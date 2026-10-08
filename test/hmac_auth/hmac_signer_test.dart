// HmacSigner against vectors computed outside the app (Python hmac/hashlib), and the GitHub test vector from
// the GitHub webhook documentation. Every expected value below is pasted as a literal with its inputs.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/request_builder/domain/services/hmac_signer.dart';

final _hook = Uri.parse('https://api.example.com/hooks/in?x=1');

HmacSignature _sign(HmacSigner signer, String body, {String method = 'POST', Uri? uri, String timestamp = ''}) =>
    signer.sign(method: method, uri: uri ?? _hook, body: utf8.encode(body), timestamp: timestamp);

void main() {
  group('the documented schemes', () {
    test('GitHub: the official test vector', () {
      // Secret and body from GitHub's "Validating webhook deliveries" page.
      const signer = HmacSigner(
        secret: "It's a Secret to Everybody",
        headerName: 'X-Hub-Signature-256',
        headerTemplate: 'sha256={signature}',
      );

      final signed = _sign(signer, 'Hello, World!');

      expect(signed.signature, '757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17');
      expect(signed.headers, {
        'X-Hub-Signature-256': 'sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17',
      });
      expect(signed.payloadText, 'Hello, World!');
    });

    test('Stripe: t=<timestamp>,v1=<hex of "<timestamp>.<body>">', () {
      // python: hmac.new(b'whsec_test_secret', b'1700000000.{"id":"evt_1","object":"event"}', sha256).hexdigest()
      const signer = HmacSigner(
        secret: 'whsec_test_secret',
        payloadTemplate: '{timestamp}.{body}',
        headerName: 'Stripe-Signature',
        headerTemplate: 't={timestamp},v1={signature}',
      );

      final signed = _sign(signer, '{"id":"evt_1","object":"event"}', timestamp: '1700000000');

      expect(signed.payloadText, '1700000000.{"id":"evt_1","object":"event"}');
      expect(signed.headers, {
        'Stripe-Signature': 't=1700000000,v1=0c8670ed117751cc551a20e35839447075c42800ea3cf3e8a2fbda99cd1e6edd',
      });
    });

    test('Shopify: the base64 of the HMAC of the body', () {
      // python: base64.b64encode(hmac.new(b'hush', b'{"id":820982911946154508,"email":"jon@doe.ca"}', sha256).digest())
      const signer = HmacSigner(
        secret: 'hush',
        encoding: HmacEncoding.base64,
        headerName: 'X-Shopify-Hmac-Sha256',
      );

      final signed = _sign(signer, '{"id":820982911946154508,"email":"jon@doe.ca"}');

      expect(signed.headers, {'X-Shopify-Hmac-Sha256': 'fp5HwmAHEVGQQwJU1KRpk57Ts2YHF6/TLOCczCtB5bs='});
    });

    test('Slack: v0=<hex of "v0:<timestamp>:<body>"> and the timestamp in a header of its own', () {
      // python: hmac.new(b'8f742231b10e8888abcd99yyyzzz85a5',
      //   b'v0:1700000000:token=xyzz0WbapA4vBCDEFasx0q6G&team_id=T1DC2JH3J&text=hi', sha256).hexdigest()
      const signer = HmacSigner(
        secret: '8f742231b10e8888abcd99yyyzzz85a5',
        payloadTemplate: 'v0:{timestamp}:{body}',
        headerName: 'X-Slack-Signature',
        headerTemplate: 'v0={signature}',
        timestampHeader: 'X-Slack-Request-Timestamp',
      );

      final signed = _sign(signer, 'token=xyzz0WbapA4vBCDEFasx0q6G&team_id=T1DC2JH3J&text=hi', timestamp: '1700000000');

      expect(signed.headers, {
        'X-Slack-Signature': 'v0=2379e35d81ed593325bd53a9ec25ef5ce1b13c0cc399a5dab2d5e341537d0e43',
        'X-Slack-Request-Timestamp': '1700000000',
      });
    });
  });

  group('algorithms and encodings', () {
    // Key 'k', body 'abc', each computed with Python hmac/hashlib.
    const expected = {
      (HmacAlgorithm.sha1, HmacEncoding.hex): 'f9bef091fe00d9f5128593836dba99e193f08174',
      (HmacAlgorithm.sha256, HmacEncoding.base64): 'NC5RnOCtbAOja5jus/HRMNtIE7nfTRFg7aSI1xLceO4=',
      (HmacAlgorithm.sha512, HmacEncoding.hex):
          'bb9ec7701f7de8a362d775b9bfcb61a474bf8bf69d5dbee0689a4b284bc59a54ffd1cfdc05151759afd97ffd1a255b3849ce775ea4be799a65e6a19ac97e2ade',
      (HmacAlgorithm.sha512, HmacEncoding.base64):
          'u57HcB996KNi13W5v8thpHS/i/adXb7gaJpLKEvFmlT/0c/cBRUXWa/Zf/0aJVs4Sc53XqS+eZpl5qGayX4q3g==',
    };

    for (final entry in expected.entries) {
      test('${entry.key.$1.label} as ${entry.key.$2.label}', () {
        final signer = HmacSigner(secret: 'k', algorithm: entry.key.$1, encoding: entry.key.$2);

        expect(_sign(signer, 'abc').signature, entry.value);
      });
    }
  });

  group('the payload', () {
    test('no body signs the empty string', () {
      // python: hmac.new(b's3cret', b'', sha256).hexdigest()
      final signed = _sign(const HmacSigner(secret: 's3cret'), '');

      expect(signed.signature, '91dfac70c5348b04e1babb8b421ac92cec08b565b49ca16130dccb72503647b7');
      expect(signed.payload, isEmpty);
    });

    test('{method} is upper case and {path} is the path as sent', () {
      // python: hmac.new(b'k', b'POST\n/hooks/in\n{"a":1}', sha256).hexdigest()
      const signer = HmacSigner(secret: 'k', payloadTemplate: '{method}\n{path}\n{body}');

      final signed = _sign(signer, '{"a":1}', method: 'post');

      expect(signed.payloadText, 'POST\n/hooks/in\n{"a":1}');
      expect(signed.signature, '543de9013da2dc732220d86557fbb2573ba7fd69aca94fd5809bbb1f078746e9');
    });

    test('{query} and {url}', () {
      // python: hmac.new(b'k', b'POST /hooks/in?x=1 https://api.example.com/hooks/in?x=1 :1700000000', sha256).hexdigest()
      const signer = HmacSigner(secret: 'k', payloadTemplate: '{method} {path}?{query} {url} :{timestamp}');

      final signed = _sign(signer, '', timestamp: '1700000000');

      expect(signed.signature, 'a19a6e7391f83d6746e86d3f24b96bc3186ce8b5ed2c5fbe6eea7ce8fdc8d91b');
    });

    test('a URL with no path has the path /', () {
      // python: hmac.new(b'k', b'/||https://api.example.com', sha256).hexdigest()
      const signer = HmacSigner(secret: 'k', payloadTemplate: '{path}|{query}|{url}');

      final signed = _sign(signer, '', uri: Uri.parse('https://api.example.com'));

      expect(signed.signature, 'c7a77c8c68c4e0baf9df61dd5546de7aee08d61c5e9d4452b7d131de0d84ba1c');
    });

    test('a body that is not text is signed byte for byte', () {
      // python: hmac.new(b'k', bytes([0xff, 0x00, 0x80]), sha256).hexdigest()
      final signed = const HmacSigner(secret: 'k').sign(
        method: 'PUT',
        uri: _hook,
        body: const [0xff, 0x00, 0x80],
        timestamp: '',
      );

      expect(signed.signature, '548097e5163ebadee41e2220e9e66fa1cb35f6948f2a755d11541a8cb8d598c2');
      expect(signed.payload, [0xff, 0x00, 0x80]);
    });

    test('non-ASCII text is signed as UTF-8', () {
      // python: hmac.new(b'k', '{"name":"Zoë 🚀"}'.encode(), sha256).hexdigest()
      final signed = _sign(const HmacSigner(secret: 'k'), '{"name":"Zoë 🚀"}');

      expect(signed.signature, '5cc8e4580e7b33bf321988281c3f871f5b4eab22ac1e9b4d2fb8315f803aacdd');
    });

    test('a body that holds a placeholder is signed as it is, never expanded', () {
      // python: hmac.new(b'k', b'{"t":"{timestamp}"}', sha256).hexdigest()
      final signed = _sign(const HmacSigner(secret: 'k'), '{"t":"{timestamp}"}', timestamp: '1700000000');

      expect(signed.signature, '6d9398247f8c9e7dd4fef13c12b38684275fc79c3d5b72e634fac8859a4ef569');
    });

    test('text that is no placeholder stays, and {body} may be used twice', () {
      // python: hmac.new(b'k', b'x{foo}ab-ab', sha256).hexdigest()
      const signer = HmacSigner(secret: 'k', payloadTemplate: 'x{foo}{body}-{body}');

      final signed = _sign(signer, 'ab');

      expect(signed.payloadText, 'x{foo}ab-ab');
      expect(signed.signature, 'e6d9013963a8b933e5e65beea14cc91a1a83a98bce83b28df85d1e167fcc869a');
    });

    test('a timestamp with an empty body', () {
      // python: hmac.new(b'k', b'v1:1700000000:GET:', sha256).hexdigest()
      const signer = HmacSigner(secret: 'k', payloadTemplate: 'v1:{timestamp}:{method}:{body}');

      final signed = _sign(signer, '', method: 'GET', timestamp: '1700000000');

      expect(signed.signature, '8c3cc117b7c88b54ee7a642cde0f01488f65cfe6ca56948299acf835e474358e');
    });
  });

  group('the headers', () {
    test('a blank header template stands for the signature alone', () {
      const signer = HmacSigner(secret: 'k', algorithm: HmacAlgorithm.sha1, headerName: 'X-Sig', headerTemplate: '');

      expect(_sign(signer, 'abc').headers, {'X-Sig': 'f9bef091fe00d9f5128593836dba99e193f08174'});
    });

    test('no header name means the signature is computed but nothing is added', () {
      final signed = _sign(const HmacSigner(secret: 'k'), 'abc');

      expect(signed.headers, isEmpty);
      expect(signed.signature, hasLength(64));
    });

    test('{timestamp} in the header value is the one that was signed', () {
      const signer = HmacSigner(
        secret: 'k',
        payloadTemplate: '{timestamp}.{body}',
        headerName: 'X-Sig',
        headerTemplate: 'ts={timestamp};sig={signature};ts again={timestamp}',
      );

      final signed = _sign(signer, 'b', timestamp: '42');

      expect(signed.headers['X-Sig'], 'ts=42;sig=${signed.signature};ts again=42');
      expect(signed.payloadText, '42.b');
    });

    test('usesTimestamp says whether a send needs a timestamp', () {
      expect(const HmacSigner(secret: 'k').usesTimestamp, isFalse);
      expect(const HmacSigner(secret: 'k', payloadTemplate: '{timestamp}.{body}').usesTimestamp, isTrue);
      expect(const HmacSigner(secret: 'k', headerTemplate: 't={timestamp}').usesTimestamp, isTrue);
      expect(const HmacSigner(secret: 'k', timestampHeader: 'X-Time').usesTimestamp, isTrue);
    });

    test('unixSeconds is the whole seconds since 1970 UTC', () {
      // python: int(datetime(2023, 11, 14, 22, 13, 20, tzinfo=utc).timestamp()) == 1700000000
      expect(HmacSigner.unixSeconds(DateTime.utc(2023, 11, 14, 22, 13, 20, 999)), '1700000000');
    });
  });
}
