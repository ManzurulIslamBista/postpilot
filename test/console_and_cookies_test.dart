import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/utils/set_cookie.dart';
import 'package:postpilot/features/console/presentation/view_models/request_console_log.dart';

void main() {
  group('RequestConsoleLog masks what it records', () {
    late RequestConsoleLog log;
    final sentAt = DateTime(2026, 10, 6, 12);

    setUp(() => log = RequestConsoleLog());

    ApiRequestSpec spec(String url) => ApiRequestSpec(method: 'GET', url: url);

    test('a query API key never lands in the list, pending or settled', () {
      final call = log.onSend(spec('https://api.test/x?api_key=s3cret-key&page=2'), sentAt: sentAt);

      expect(log.entries.single.url, startsWith('https://api.test/x?api_key='));
      expect(log.entries.single.url, isNot(contains('s3cret-key')));
      expect(log.entries.single.url, contains('page=2'), reason: 'only the secret goes, not the rest of the URL');

      call.onResponse(
        const ApiHttpResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [1, 2], duration: Duration(milliseconds: 5)),
      );

      expect(log.entries.single.url, isNot(contains('s3cret-key')));
      expect(log.entries.single.statusCode, 200);
    });

    test('so is a password in the user info, and a token of any of the usual names', () {
      log.onSend(spec('https://ann:hunter2@api.test/x?access_token=tok-abc-123&sig=zzz999'), sentAt: sentAt);

      final url = log.entries.single.url;
      expect(url, isNot(contains('hunter2')));
      expect(url, isNot(contains('tok-abc-123')));
      expect(url, isNot(contains('zzz999')));
      expect(url, contains('ann:'), reason: 'the user name is not a secret');
    });

    test('a {{variable}} reference is not a secret and stays readable', () {
      log.onSend(spec('https://api.test/x?token={{token}}'), sentAt: sentAt);

      expect(log.entries.single.url, 'https://api.test/x?token={{token}}');
    });

    test('an error message that quotes the URL is masked as well', () {
      final call = log.onSend(spec('https://api.test/x?api_key=s3cret-key'), sentAt: sentAt);

      call.onError(Exception('Connection to https://api.test/x?api_key=s3cret-key&page=2 failed'), const Duration(milliseconds: 9));

      final entry = log.entries.single;
      expect(entry.errorMessage, isNot(contains('s3cret-key')));
      expect(entry.errorMessage, contains('page=2'));
      expect(entry.isError, isTrue);
    });
  });

  group('SetCookies', () {
    test('splits a joined header at the commas between cookies, not the ones inside an Expires date', () {
      const joined = 'a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/, b=2; Path=/x, c=3; Expires=Thu, 22-Oct-26 07:28:00 GMT';

      expect(SetCookies.split(joined), [
        'a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/',
        'b=2; Path=/x',
        'c=3; Expires=Thu, 22-Oct-26 07:28:00 GMT',
      ]);
    });

    test('one cookie, an empty value and blanks', () {
      expect(SetCookies.split('a=1; Path=/'), ['a=1; Path=/']);
      expect(SetCookies.split(''), isEmpty);
      expect(SetCookies.split('  '), isEmpty);
      expect(SetCookies.split('a=, b=2'), ['a=', 'b=2']);
    });

    test('valueOf finds a cookie by its exact name, the first when it repeats', () {
      const lines = ['sid=abc123; Path=/; HttpOnly', 'sidx=other', 'sid=second', 'token=a=b=c; Secure'];

      expect(SetCookies.valueOf(lines, 'sid'), 'abc123');
      expect(SetCookies.valueOf(lines, 'sidx'), 'other');
      expect(SetCookies.valueOf(lines, 'token'), 'a=b=c', reason: 'an = inside the value belongs to the value');
      expect(SetCookies.valueOf(lines, 'SID'), isNull, reason: 'cookie names are case-sensitive');
      expect(SetCookies.valueOf(lines, 'missing'), isNull);
      expect(SetCookies.valueOf(lines, ''), isNull);
    });

    test('valueOf trims, and skips a line that is not a name=value pair', () {
      expect(SetCookies.valueOf(const ['junk', '=novalue', ' sid = abc ; Path=/'], 'sid'), 'abc');
    });
  });
}
