import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';

const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n';
const _apiKey = 'k3j9f0s8d7f6g5h4j3k2l1z0x9c8v7';

/// A workspace document in the backup format, with a secret in every kind of place.
Map<String, dynamic> _workspace() => {
      'format': 'postpilot-backup',
      'version': 2,
      'collections': [
        {
          'name': 'Pets',
          'description': 'Pets API. Token: $_jwt',
          'variables': [
            {'key': 'baseUrl', 'value': 'https://api.test', 'enabled': true},
            {'key': 'db_password', 'value': 'pw-1', 'enabled': true},
          ],
          'auth': {'type': 'bearer', 'bearerToken': 'coll-secret', 'basicUsername': 'ada'},
          'folders': [
            {'id': 1, 'parentId': null, 'name': 'Admin'},
          ],
          'requests': [
            {
              'folderId': null,
              'name': 'Get pet',
              'method': 'get',
              'url': 'https://api.test/pets?api_key=$_apiKey&page=1',
              'headers': [
                {'key': 'Authorization', 'value': 'Bearer abc', 'enabled': true},
                {'key': 'Accept', 'value': 'application/json', 'enabled': true},
              ],
              'queryParams': [
                {'key': 'token', 'value': 'qt-1', 'enabled': true},
                {'key': 'page', 'value': '1', 'enabled': true},
              ],
              'body': {
                'type': 'raw',
                'rawContentType': 'json',
                'rawText': '{"password": "hunter2", "user": "ada"}',
                'formFields': [
                  {'key': 'secret', 'value': 'f-1', 'enabled': true},
                ],
                'urlEncodedFields': <Object>[],
                'graphqlQuery': '',
                'graphqlVariables': '{}',
              },
              'auth': {'type': 'bearer', 'bearerToken': 'bearer-abc', 'basicPassword': '', 'oauth2TokenExpiry': null},
              'scripts': {
                'assertions': [
                  {'type': 'headerEquals', 'path': 'Authorization', 'expected': 'Bearer xyz'},
                  {'type': 'statusEquals', 'path': '', 'expected': '200'},
                ],
                'extractors': <Object>[],
              },
              'examples': [
                {
                  'name': 'ok',
                  'statusCode': 200,
                  'headers': {'Set-Cookie': 'sid=abc123', 'Content-Type': 'application/json'},
                  'body': '{"access_token": "at-1", "name": "Rex"}',
                  'savedAt': '2026-01-01T00:00:00.000Z',
                },
              ],
            },
          ],
        },
      ],
      'environments': [
        {
          'name': 'Dev',
          'variables': [
            {'key': 'baseUrl', 'value': 'https://dev.test', 'secret': false, 'enabled': true},
            {'key': 'token', 'value': 'tok-1', 'secret': true, 'enabled': true},
          ],
        },
      ],
      'globals': [
        {'key': 'g_secret', 'value': 'gs-1', 'secret': true, 'enabled': true},
      ],
    };

const _allSecrets = [
  'tok-1', 'gs-1', 'pw-1', 'coll-secret', _apiKey, 'Bearer abc', 'qt-1', 'hunter2', 'f-1', 'bearer-abc', 'Bearer xyz',
  'sid=abc123', 'at-1', _jwt, //
];

/// A collection with requests that all have a bearer token, to try keys on.
Map<String, dynamic> _tokens({
  String collection = 'Pets',
  String? collectionUid,
  required List<Map<String, dynamic>> requests,
  List<Map<String, dynamic>> folders = const [],
}) =>
    {
      'format': 'postpilot-backup',
      'version': 3,
      'collections': [
        {
          'name': collection,
          'uid': ?collectionUid,
          'folders': folders,
          'requests': requests,
        },
      ],
      'environments': <Object>[],
      'globals': <Object>[],
    };

Map<String, dynamic> _request(String name, String token, {String? uid, int? folderId}) => {
      'folderId': folderId,
      'name': name,
      'uid': ?uid,
      'method': 'get',
      'url': 'https://api.test/$name',
      'auth': {'type': 'bearer', 'bearerToken': token},
    };

/// The bearer token of each request, by request name (or by uid when [byUid]).
List<String> _tokenOf(Map<String, dynamic> doc, {bool byUid = false}) => [
      for (final r in ((doc['collections'] as List).first['requests'] as List))
        '${byUid ? r['uid'] : r['name']}=${(r['auth'] as Map)['bearerToken']}',
    ];

void main() {
  group('SecretSplitter.split', () {
    test('moves a secret out of every place that can hold one, and nothing else', () {
      final split = SecretSplitter.split(_workspace());

      expect(split.secrets, {
        'env/Dev/token': 'tok-1',
        'global/g_secret': 'gs-1',
        'cvar/Pets/db_password': 'pw-1',
        'cauth/Pets/bearerToken': 'coll-secret',
        'cdesc/Pets': 'Pets API. Token: $_jwt',
        'rurl/Pets/Get pet': 'https://api.test/pets?api_key=$_apiKey&page=1',
        'rhdr/Pets/Get pet/Authorization': 'Bearer abc',
        'rqry/Pets/Get pet/token': 'qt-1',
        'rform/Pets/Get pet/secret': 'f-1',
        'rbody/Pets/Get pet/rawText': '{"password": "hunter2", "user": "ada"}',
        'rauth/Pets/Get pet/bearerToken': 'bearer-abc',
        'rtest/Pets/Get pet/headerEquals:Authorization': 'Bearer xyz',
        'rexh/Pets/Get pet/ok/Set-Cookie': 'sid=abc123',
        'rexb/Pets/Get pet/ok': '{"access_token": "at-1", "name": "Rex"}',
      });

      final text = jsonEncode(split.publicDoc);
      for (final secret in _allSecrets) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      for (final kept in ['https://dev.test', 'https://api.test/pets?api_key=&page=1', 'application/json', 'Rex', 'ada']) {
        expect(text, contains(kept), reason: kept);
      }
    });

    test('the shared file keeps its shape: only the secret values are blank', () {
      final public = SecretSplitter.split(_workspace()).publicDoc;
      final request = (public['collections'] as List).first['requests'].first as Map;

      expect((request['headers'] as List).map((h) => h['value']), ['', 'application/json']);
      expect((request['queryParams'] as List).map((q) => q['value']), ['', '1']);
      expect(request['body']['rawText'], '{"password": "", "user": "ada"}');
      expect(((request['scripts'] as Map)['assertions'] as List).map((a) => a['expected']), ['', '200']);
      expect(request['examples'].first['headers'], {'Set-Cookie': '', 'Content-Type': 'application/json'});
      expect(request['examples'].first['body'], '{"access_token": "", "name": "Rex"}');
      expect(request['url'], 'https://api.test/pets?api_key=&page=1');
    });

    test('a template and a document without secrets are left alone', () {
      final doc = _tokens(requests: [
        {
          ..._request('List', '{{token}}'),
          'headers': [
            {'key': 'Authorization', 'value': 'Bearer {{token}}', 'enabled': true},
          ],
          'body': {'type': 'raw', 'rawText': '{"password": "{{password}}"}'},
        },
      ]);
      final split = SecretSplitter.split(doc);
      expect(split.secrets, isEmpty);
      expect(jsonEncode(split.publicDoc), jsonEncode(doc));
    });

    test('does not change the document it is given', () {
      final doc = _workspace();
      final before = jsonEncode(doc);
      SecretSplitter.split(doc);
      expect(jsonEncode(doc), before);
    });
  });

  group('SecretSplitter.merge', () {
    test('puts every secret back, so split then merge gives the original', () {
      final split = SecretSplitter.split(_workspace());
      expect(jsonEncode(SecretSplitter.merge(split.publicDoc, split.secrets)), jsonEncode(_workspace()));
    });

    test('never overwrites a value somebody has set', () {
      final split = SecretSplitter.split(_workspace());
      final shared = jsonDecode(jsonEncode(split.publicDoc)) as Map<String, dynamic>;
      final request = (shared['collections'] as List).first['requests'].first as Map;
      (request['headers'] as List).first['value'] = 'Bearer shared-default';
      request['body']['rawText'] = '{"password": "shared", "user": "ada"}';

      final merged = SecretSplitter.merge(shared, split.secrets);

      final mergedRequest = (merged['collections'] as List).first['requests'].first as Map;
      expect((mergedRequest['headers'] as List).first['value'], 'Bearer shared-default');
      expect(mergedRequest['body']['rawText'], '{"password": "shared", "user": "ada"}');
      expect(mergedRequest['auth']['bearerToken'], 'bearer-abc', reason: 'the blank ones are still filled');
    });

    test('keeps what a teammate changed around a secret', () {
      final split = SecretSplitter.split(_workspace());
      final theirs = jsonDecode(jsonEncode(split.publicDoc)) as Map<String, dynamic>;
      final request = (theirs['collections'] as List).first['requests'].first as Map;
      request['url'] = 'https://api.test/animals?api_key=&page=2';
      request['body']['rawText'] = '{"password": "", "user": "grace", "extra": 1}';

      final merged = SecretSplitter.merge(theirs, split.secrets);

      final mergedRequest = (merged['collections'] as List).first['requests'].first as Map;
      expect(mergedRequest['url'], 'https://api.test/animals?api_key=$_apiKey&page=2');
      expect(mergedRequest['body']['rawText'], '{"password": "hunter2", "user": "grace", "extra": 1}');
    });
  });

  group('keys that survive what a teammate does', () {
    test('a request with a uid keeps its secret when it is renamed, moved to another folder or reordered', () {
      final mine = _tokens(collectionUid: 'c-1', requests: [
        _request('Get pet', 'token-A', uid: 'u-1'),
        _request('Get pet', 'token-B', uid: 'u-2'),
      ]);
      final split = SecretSplitter.split(mine);
      expect(split.secrets.keys, containsAll(['rauth/@c-1/@u-1/bearerToken', 'rauth/@c-1/@u-2/bearerToken']));

      // The teammate renames the collection and the first request, and puts them the other way round.
      final theirs = jsonDecode(jsonEncode(split.publicDoc)) as Map<String, dynamic>;
      final collection = (theirs['collections'] as List).first as Map<String, dynamic>;
      collection['name'] = 'Animals';
      final requests = (collection['requests'] as List).reversed.toList();
      requests.last['name'] = 'Fetch pet';
      requests.last['folderId'] = 1;
      collection['requests'] = requests;
      collection['folders'] = [
        {'id': 1, 'parentId': null, 'name': 'Moved'},
      ];

      final merged = SecretSplitter.merge(theirs, split.secrets);

      expect(_tokenOf(merged, byUid: true), ['u-2=token-B', 'u-1=token-A']);
    });

    test('same-named requests in different folders are told apart by their folders, not their order', () {
      final folders = [
        {'id': 1, 'parentId': null, 'name': 'Admin'},
        {'id': 2, 'parentId': null, 'name': 'Public'},
      ];
      final mine = _tokens(folders: folders, requests: [
        _request('Get user', 'admin-token', folderId: 1),
        _request('Get user', 'public-token', folderId: 2),
      ]);
      final split = SecretSplitter.split(mine);
      expect(split.secrets.keys, containsAll(['rauth/Pets/Admin/Get user/bearerToken', 'rauth/Pets/Public/Get user/bearerToken']));

      final theirs = jsonDecode(jsonEncode(split.publicDoc)) as Map<String, dynamic>;
      final collection = (theirs['collections'] as List).first as Map<String, dynamic>;
      collection['requests'] = (collection['requests'] as List).reversed.toList();

      final merged = SecretSplitter.merge(theirs, split.secrets);

      final tokens = {
        for (final r in ((merged['collections'] as List).first['requests'] as List)) r['folderId']: r['auth']['bearerToken'],
      };
      expect(tokens, {1: 'admin-token', 2: 'public-token'});
    });

    test('nested folders make the path: Parent/Child/Request', () {
      final folders = [
        {'id': 1, 'parentId': null, 'name': 'Parent'},
        {'id': 2, 'parentId': 1, 'name': 'Child'},
      ];
      final split = SecretSplitter.split(_tokens(folders: folders, requests: [_request('Req', 't', folderId: 2)]));
      expect(split.secrets.keys, ['rauth/Pets/Parent/Child/Req/bearerToken']);
    });

    test('a file written before folders and uids existed still fills in its secrets', () {
      final folders = [
        {'id': 1, 'parentId': null, 'name': 'Admin'},
        {'id': 2, 'parentId': null, 'name': 'Public'},
      ];
      final doc = _tokens(folders: folders, requests: [
        _request('Get user', '', folderId: 1),
        _request('Get user', '', folderId: 2),
        _request('Solo', '', folderId: null),
      ]);

      // The keys the previous version wrote: by collection and request name, `#2` for the second of a name.
      final merged = SecretSplitter.merge(doc, {
        'rauth/Pets/Get user/bearerToken': 'first',
        'rauth/Pets/Get user#2/bearerToken': 'second',
        'rauth/Pets/Solo/bearerToken': 'solo',
      });

      expect(_tokenOf(merged), ['Get user=first', 'Get user=second', 'Solo=solo']);
    });

    test('a collection that gained a uid still finds the secrets saved under its name', () {
      final doc = _tokens(collectionUid: 'c-1', requests: [_request('Get pet', '', uid: 'u-1')]);
      final merged = SecretSplitter.merge(doc, {'rauth/Pets/Get pet/bearerToken': 'old-format'});
      expect(_tokenOf(merged), ['Get pet=old-format']);
    });
  });

  group('secrets that match nothing', () {
    final mine = {
      'environments': [
        {
          'name': 'Dev',
          'variables': [
            {'key': 'token', 'value': 'tok-1', 'secret': true, 'enabled': true},
          ],
        },
        {
          'name': 'Prod',
          'variables': [
            {'key': 'token', 'value': 'tok-2', 'secret': true, 'enabled': true},
          ],
        },
      ],
    };

    Map<String, dynamic> renamed(Map<String, dynamic> doc) {
      final copy = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
      ((copy['environments'] as List).first as Map)['name'] = 'Development';
      return copy;
    }

    test('are found, and kept as unmatched when the file came from somebody else', () {
      final split = SecretSplitter.split(mine);
      final theirs = renamed(split.publicDoc);

      expect(SecretSplitter.orphans(theirs, split.secrets), {'env/Dev/token': 'tok-1'});

      final merged = SecretSplitter.merge(theirs, split.secrets);
      final kept = SecretSplitter.split(merged);
      expect(kept.secrets, {'env/Prod/token': 'tok-2'});

      final local = SecretSplitter.retain(
        doc: kept.publicDoc,
        secrets: kept.secrets,
        previous: LocalSecrets(secrets: split.secrets),
        keepOrphans: true,
      );
      expect(local.secrets, {'env/Prod/token': 'tok-2'});
      expect(local.unmatched, {'env/Dev/token': 'tok-1'}, reason: 'the pull must not lose it');
    });

    test('come back when the name matches again', () {
      final split = SecretSplitter.split(mine);
      final kept = LocalSecrets(secrets: const {'env/Prod/token': 'tok-2'}, unmatched: const {'env/Dev/token': 'tok-1'});

      final merged = SecretSplitter.merge(split.publicDoc, kept.all);

      expect(jsonEncode(merged), jsonEncode(mine));
    });

    test('an ordinary save keeps the unmatched ones, drops the ones that found their place, and forgets removed secrets', () {
      final split = SecretSplitter.split(mine);
      final previous = LocalSecrets(
        secrets: const {'env/Prod/token': 'old-removed-value', 'env/Gone/token': 'x'},
        unmatched: const {'env/Old/token': 'old', 'env/Dev/token': 'now-matched'},
      );

      final local = SecretSplitter.retain(doc: split.publicDoc, secrets: split.secrets, previous: previous);

      expect(local.secrets, split.secrets);
      expect(local.unmatched, {'env/Old/token': 'old'}, reason: 'Dev matches again; the removed secrets are not kept');
    });

    test('the unmatched list is capped, oldest first', () {
      final many = {for (var i = 0; i < SecretSplitter.maxUnmatched + 5; i++) 'env/E$i/k': 'v$i'};
      final capped = SecretSplitter.capUnmatched(many);
      expect(capped.length, SecretSplitter.maxUnmatched);
      expect(capped.keys.first, 'env/E5/k');
      expect(capped.keys.last, 'env/E${SecretSplitter.maxUnmatched + 4}/k');
    });
  });

  group('SecretSplitter.exposed', () {
    test('with the split on, nothing is left to warn about in a document the split understands', () {
      expect(SecretSplitter.exposed(_workspace(), keepLocal: true), isEmpty);
    });

    test('with the split off, every secret is named, in words a person can read', () {
      final names = SecretSplitter.exposed(_workspace(), keepLocal: false);
      expect(names, hasLength(14));
      expect(
        names,
        containsAll([
          'Dev › token',
          'Globals › g_secret',
          'Pets › db_password',
          'Pets › Get pet › URL',
          'Pets › Get pet › Authorization header',
          'Pets › Get pet › token parameter',
          'Pets › Get pet › body',
          'Pets › Get pet › auth bearerToken',
          'Pets › Get pet › example "ok" › Set-Cookie header',
        ]),
      );
    });

    test('with the split on, a secret-looking value it did not recognise is still reported', () {
      final doc = _workspace();
      ((doc['environments'] as List).first['variables'] as List).add({'key': 'access_token', 'value': 'at-9', 'secret': false, 'enabled': true});
      ((doc['globals'] as List)).add({'key': 'note', 'value': 'ghp_abcdefghijklmnopqrstuvwxyz0123456789', 'secret': false, 'enabled': true});
      final request = ((doc['collections'] as List).first['requests'] as List).first as Map;
      (request['headers'] as List).add({'key': 'X-Custom', 'value': _jwt, 'enabled': true});

      expect(SecretSplitter.exposed(doc, keepLocal: true), [
        'Dev › access_token',
        'Globals › note',
        'Pets › Get pet › X-Custom header',
      ]);
    });

    test('an ordinary workspace is not reported at all', () {
      final doc = _tokens(requests: [
        {
          ..._request('List', ''),
          'headers': [
            {'key': 'Accept', 'value': 'application/json', 'enabled': true},
          ],
          'body': {'type': 'raw', 'rawText': '{"title": "Password reset", "key": "color"}'},
        },
      ]);
      expect(SecretSplitter.exposed(doc, keepLocal: true), isEmpty);
      expect(SecretSplitter.exposed(doc, keepLocal: false), isEmpty);
    });
  });

  group('the Git state of a linked collection', () {
    final full = SyncDoc(
      uid: 'r1',
      kind: SyncKind.request,
      parentUid: 'c1',
      name: 'Login',
      data: {
        'url': 'https://api.test/login',
        'headers': [
          {'key': 'Authorization', 'value': 'Bearer abc', 'enabled': true},
        ],
        'auth': {'type': 'bearer', 'bearerToken': 'git-secret'},
      },
    );
    final clean = SyncDoc(uid: 'r2', kind: SyncKind.request, parentUid: 'c1', name: 'Health', data: {'url': 'https://api.test/health'});

    Map<String, dynamic> linked() => {
          'collections': [
            {
              'name': 'Pets',
              'uid': 'c1',
              'git': {
                'provider': 'github',
                'owner': 'acme',
                'repo': 'pets',
                'branch': 'main',
                'includeSecrets': true,
                'base': [
                  {'uid': 'r1', 'path': 'login.request.json', 'blobSha': 'sha1', 'doc': full.canonicalText},
                  {'uid': 'r2', 'path': 'health.request.json', 'blobSha': 'sha2', 'doc': clean.canonicalText},
                ],
              },
              'requests': <Object>[],
            },
          ],
          'environments': <Object>[],
          'globals': <Object>[],
        };

    test('a synced doc that holds credentials (a collection that syncs its secrets) does not carry them into workspace.json', () {
      final split = SecretSplitter.split(linked());

      expect(split.secrets.keys, ['gbase/@c1/r1']);
      expect(split.secrets['gbase/@c1/r1'], full.canonicalText);
      final text = jsonEncode(split.publicDoc);
      expect(text, isNot(contains('git-secret')));
      expect(text, isNot(contains('Bearer abc')));
      final base = (((split.publicDoc['collections'] as List).first as Map)['git'] as Map)['base'] as List;
      expect((base[0] as Map)['doc'], SecretFields.stripDoc(full).canonicalText);
      expect((base[1] as Map)['doc'], clean.canonicalText, reason: 'a doc without credentials is not rewritten');
      expect(jsonEncode(SecretSplitter.merge(split.publicDoc, split.secrets)), jsonEncode(linked()), reason: 'and they come back as they were');
    });

    test('the warning counts them when the split is off', () {
      expect(SecretSplitter.exposed(linked(), keepLocal: false), ['Pets › Git sync state']);
      expect(SecretSplitter.exposed(linked(), keepLocal: true), isEmpty);
    });
  });

  group('the local file', () {
    test('round-trips its secrets and its unmatched ones, and says where the secrets are kept', () {
      final text = SecretSplitter.encodeLocal({'a': '1'}, unmatched: {'b': '2'});

      expect(SecretSplitter.decodeLocal(text), {'a': '1'});
      final file = SecretSplitter.decodeLocalFile(text);
      expect(file.secrets, {'a': '1'});
      expect(file.unmatched, {'b': '2'});
      expect(file.all, {'b': '2', 'a': '1'});
      expect(text, contains('workspace.json'));
      expect(text, isNot(contains('this device')), reason: 'the file can sit in a synced folder');
      expect(SecretSplitter.encodeLocal({'a': '1'}), isNot(contains('unmatched')));
    });

    test('a file from before unmatched existed, or a damaged one, still opens', () {
      expect(SecretSplitter.decodeLocalFile('{"version": 1, "secrets": {"a": "1"}}').unmatched, isEmpty);
      expect(SecretSplitter.decodeLocalFile('{broken').secrets, isEmpty);
      expect(SecretSplitter.decodeLocalFile(null).secrets, isEmpty);
      expect(SecretSplitter.decodeLocalFile('{"secrets": {"a": 5, "b": "ok"}, "unmatched": 3}').secrets, {'b': 'ok'});
    });
  });
}
