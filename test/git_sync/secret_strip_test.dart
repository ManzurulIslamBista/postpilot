import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/data/mappers/folder_doc_mapper.dart';
import 'package:postpilot/features/git_sync/data/mappers/request_doc_mapper.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';

const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n';

/// A request doc as the database mapper would produce it, with a credential in every place that can hold one.
SyncDoc _request({Map<String, Object?> data = const {}}) => RequestDocMapper.canonical(SyncDoc(
      uid: 'r1',
      kind: SyncKind.request,
      parentUid: 'c1',
      name: 'Login',
      data: {
        'method': 'post',
        'url': 'https://api.test/login?api_key=k3j9f0s8d7f6g5h4j3k2l1z0x9c8v7&page=1',
        'headers': [
          {'key': 'Authorization', 'value': 'Bearer abc', 'enabled': true},
          {'key': 'Accept', 'value': 'application/json', 'enabled': true},
        ],
        'queryParams': <Object?>[],
        'body': {
          'type': 'raw',
          'rawContentType': 'xml',
          'rawText': '<Login><UserName>ada</UserName><wsse:Password>hunter2</wsse:Password></Login>',
          'formFields': <Object?>[],
          'urlEncodedFields': <Object?>[],
          'graphqlQuery': 'mutation { login(email: "a@b.c", password: "s3cret") { id } }',
          'graphqlVariables': '{"pin": 1234, "user": "ada"}',
        },
        'auth': {'type': 'inherit'},
        'tests': {
          'assertions': [
            {'type': 'headerEquals', 'path': 'Authorization', 'expected': 'Bearer abc'},
            {'type': 'jsonPathEquals', 'path': 'data.access_token', 'expected': 'tok-1'},
            {'type': 'jsonPathEquals', 'path': 'data.items[0].password', 'expected': 'pw-1'},
            {'type': 'jsonPathEquals', 'path': 'data.name', 'expected': 'ada'},
            {'type': 'jsonPathEquals', 'path': 'auth.user.email', 'expected': 'a@b.c'},
            {'type': 'bodyContains', 'path': '', 'expected': '"password":"hunter2"'},
            {'type': 'bodyContains', 'path': '', 'expected': 'welcome'},
            {'type': 'statusEquals', 'path': '', 'expected': '200'},
          ],
          'extractors': <Object?>[],
        },
        'description': 'Log in. Example token: $_jwt',
        ...data,
      },
    ));

Map<String, Object?> _body(SyncDoc doc) => Map<String, Object?>.from(doc.data['body']! as Map);
List<Map> _assertions(SyncDoc doc) => ((doc.data['tests']! as Map)['assertions'] as List).cast<Map>();

void main() {
  group('SecretFields.stripDoc on a request', () {
    final stripped = SecretFields.stripDoc(_request());

    test('blanks the credentials of the body formats it did not know', () {
      final body = _body(stripped);
      expect(body['rawText'], '<Login><UserName>ada</UserName><wsse:Password></wsse:Password></Login>');
      expect(body['graphqlQuery'], 'mutation { login(email: "a@b.c", password: "") { id } }');
      expect(body['graphqlVariables'], '{"pin": "", "user": "ada"}');
    });

    test('keeps the headers and the URL parts that were already handled', () {
      expect(stripped.data['url'], 'https://api.test/login?api_key=&page=1');
      final headers = (stripped.data['headers']! as List).cast<Map>();
      expect(headers.map((h) => h['value']), ['', 'application/json']);
    });

    test('blanks what an assertion expects when it is a credential, and nothing else', () {
      expect(_assertions(stripped).map((a) => a['expected']), [
        '', // Authorization header
        '', // data.access_token
        '', // data.items[0].password
        'ada', // data.name
        'a@b.c', // auth.user.email: "auth" is a parent, the name is email
        '"password":""', // credentials inside the text a body must contain
        'welcome',
        '200',
      ]);
    });

    test('removes an unmistakable credential from the description, not the prose around it', () {
      expect(stripped.data['description'], 'Log in. Example token: ');
      final prose = SecretFields.stripDoc(_request(data: {'description': 'Send the password as password=YOUR_PASSWORD.'}));
      expect(prose.data['description'], 'Send the password as password=YOUR_PASSWORD.');
    });

    test('is idempotent', () {
      expect(SecretFields.stripDoc(stripped), stripped);
    });

    test('leaves a doc without credentials untouched', () {
      final plain = _request(data: {
        'url': 'https://api.test/items?page=1',
        'headers': <Object?>[],
        'body': {
          'type': 'raw',
          'rawContentType': 'json',
          'rawText': '{"title": "Password reset", "key": "color", "max_tokens": 100}',
          'formFields': <Object?>[],
          'urlEncodedFields': <Object?>[],
          'graphqlQuery': 'query { items(first: 10) { id } }',
          'graphqlVariables': '{}',
        },
        'tests': {
          'assertions': [
            {'type': 'jsonPathEquals', 'path': 'data.title', 'expected': 'Password reset'},
            {'type': 'bodyContains', 'path': '', 'expected': 'ok'},
          ],
          'extractors': <Object?>[],
        },
        'description': 'Lists the items. See https://docs.test/items?page=2',
      });
      // The auth map always loses its credential keys (empty or not): that is not what is tested here.
      Map<String, Object?> withoutAuth(SyncDoc doc) => {...doc.data}..remove('auth');
      expect(withoutAuth(SecretFields.stripDoc(plain)), withoutAuth(plain));
    });
  });

  group('putting local credentials back into a stripped doc', () {
    test('a stripped request taken as the target keeps every local credential, and equals the original', () {
      final full = _request();
      final target = SecretFields.stripDoc(full);

      final applied = RequestDocMapper.canonical(target, local: full);

      expect(applied, full);
    });

    test('what somebody else changed is applied, and the credentials stay local', () {
      final full = _request();
      final target = SecretFields.stripDoc(_request(data: {
        'body': {
          ..._body(full),
          'graphqlQuery': 'mutation { login(email: "new@b.c", password: "") { id } }',
        },
        'tests': {
          'assertions': [
            {'type': 'jsonPathEquals', 'path': 'data.access_token', 'expected': ''},
            {'type': 'headerEquals', 'path': 'Authorization', 'expected': ''},
            {'type': 'statusEquals', 'path': '', 'expected': '201'},
          ],
          'extractors': <Object?>[],
        },
      }));

      final applied = RequestDocMapper.canonical(target, local: full);

      expect(_body(applied)['graphqlQuery'], 'mutation { login(email: "new@b.c", password: "s3cret") { id } }');
      expect(_assertions(applied).map((a) => '${a['path']}=${a['expected']}'), [
        'data.access_token=tok-1',
        'Authorization=Bearer abc',
        '=201',
      ]);
    });

    test('a description is restored only if nothing else in it changed', () {
      final full = _request();
      final same = RequestDocMapper.canonical(SecretFields.stripDoc(full), local: full);
      expect(same.data['description'], 'Log in. Example token: $_jwt');

      final edited = SecretFields.stripDoc(_request(data: {'description': 'Log in, new text. Example token: $_jwt'}));
      expect(RequestDocMapper.canonical(edited, local: full).data['description'], 'Log in, new text. Example token: ');
    });

    test('a folder description gets its credential back too', () {
      final full = FolderDocMapper.canonical(SyncDoc(
        uid: 'f1',
        kind: SyncKind.folder,
        parentUid: 'c1',
        name: 'Auth',
        data: {'description': 'Token: $_jwt', 'tags': <Object?>[]},
      ));
      final stripped = SecretFields.stripDoc(full);
      expect(stripped.data['description'], 'Token: ');
      expect(FolderDocMapper.canonical(stripped, local: full), full);
      expect(FolderDocMapper.canonical(stripped).data['description'], 'Token: ');
    });
  });
}
