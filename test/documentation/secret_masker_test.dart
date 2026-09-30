import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/documentation/domain/entities/api_docs_model.dart';
import 'package:postpilot/features/documentation/domain/services/secret_masker.dart';

void main() {
  const mask = SecretMasker.mask;

  group('isSensitiveName', () {
    test('recognises the usual credential names in any spelling', () {
      for (final name in [
        'Authorization',
        'Proxy-Authorization',
        'X-API-Key',
        'api_key',
        'apiKey',
        'API-KEY',
        'access_token',
        'refresh_token',
        'id_token',
        'client_secret',
        'password',
        'Password',
        'user_passwd',
        'X-Auth-Token',
        'Cookie',
        'Set-Cookie',
        'key',
        'auth',
        'pwd',
        'session',
        'private_key',
        'X-Signature',
        'jwt',
        'X-Auth',
        'x_auth',
        'apiKey',
        'sessionId',
        'X-Amz-Security-Token',
        'AWSAccessKeyId',
        'accessKey',
        'X-Hub-Signature-256',
      ]) {
        expect(SecretMasker.isSensitiveName(name), isTrue, reason: name);
      }
    });

    test('leaves ordinary names alone', () {
      for (final name in [
        'Accept',
        'Content-Type',
        'page',
        'author',
        'keyword',
        'monkey',
        'User-Agent',
        'X-Request-Id',
        'limit',
        'name',
        'email',
        'oauth_version',
        'OAuth',
        'bypass',
        'compass',
        'X-Forwarded-For',
        'passenger',
        '',
      ]) {
        expect(SecretMasker.isSensitiveName(name), isFalse, reason: name);
      }
    });
  });

  group('maskValue', () {
    test('masks the value of a sensitive name', () {
      expect(SecretMasker.maskValue('password', 'hunter2'), mask);
      expect(SecretMasker.maskValue('X-API-Key', 'abc'), mask);
    });

    test('keeps the auth scheme so the docs still say how to authenticate', () {
      expect(SecretMasker.maskValue('Authorization', 'Bearer abc.def'), 'Bearer $mask');
      expect(SecretMasker.maskValue('Authorization', 'bearer abc'), 'bearer $mask');
      expect(SecretMasker.maskValue('Authorization', 'Basic dXNlcjpwdw=='), 'Basic $mask');
    });

    test('leaves a value that is only variable references', () {
      for (final value in ['{{token}}', 'Bearer {{token}}', '{{a}}{{b}}', '  {{token}}  ', 'Basic {{basic}}']) {
        expect(SecretMasker.maskValue('Authorization', value), value, reason: value);
      }
    });

    test('masks a value that mixes text into a variable', () {
      expect(SecretMasker.maskValue('token', 'prefix-{{token}}'), mask);
      expect(SecretMasker.maskValue('Authorization', 'Bearer {{token}}extra'), 'Bearer $mask');
    });

    test('does not touch other names or empty values', () {
      expect(SecretMasker.maskValue('Accept', 'application/json'), 'application/json');
      expect(SecretMasker.maskValue('password', ''), '');
    });
  });

  group('maskUrl', () {
    test('a url without a query is unchanged', () {
      expect(SecretMasker.maskUrl('https://api.example.com/users/1'), 'https://api.example.com/users/1');
      expect(SecretMasker.maskUrl('{{baseUrl}}/users'), '{{baseUrl}}/users');
      expect(SecretMasker.maskUrl(''), '');
    });

    test('masks only the sensitive parameters', () {
      expect(SecretMasker.maskUrl('https://x/a?page=2&api_key=abc&token=t&sort=asc'),
          'https://x/a?page=2&api_key=$mask&token=$mask&sort=asc');
    });

    test('keeps the fragment and recognises encoded names', () {
      expect(SecretMasker.maskUrl('https://x/a?access%5Ftoken=abc#top'), 'https://x/a?access%5Ftoken=$mask#top');
    });

    test('leaves variables, flags and empty values', () {
      expect(SecretMasker.maskUrl('/a?api_key={{key}}&token=&flag&password'), '/a?api_key={{key}}&token=&flag&password');
    });

    test('masks the password of user:password@host', () {
      expect(SecretMasker.maskUrl('https://ann:hunter2@host/x'), 'https://ann:$mask@host/x');
      expect(SecretMasker.maskUrl('https://ann:{{pw}}@host/x'), 'https://ann:{{pw}}@host/x');
    });

    test('does not mistake a port or a user name for a password', () {
      expect(SecretMasker.maskUrl('https://host:8080/x'), 'https://host:8080/x');
      expect(SecretMasker.maskUrl('https://ann@host/x'), 'https://ann@host/x');
      expect(SecretMasker.maskUrl('https://host/x@y:z'), 'https://host/x@y:z');
    });
  });

  group('maskJson', () {
    test('masks string values under sensitive keys, at any depth', () {
      expect(
        SecretMasker.maskJson('{"user":"ann","password":"hunter2","deep":{"client_secret": "s3","list":[{"token":"t"}]}}'),
        '{"user":"ann","password":"$mask","deep":{"client_secret": "$mask","list":[{"token":"$mask"}]}}',
      );
    });

    test('handles escaped quotes inside a value', () {
      expect(SecretMasker.maskJson(r'{"password": "a\"b\\", "x": "y"}'), '{"password": "$mask", "x": "y"}');
    });

    test('leaves variables, non-string values, empty strings and ordinary keys', () {
      const text = '{"password": "{{pw}}", "token": 123, "secret": null, "api_key": "", "name": "Ann"}';
      expect(SecretMasker.maskJson(text), text);
    });

    test('text that is not JSON passes through', () {
      expect(SecretMasker.maskJson('plain text password: abc'), 'plain text password: abc');
      expect(SecretMasker.maskJson(''), '');
    });

    test('a huge body is handled in linear time', () {
      final body = '{"a": "${'x' * 2000000}", "password": "p"}';
      final watch = Stopwatch()..start();
      expect(SecretMasker.maskJson(body), endsWith('"password": "$mask"}'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('redact', () {
    test('masks every part of the model and keeps its shape', () {
      const model = ApiDocsModel(
        name: 'Api',
        variables: [ApiDocsField('token', 'abc'), ApiDocsField('baseUrl', 'https://x')],
        folders: [
          ApiDocsFolder(
            name: 'F',
            folders: [
              ApiDocsFolder(name: 'G', requests: [
                ApiDocsRequest(name: 'Deep', method: 'GET', url: '/d?key=abc', headers: [ApiDocsField('Cookie', 'sid=1')]),
              ]),
            ],
          ),
        ],
        requests: [
          ApiDocsRequest(
            name: 'R',
            method: 'POST',
            url: '/r',
            body: ApiDocsBody(
              typeLabel: 'JSON',
              language: 'json',
              text: '{"password":"p"}',
              variablesText: '{"secret":"s"}',
              fields: [ApiDocsField('pwd', 'p')],
            ),
            examples: [ApiDocsExample(name: 'OK', statusCode: 200, body: '{"token":"t"}')],
          ),
        ],
      );

      final safe = SecretMasker.redact(model);

      expect(safe.variables.map((v) => v.value), [mask, 'https://x']);
      final deep = safe.folders.single.folders.single.requests.single;
      expect(deep.url, '/d?key=$mask');
      expect(deep.headers.single.value, mask);
      final request = safe.requests.single;
      expect(request.body!.text, '{"password":"$mask"}');
      expect(request.body!.variablesText, '{"secret":"$mask"}');
      expect(request.body!.fields.single.value, mask);
      expect(request.examples.single.body, '{"token":"$mask"}');
      expect(request.body!.typeLabel, 'JSON');
      expect(safe.name, 'Api');
    });
  });
}
