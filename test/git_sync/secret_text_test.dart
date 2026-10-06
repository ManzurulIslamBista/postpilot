import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_names.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_text.dart';

/// The expectations here are written by hand from what each text contains, not produced by running
/// the code: what is blanked is exactly the credential, and every other byte stays.
void main() {
  group('SecretNames', () {
    test('a bare "key" is a credential only when its value looks generated', () {
      expect(SecretNames.isSecretBodyKey('key', 'AIzaSyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q'), isTrue);
      expect(SecretNames.isSecretBodyKey('key', 'k3j9f0s8d7f6g5h4j3k2l1z0x9c8v7'), isTrue);
      expect(SecretNames.isSecretBodyKey('key', 'color'), isFalse);
      expect(SecretNames.isSecretBodyKey('key', 'my-collection-2024'), isFalse, reason: 'a slug names a thing');
      expect(SecretNames.isSecretBodyKey('key', '550e8400-e29b-41d4-a716-446655440000'), isFalse, reason: 'a uuid is an id');
      expect(SecretNames.isSecretBodyKey('keyword', 'k3j9f0s8d7f6g5h4j3k2l1z0x9c8v7'), isFalse);
      expect(SecretNames.isSecretBodyKey('api_key', 'x'), isTrue, reason: 'a named key needs no look at the value');
    });

    test('PINs and one-time codes are credentials, counts and descriptions of them are not', () {
      for (final name in ['pin', 'otp', 'passcode', 'user_pin', 'pinCode']) {
        expect(SecretNames.looksSecretKey(name), isTrue, reason: name);
      }
      for (final name in ['pinned', 'spinner', 'password_hint', 'password_length', 'token_count', 'password_policy']) {
        expect(SecretNames.looksSecretKey(name), isFalse, reason: name);
      }
      expect(SecretNames.isNumericSecretKey('pin'), isTrue);
      expect(SecretNames.isNumericSecretKey('password'), isTrue);
      expect(SecretNames.isNumericSecretKey('otp'), isTrue);
      expect(SecretNames.isNumericSecretKey('max_tokens'), isFalse, reason: 'a count of tokens, not a token');
      expect(SecretNames.isNumericSecretKey('password_ttl'), isFalse);
      expect(SecretNames.isNumericSecretKey('pin_count'), isFalse);
    });

    test('known token shapes are found anywhere', () {
      final text = 'a ghp_abcdefghijklmnopqrstuvwxyz0123456789 b AKIAABCDEFGHIJKLMNOP c sk_live_abcdefghij1234 d';
      expect(SecretNames.knownTokens(text).map((m) => m.group(0)), [
        'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
        'AKIAABCDEFGHIJKLMNOP',
        'sk_live_abcdefghij1234',
      ]);
      expect(SecretNames.knownTokens('nothing here, just words and 12345'), isEmpty);
    });
  });

  group('SecretText.blankBody', () {
    test('blanks a bare "key" JSON pair holding a generated value, and only that', () {
      expect(
        SecretText.blankBody('{"key": "AIzaSyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q", "name": "Ada"}'),
        '{"key": "", "name": "Ada"}',
      );
      for (final data in [
        '{"key": "color"}',
        '{"key": "my-collection-2024"}',
        '{"key": "550e8400-e29b-41d4-a716-446655440000"}',
        '{"key": 7}',
      ]) {
        expect(SecretText.blankBody(data), data);
      }
    });

    test('blanks the password element of an XML or SOAP body, with prefixes and attributes', () {
      const soap =
          '<soap:Envelope><soap:Body><Login><UserName>ada</UserName>'
          '<wsse:Password Type="PasswordText">hunter2</wsse:Password><ApiKey>k-123</ApiKey>'
          '<Title>Password reset</Title><token>{{token}}</token></Login></soap:Body></soap:Envelope>';
      expect(
        SecretText.blankBody(soap),
        '<soap:Envelope><soap:Body><Login><UserName>ada</UserName>'
        '<wsse:Password Type="PasswordText"></wsse:Password><ApiKey></ApiKey>'
        '<Title>Password reset</Title><token>{{token}}</token></Login></soap:Body></soap:Envelope>',
      );
      expect(SecretText.blankBody('<Secret><![CDATA[a<b]]></Secret>'), '<Secret></Secret>');
    });

    test('blanks the literal arguments of a GraphQL query and an XML attribute', () {
      expect(
        SecretText.blankBody('mutation { login(email: "a@b.c", password: "s3cret", pin: \'1234\') { id } }'),
        'mutation { login(email: "a@b.c", password: "", pin: \'\') { id } }',
      );
      expect(SecretText.blankBody('<auth password="p4ss" user="ada"/>'), '<auth password="" user="ada"/>');
      expect(SecretText.blankBody('login(password: "{{pw}}")'), 'login(password: "{{pw}}")');
      expect(SecretText.blankBody('query(\$password: String!) { x }'), 'query(\$password: String!) { x }');
    });

    test('blanks the secret fields of an urlencoded body sent as raw text', () {
      expect(
        SecretText.blankBody('grant_type=password&client_id=abc&client_secret=xyz123&username=ada&password=hunter2'),
        'grant_type=password&client_id=abc&client_secret=&username=ada&password=',
      );
      expect(SecretText.blankBody('a=1&token=abc\nsession_id=77'), 'a=1&token=\nsession_id=');
    });

    test('blanks a number under a credential name, and leaves counts and other numbers alone', () {
      expect(
        SecretText.blankBody('{"pin": 1234, "max_tokens": 100, "count": 3, "otp": 482913, "pin_count": 3}'),
        '{"pin": "", "max_tokens": 100, "count": 3, "otp": "", "pin_count": 3}',
      );
      expect(SecretText.blankBody('{"password": 123456}'), '{"password": ""}');
    });

    test('leaves ordinary data alone', () {
      for (final data in [
        '{"title": "Password reset", "token_url": "https://x.test/token", "author": "ann", "monkey": "banana"}',
        '{"password_hint": "first pet", "password_length": "8", "token_count": "5"}',
        '<Title>Reset your password</Title><Author>ann</Author>',
        'Send the password in the body and keep the token safe.',
        'a=1&page=2&sort=asc',
        '{"password": "{{password}}"}',
        '{"name": "Ada", "note": "see https://x.test?page=2"}',
      ]) {
        expect(SecretText.blankBody(data), data, reason: data);
      }
    });

    test('is idempotent', () {
      const text = '{"password": "a", "pin": 12} <Password>b</Password> x(token: "c") q=1&secret=d';
      final once = SecretText.blankBody(text);
      expect(SecretText.blankBody(once), once);
    });

    test('with a placeholder, the credential becomes {{name}} and the text stays valid', () {
      expect(
        SecretText.blankBody('{"password": "a", "pin": 12, "n": 1}', placeholder: (name) => name),
        '{"password": "{{password}}", "pin": "{{pin}}", "n": 1}',
      );
      expect(SecretText.blankBody('<wsse:Password>b</wsse:Password>', placeholder: (name) => name), '<wsse:Password>{{Password}}</wsse:Password>');
      expect(SecretText.blankBody('x(token: "c")', placeholder: (name) => 'my token'), 'x(token: "{{my_token}}")');
    });
  });

  group('SecretText.restoreBody', () {
    const bodies = {
      'json': '{"user": "ada", "password": "hunter2", "key": "AIzaSyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q", "pin": 1234}',
      'soap': '<L><UserName>ada</UserName><wsse:Password Type="t">hunter2</wsse:Password><ApiKey>k-1</ApiKey></L>',
      'graphql': 'mutation { login(email: "a@b.c", password: "s3cret") { id } }',
      'form': 'grant_type=password&client_secret=xyz123&password=hunter2&username=ada',
    };

    for (final entry in bodies.entries) {
      test('puts every credential of the ${entry.key} body back', () {
        final blank = SecretText.blankBody(entry.value);
        expect(blank, isNot(entry.value));
        expect(SecretText.restoreBody(blank, entry.value), entry.value);
      });
    }

    test('matches by name and occurrence, and keeps what somebody else changed', () {
      const local = '{"password": "one", "other": "x", "password2": "z"}';
      expect(SecretText.restoreBody('{"password": "", "other": "changed", "password2": ""}', local),
          '{"password": "one", "other": "changed", "password2": "z"}');

      const twice = 'a=1&token=first&b=2&token=second';
      expect(SecretText.restoreBody('a=1&token=&b=2&token=', twice), twice);
      expect(SecretText.restoreBody('b=2&token=&token=', twice), 'b=2&token=first&token=second');
    });

    test('never overwrites a value somebody has set, and ignores a name the local text lacks', () {
      expect(SecretText.restoreBody('{"password": "shared"}', '{"password": "mine"}'), '{"password": "shared"}');
      expect(SecretText.restoreBody('{"password": ""}', '{"other": "x"}'), '{"password": ""}');
      expect(SecretText.restoreBody('', '{"password": "x"}'), '');
    });

    test('a bare key is restored only from a value that looks generated', () {
      expect(SecretText.restoreBody('{"key": ""}', '{"key": "color"}'), '{"key": ""}');
      expect(SecretText.restoreBody('{"key": ""}', '{"key": "k3j9f0s8d7f6g5h4j3k2l1z0x9c8v7"}'),
          '{"key": "k3j9f0s8d7f6g5h4j3k2l1z0x9c8v7"}');
    });

    test('the JSON-only names of before still work', () {
      expect(SecretText.blankJson('{"password": "a"}'), '{"password": ""}');
      expect(SecretText.restoreJson('{"password": ""}', '{"password": "a"}'), '{"password": "a"}');
    });
  });

  group('SecretText.blankNote', () {
    test('removes unmistakable credentials from prose', () {
      expect(
        SecretText.blankNote('Use Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n in the header'),
        'Use Bearer  in the header',
      );
      expect(
        SecretText.blankNote('curl -H "Authorization: Bearer abc123def456ghi789jkl012mno345" https://x.test'),
        'curl -H "Authorization: Bearer " https://x.test',
      );
      expect(SecretText.blankNote('token ghp_abcdefghijklmnopqrstuvwxyz0123456789 expires'), 'token  expires');
      expect(SecretText.blankNote('db at https://app:Zx81kq0pL3vN7mB2cR9t@db.test/x'), 'db at https://app:@db.test/x');
      expect(SecretText.blankNote('call /v1/items?api_key=k3j9f0s8d7f6g5h4j3k2l1z0x9c8v7&page=2'), 'call /v1/items?api_key=&page=2');
    });

    test('leaves prose, placeholders and documentation examples alone', () {
      for (final note in [
        'The token expires after 1 hour. Send the password as password=YOUR_PASSWORD.',
        'Authorization: Bearer {{token}}',
        'Send a Bearer token in the header; Basic authentication is not supported.',
        'GET /v1/items?api_key=YOUR_API_KEY',
        'https://user:password@host.test/path',
        'Token: valid for one hour',
        '',
      ]) {
        expect(SecretText.blankNote(note), note, reason: note);
      }
    });

    test('is put back only when nothing else in the note changed', () {
      const local = 'Use ghp_abcdefghijklmnopqrstuvwxyz0123456789 here';
      final blank = SecretText.blankNote(local);
      expect(blank, 'Use  here');
      expect(SecretText.restoreNote(blank, local), local);
      expect(SecretText.restoreNote('Use  there', local), 'Use  there');
    });
  });
}
