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

  group('maskValue by what the value is', () {
    test('a url under an ordinary name loses its password and secret parameters', () {
      expect(SecretMasker.maskValue('baseUrl', 'https://ann:hunter2@staging.example.com'), 'https://ann:$mask@staging.example.com');
      expect(SecretMasker.maskValue('dbUrl', 'postgres://u:pw@host/db'), 'postgres://u:$mask@host/db');
      expect(SecretMasker.maskValue('callback', 'https://x/cb?code=1&api_key=abc'), 'https://x/cb?code=1&api_key=$mask');
      expect(SecretMasker.maskValue('baseUrl', 'https://api.example.com/v1'), 'https://api.example.com/v1');
    });

    test('a webhook keeps its host but loses the secret path', () {
      expect(SecretMasker.maskValue('webhook', 'https://hooks.slack.com/services/T0/B0/XXXX'),
          'https://hooks.slack.com/services/$mask');
      expect(SecretMasker.maskValue('hook', 'https://discord.com/api/webhooks/123/abc_DEF'), 'https://discord.com/api/webhooks/$mask');
    });

    test('a known token shape is masked whatever the name', () {
      for (final value in [
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln',
        'sk_live_4eC39HqLyjWDarjtT1zdp7dc',
        'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
        'AKIAIOSFODNN7EXAMPLE',
        'xoxb-1234567890-abcdefghij',
      ]) {
        expect(SecretMasker.maskValue('note', value), mask, reason: value);
      }
    });

    test('ordinary values and variable references stay', () {
      expect(SecretMasker.maskValue('greeting', 'hello sk_live'), 'hello sk_live');
      expect(SecretMasker.maskValue('id', 'AKIA-not-a-key'), 'AKIA-not-a-key');
      expect(SecretMasker.maskValue('baseUrl', '{{scheme}}://{{host}}'), '{{scheme}}://{{host}}');
    });
  });

  group('maskBody', () {
    test('masks GraphQL literal arguments by their name', () {
      expect(
        SecretMasker.maskBody('mutation { login(user: "ann", password: "hunter2") { token } }'),
        'mutation { login(user: "ann", password: "$mask") { token } }',
      );
      expect(SecretMasker.maskBody("{ f(api_key: 'abc', n: 'x') }"), "{ f(api_key: '$mask', n: 'x') }");
      expect(SecretMasker.maskBody('{ login(password: \$pw, token: "{{t}}") }'), '{ login(password: \$pw, token: "{{t}}") }');
    });

    test('masks XML elements and attributes by their name', () {
      expect(
        SecretMasker.maskBody('<wsse:UsernameToken><wsse:Username>ann</wsse:Username><wsse:Password Type="x">hunter2</wsse:Password>'
            '</wsse:UsernameToken>'),
        '<wsse:UsernameToken><wsse:Username>ann</wsse:Username><wsse:Password Type="x">$mask</wsse:Password></wsse:UsernameToken>',
      );
      expect(SecretMasker.maskBody('<login user="ann" password="hunter2"/>'), '<login user="ann" password="$mask"/>');
      expect(SecretMasker.maskBody('<a><Password>{{pw}}</Password><name>Ann</name></a>'), '<a><Password>{{pw}}</Password><name>Ann</name></a>');
    });

    test('masks name=value pairs of a urlencoded body sent as raw text', () {
      expect(
        SecretMasker.maskBody('grant_type=password&client_id=web&client_secret=abc&client%5Fpassword=p'),
        'grant_type=password&client_id=web&client_secret=$mask&client%5Fpassword=$mask',
      );
      expect(SecretMasker.maskBody('API_KEY=abc\nNAME=Ann'), 'API_KEY=$mask\nNAME=Ann');
      expect(SecretMasker.maskBody('token={{t}}&x=1'), 'token={{t}}&x=1');
    });

    test('masks name: value lines of a YAML or header-style body', () {
      expect(
        SecretMasker.maskBody('user: ann\npassword: hunter2  \n  - api_key: abc\nAuthorization: Bearer xyz\nurl: https://x/y'),
        'user: ann\npassword: $mask  \n  - api_key: $mask\nAuthorization: Bearer $mask\nurl: https://x/y',
      );
    });

    test('still masks JSON and known tokens, and leaves counts and plain text alone', () {
      expect(SecretMasker.maskBody('{"password":"p","max_tokens":100,"note":"see sk_live_4eC39HqLyjWDarjtT1zdp7dc"}'),
          '{"password":"$mask","max_tokens":100,"note":"see $mask"}');
      const plain = 'Hello, this is a plain body.\nNothing secret: here.';
      expect(SecretMasker.maskBody(plain), plain);
      expect(SecretMasker.maskBody(''), '');
    });

    test('is idempotent', () {
      const body = 'password: hunter2\n<Password>p</Password>\ntoken=abc\nf(secret: "s")';
      final once = SecretMasker.maskBody(body);
      expect(SecretMasker.maskBody(once), once);
    });

    test('a huge body of any shape is handled in linear time', () {
      final watch = Stopwatch()..start();
      SecretMasker.maskBody('a' * 2000000);
      SecretMasker.maskBody('a-' * 1000000);
      SecretMasker.maskBody('k: x${' ' * 1000000}y');
      SecretMasker.maskBody('<a ${'b ' * 500000}');
      SecretMasker.maskBody('password: "${'x' * 2000000}');
      SecretMasker.maskBody('a=b&' * 250000);
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    });
  });

  group('maskMessage', () {
    test('masks urls quoted in a message, resolved or not', () {
      expect(
        SecretMasker.maskMessage('Not a valid http(s) URL: "{{baseUrl}}/u?api_key=abc&p=1" (see https://ann:pw@h/x)'),
        'Not a valid http(s) URL: "{{baseUrl}}/u?api_key=$mask&p=1" (see https://ann:$mask@h/x)',
      );
      expect(SecretMasker.maskMessage('Request timed out. Try again?'), 'Request timed out. Try again?');
      expect(SecretMasker.maskMessage(''), '');
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

    test('masks credentials in other body formats and in variables under ordinary names', () {
      const model = ApiDocsModel(
        name: 'Api',
        variables: [
          ApiDocsField('baseUrl', 'https://ann:hunter2@staging.example.com'),
          ApiDocsField('dbUrl', 'postgres://u:pw@host/db'),
          ApiDocsField('webhook', 'https://hooks.slack.com/services/T0/B0/XXXX'),
          ApiDocsField('stripe', 'sk_live_4eC39HqLyjWDarjtT1zdp7dc'),
          ApiDocsField('region', 'eu'),
        ],
        requests: [
          ApiDocsRequest(
            name: 'GraphQL',
            method: 'POST',
            url: '/graphql',
            body: ApiDocsBody(
              typeLabel: 'GraphQL',
              language: 'graphql',
              text: 'mutation { login(user: "ann", password: "hunter2") { token } }',
              variablesText: '{"pin": 4321, "password": "p2"}',
            ),
          ),
          ApiDocsRequest(
            name: 'SOAP',
            method: 'POST',
            url: '/soap',
            body: ApiDocsBody(typeLabel: 'XML', language: 'xml', text: '<wsse:Password>hunter2</wsse:Password>'),
            headers: [ApiDocsField('X-Callback', 'https://x/cb?api_key=abc')],
            examples: [ApiDocsExample(name: 'OK', statusCode: 200, body: 'access_token=abc&expires=3600')],
          ),
          ApiDocsRequest(
            name: 'Form',
            method: 'POST',
            url: '/token',
            body: ApiDocsBody(typeLabel: 'Text', text: 'grant_type=password&client_secret=abc'),
          ),
        ],
      );

      final safe = SecretMasker.redact(model);

      expect(safe.variables.map((v) => v.value), [
        'https://ann:$mask@staging.example.com',
        'postgres://u:$mask@host/db',
        'https://hooks.slack.com/services/$mask',
        mask,
        'eu',
      ]);
      expect(safe.requests[0].body!.text, 'mutation { login(user: "ann", password: "$mask") { token } }');
      expect(safe.requests[0].body!.variablesText, '{"pin": 4321, "password": "$mask"}');
      expect(safe.requests[1].body!.text, '<wsse:Password>$mask</wsse:Password>');
      expect(safe.requests[1].headers.single.value, 'https://x/cb?api_key=$mask');
      expect(safe.requests[1].examples.single.body, 'access_token=$mask&expires=3600');
      expect(safe.requests[2].body!.text, 'grant_type=password&client_secret=$mask');
    });
  });
}
