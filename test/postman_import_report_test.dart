import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';

/// A one-request collection around [request], so a test only writes the part it is about.
String _collection(Object request, {Map<String, Object?> extra = const {}, String name = 'R'}) => jsonEncode({
  'info': {'name': 'C'},
  'item': [
    {'name': name, 'request': request, ...extra},
  ],
});

PostmanRequestItem _only(ParsedPostmanCollection parsed) => parsed.items.single as PostmanRequestItem;

List<String> _skipped(ParsedPostmanCollection parsed) => [for (final n in parsed.notes) if (n.skipped) n.message];
List<String> _adjusted(ParsedPostmanCollection parsed) => [for (final n in parsed.notes) if (!n.skipped) n.message];

void main() {
  group('request shapes', () {
    test('the short form "request": "<url>" is a GET to that URL', () {
      final parsed = PostmanCollectionParser.parse(_collection('https://api.test/ping'));
      final request = _only(parsed);
      expect(request.method, HttpMethod.get);
      expect(request.url, 'https://api.test/ping');
      expect(parsed.notes, isEmpty);
    });

    test('a request that is neither an object nor a string is skipped with a note, the rest still imports', () {
      final json = jsonEncode({
        'info': {'name': 'C'},
        'item': [
          {'name': 'Broken', 'request': 42},
          'not an item',
          {'name': 'Fine', 'request': 'https://a.test'},
        ],
      });
      final parsed = PostmanCollectionParser.parse(json);
      expect(parsed.items.map((i) => i.name), ['Fine']);
      expect(_skipped(parsed), [
        'Request "Broken": its "request" is neither an object nor a URL, so it was not imported.',
        'An entry of "item" is not an object, so it was not imported.',
      ]);
    });

    test('a JSON value that is not an object is rejected with a message, not a cast error', () {
      expect(
        () => PostmanCollectionParser.parse('[1,2]'),
        throwsA(isA<ImportException>().having((e) => e.message, 'message', contains('not a Postman collection'))),
      );
    });

    test('a URL built from parts when the export has no raw', () {
      final parsed = PostmanCollectionParser.parse(
        _collection({
          'method': 'GET',
          'url': {
            'protocol': 'https',
            'host': ['api', 'test'],
            'port': '8443',
            'path': ['v1', 'users'],
            'query': [
              {'key': 'a', 'value': '1'},
              {'key': 'b', 'value': '2', 'disabled': true},
              {'key': 'c', 'value': '3'},
            ],
          },
        }),
      );
      final request = _only(parsed);
      expect(request.url, 'https://api.test:8443/v1/users?a=1&c=3');
      expect(request.queryParams.map((p) => p.key), ['b'], reason: 'only the disabled one is kept apart');
    });

    test('a header block given as one text of "Name: value" lines', () {
      final parsed = PostmanCollectionParser.parse(
        _collection({'method': 'GET', 'url': 'https://a.test', 'header': 'Accept: application/json\nX-Trace: 1: 2'}),
      );
      expect(_only(parsed).headers.map((h) => (h.key, h.value)), [('Accept', 'application/json'), ('X-Trace', '1: 2')]);
    });
  });

  group('path variables', () {
    test(':name segments are filled from url.variable, others are left alone and reported', () {
      final parsed = PostmanCollectionParser.parse(
        _collection({
          'method': 'GET',
          'url': {
            'raw': '{{base}}/users/:id/posts/:postId?x=:id',
            'variable': [
              {'key': 'id', 'value': '42'},
              {'key': 'postId', 'value': ''},
              {'key': 'unused', 'value': 'zzz'},
            ],
          },
        }),
      );
      // `?x=:id` is not a path segment, so only the one after a slash is replaced.
      expect(_only(parsed).url, '{{base}}/users/42/posts/:postId?x=:id');
      expect(_skipped(parsed), ['Request "R": path variable :postId has no value, so the URL keeps :postId.']);
      expect(_adjusted(parsed), ['Request "R": path variable :id was written into the URL (PostPilot has no :path variables).']);
    });

    test('a port is not a path variable, and a {{variable}} value is kept for the app to resolve', () {
      final parsed = PostmanCollectionParser.parse(
        _collection({
          'method': 'GET',
          'url': {
            'raw': 'http://localhost:3000/items/:itemId',
            'variable': [
              {'key': 'itemId', 'value': '{{currentItem}}'},
              {'key': '3000', 'value': 'nope'},
            ],
          },
        }),
      );
      expect(_only(parsed).url, 'http://localhost:3000/items/{{currentItem}}');
    });

    test('two filled variables are reported together', () {
      final parsed = PostmanCollectionParser.parse(
        _collection({
          'method': 'GET',
          'url': {
            'raw': 'https://a.test/:a/:b',
            'variable': [
              {'key': 'a', 'value': '1'},
              {'key': 'b', 'value': '2'},
            ],
          },
        }),
      );
      expect(_only(parsed).url, 'https://a.test/1/2');
      expect(_adjusted(parsed), ['Request "R": path variables :a, :b were written into the URL (PostPilot has no :path variables).']);
    });
  });

  group('folder variables', () {
    String collection() => jsonEncode({
      'info': {'name': 'C'},
      'variable': [
        {'key': 'host', 'value': 'https://a.test'},
        {'key': 'same', 'value': '1'},
      ],
      'item': [
        {
          'name': 'Admin',
          'variable': [
            {'key': 'role', 'value': 'admin'},
            {'key': 'host', 'value': 'https://other.test'},
            {'key': 'same', 'value': '1'},
            {'key': 'off', 'value': 'x', 'disabled': true},
          ],
          'item': [
            {'name': 'Nested', 'variable': [{'key': 'deep', 'value': 'd'}], 'item': []},
          ],
        },
      ],
    });

    test('stay on their folder, the collection keeps only its own', () {
      final parsed = PostmanCollectionParser.parse(collection());
      expect(parsed.variables.map((v) => (v.key, v.value, v.enabled)), [
        ('host', 'https://a.test', true),
        ('same', '1', true),
      ]);
      final admin = parsed.items.single as PostmanFolderItem;
      expect(admin.variables.map((v) => (v.key, v.value, v.enabled)), [
        ('role', 'admin', true),
        ('host', 'https://other.test', true),
        ('same', '1', true),
        ('off', 'x', false),
      ]);
      final nested = admin.children.single as PostmanFolderItem;
      expect(nested.variables.map((v) => (v.key, v.value)), [('deep', 'd')]);
    });

    test('a folder may define a name the collection has too, that is not a conflict and not reported', () {
      final parsed = PostmanCollectionParser.parse(collection());
      expect(_skipped(parsed), isEmpty);
      expect(_adjusted(parsed), isEmpty);
    });
  });

  group('authentication', () {
    test('oauth1, hawk and ntlm are reported, and import as no authentication', () {
      Map<String, Object?> item(String type) => {
        'name': type,
        'request': {
          'method': 'GET',
          'url': 'https://a.test',
          'auth': {'type': type, type: <Object>[]},
        },
      };
      final parsed = PostmanCollectionParser.parse(
        jsonEncode({
          'info': {'name': 'C'},
          'item': [item('oauth1'), item('hawk'), item('ntlm')],
        }),
      );
      expect(parsed.items.map((i) => (i as PostmanRequestItem).auth.type), [AuthType.none, AuthType.none, AuthType.none]);
      expect(_skipped(parsed), [
        'Request "oauth1": "oauth1" authentication is not supported, so it was imported without authentication.',
        'Request "hawk": "hawk" authentication is not supported, so it was imported without authentication.',
        'Request "ntlm": "ntlm" authentication is not supported, so it was imported without authentication.',
      ]);
      expect(parsed.skippedCount, 3);
    });

    test('an unsupported folder auth is reported once and kept on the folder as none', () {
      final parsed = PostmanCollectionParser.parse(
        jsonEncode({
          'info': {'name': 'C'},
          'item': [
            {
              'name': 'Secure',
              'auth': {'type': 'edgegrid'},
              'item': [
                {'name': 'A', 'request': 'https://a.test'},
                {'name': 'B', 'request': 'https://b.test'},
              ],
            },
          ],
        }),
      );
      final folder = parsed.items.single as PostmanFolderItem;
      expect(folder.auth?.type, AuthType.none);
      expect(folder.children.map((c) => (c as PostmanRequestItem).auth.type), [AuthType.inherit, AuthType.inherit],
          reason: 'the requests inherit the folder\'s (no) auth, they carry no copy of it');
      expect(_skipped(parsed), ['Folder "Secure": "edgegrid" authentication is not supported, so it was imported without authentication.']);
    });

    test('supported auth types and "noauth" produce no note', () {
      final parsed = PostmanCollectionParser.parse(
        _collection({
          'method': 'GET',
          'url': 'https://a.test',
          'auth': {
            'type': 'bearer',
            'bearer': [
              {'key': 'token', 'value': 't'},
            ],
          },
        }),
      );
      expect(_only(parsed).auth.type, AuthType.bearer);
      expect(parsed.notes, isEmpty);
    });
  });

  group('other things that used to vanish silently', () {
    test('protocolProfileBehavior (keys only, no values) and saved example responses', () {
      final parsed = PostmanCollectionParser.parse(
        _collection(
          'https://a.test',
          extra: {
            'protocolProfileBehavior': {'disableBodyPruning': true, 'followRedirects': false},
            'response': [
              {'name': 'ok'},
              {'name': 'fail'},
            ],
          },
        ),
      );
      expect(_skipped(parsed), [
        'Request "R": protocolProfileBehavior (disableBodyPruning, followRedirects) was not imported.',
        'Request "R": 2 saved example responses were not imported.',
      ]);
    });

    test('an empty protocolProfileBehavior or response list says nothing', () {
      final parsed = PostmanCollectionParser.parse(
        _collection('https://a.test', extra: {'protocolProfileBehavior': <String, Object?>{}, 'response': <Object>[]}),
      );
      expect(parsed.notes, isEmpty);
    });

    test('file form fields and a body sent from a file', () {
      final parsed = PostmanCollectionParser.parse(
        jsonEncode({
          'info': {'name': 'C'},
          'item': [
            {
              'name': 'Upload',
              'request': {
                'method': 'POST',
                'url': 'https://a.test',
                'body': {
                  'mode': 'formdata',
                  'formdata': [
                    {'key': 'name', 'value': 'x', 'type': 'text'},
                    {'key': 'avatar', 'type': 'file', 'src': '/tmp/a.png'},
                  ],
                },
              },
            },
            {
              'name': 'Binary',
              'request': {
                'method': 'POST',
                'url': 'https://a.test',
                'body': {
                  'mode': 'file',
                  'file': {'src': '/tmp/b.bin'},
                },
              },
            },
          ],
        }),
      );
      final upload = parsed.items.first as PostmanRequestItem;
      expect(upload.body.type, BodyType.formData);
      expect(upload.body.formFields.map((f) => (f.key, f.value, f.isFile)), [('name', 'x', false), ('avatar', '/tmp/a.png', true)]);
      final binary = (parsed.items.last as PostmanRequestItem).body;
      expect(binary.type, BodyType.binary);
      expect(binary.binaryFile!.value, '/tmp/b.bin');
      expect(_skipped(parsed), isEmpty, reason: 'both come in as file references now');
      expect(_adjusted(parsed), [
        '2 file paths point to this machine, so they will not work for a teammate. '
            'Replace the start of the path with a variable, for example {{uploadDir}}/avatar.png.',
      ]);
    });
  });

  group('scripts', () {
    Map<String, Object?> event(String listen, List<String> lines) => {
      'listen': listen,
      'script': {'type': 'text/javascript', 'exec': lines},
    };

    test('a request\'s test script becomes its assertions and extractors', () {
      final parsed = PostmanCollectionParser.parse(
        _collection(
          'https://a.test/login',
          extra: {
            'event': [
              event('test', [
                'var jsonData = pm.response.json();',
                'pm.test("ok", function () { pm.response.to.have.status(200); });',
                'pm.environment.set("token", jsonData.access_token);',
              ]),
            ],
          },
        ),
      );
      final request = _only(parsed);
      expect(request.assertions.map((a) => (a.type, a.expected)), [(AssertionType.statusEquals, '200')]);
      expect(request.extractors.map((x) => (x.path, x.variableKey)), [('access_token', 'token')]);
      expect(parsed.notes, isEmpty);
      expect((parsed.assertionCount, parsed.extractorCount), (1, 1));
    });

    test('statements that cannot be translated are counted and listed with the request name', () {
      final parsed = PostmanCollectionParser.parse(
        _collection(
          'https://a.test',
          extra: {
            'event': [
              event('test', [
                'pm.response.to.have.status(200);',
                'pm.expect(pm.response.json().items.length).to.be.above(0);',
                'postman.setNextRequest("Other");',
              ]),
            ],
          },
        ),
      );
      expect(_only(parsed).assertions, hasLength(1));
      expect(_skipped(parsed), [
        'Request "R": test script statement not converted: pm.expect(pm.response.json().items.length).to.be.above(0)',
        'Request "R": test script statement not converted: postman.setNextRequest("Other")',
      ]);
      expect(parsed.skippedCount, 2);
    });

    test('a pre-request script is reported once, as a whole, with its first statement', () {
      final parsed = PostmanCollectionParser.parse(
        _collection(
          'https://a.test',
          extra: {
            'event': [
              event('prerequest', ['console.log("hi");', 'const ts = Date.now();', 'pm.environment.set("ts", ts);']),
              event('prerequest', ['// only a comment']),
            ],
          },
        ),
      );
      expect(_skipped(parsed), [
        'Request "R": pre-request script (2 statements) was not imported, PostPilot has no scripts that run before a request. '
            'It starts with: const ts = Date.now()',
      ]);
    });

    test('scripts that are only a link, and disabled events', () {
      final parsed = PostmanCollectionParser.parse(
        _collection(
          'https://a.test',
          extra: {
            'event': [
              {
                'listen': 'test',
                'script': {'src': 'https://cdn.test/t.js'},
              },
              {
                'listen': 'prerequest',
                'script': {'src': 'https://cdn.test/p.js'},
              },
              {...event('test', ['pm.response.to.have.status(500);']), 'disabled': true},
            ],
          },
        ),
      );
      expect(_only(parsed).assertions, isEmpty);
      expect(_skipped(parsed), [
        'Request "R": a test script loaded from a URL was not imported.',
        'Request "R": a pre-request script loaded from a URL was not imported.',
      ]);
    });

    test('collection and folder test scripts stay on the collection and the folder, where they apply to every request below', () {
      final parsed = PostmanCollectionParser.parse(
        jsonEncode({
          'info': {'name': 'C'},
          'event': [event('test', ['pm.expect(pm.response.responseTime).to.be.below(800);'])],
          'item': [
            {
              'name': 'Folder',
              'event': [event('test', ['pm.response.to.have.header("X-Id");', 'weird();'])],
              'item': [
                {
                  'name': 'Inner',
                  'request': 'https://a.test',
                  'event': [event('test', ['pm.response.to.have.status(201);'])],
                },
              ],
            },
            {'name': 'Top', 'request': 'https://b.test'},
          ],
        }),
      );
      final folder = parsed.items.first as PostmanFolderItem;
      final inner = folder.children.single as PostmanRequestItem;
      final top = parsed.items.last as PostmanRequestItem;
      expect(parsed.assertions.map((a) => a.type), [AssertionType.responseTimeBelowMs], reason: 'the collection\'s own test');
      expect(folder.assertions.map((a) => a.type), [AssertionType.headerExists], reason: 'the folder\'s own test');
      expect(inner.assertions.map((a) => a.type), [AssertionType.statusEquals], reason: 'a request keeps only its own');
      expect(top.assertions, isEmpty);
      // The untranslatable statement is reported once, at the folder that holds it, not per request.
      expect(_skipped(parsed), ['Folder "Folder": test script statement not converted: weird()']);
      expect(parsed.assertionCount, 3, reason: 'one on the collection, one on the folder, one on the request: each counted once');
    });

    test('collectionVariables.set is converted but reported as a change', () {
      final parsed = PostmanCollectionParser.parse(
        _collection(
          'https://a.test',
          extra: {
            'event': [
              event('test', ['pm.collectionVariables.set("id", pm.response.json().id);']),
            ],
          },
        ),
      );
      expect(_only(parsed).extractors.single.variableKey, 'id');
      expect(_skipped(parsed), isEmpty);
      expect(_adjusted(parsed), hasLength(1));
      expect(_adjusted(parsed).single, startsWith('Request "R": pm.collectionVariables.set("id") became an extractor'));
    });
  });

  test('counts folders and requests of the whole tree', () {
    final parsed = PostmanCollectionParser.parse(
      jsonEncode({
        'info': {'name': 'C'},
        'item': [
          {
            'name': 'F1',
            'item': [
              {'name': 'F2', 'item': [{'name': 'a', 'request': 'https://a.test'}]},
              {'name': 'b', 'request': 'https://b.test'},
            ],
          },
          {'name': 'c', 'request': 'https://c.test'},
        ],
      }),
    );
    expect((parsed.folderCount, parsed.requestCount), (2, 3));
  });
}
