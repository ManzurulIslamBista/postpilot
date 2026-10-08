// What RequestSpecBuilder puts on a request with HMAC auth: the signature of the exact bytes that go on the wire.
// The expected signatures are literals computed with Python hmac/hashlib from the inputs written next to them; the
// secret is `hunter2` unless a test says otherwise.
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/hmac_snippet_note.dart';
import 'package:postpilot/features/request_builder/domain/services/hmac_presets.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';

/// 2023-11-14T22:13:20Z, which is 1700000000 seconds since 1970 (python: datetime(...).timestamp()).
final _clock = DateTime.utc(2023, 11, 14, 22, 13, 20);

const _github = RequestAuth(type: AuthType.hmac, hmacSecret: 'hunter2');

RequestAuth _preset(HmacPreset preset, {String secret = 'hunter2'}) =>
    HmacPresets.apply(RequestAuth(type: AuthType.hmac, hmacSecret: secret), preset);

ApiRequestEntity _request({
  HttpMethod method = HttpMethod.post,
  String url = 'https://api.example.com/hooks/in',
  RequestBody body = const RequestBody(type: BodyType.raw, rawText: '{"a":1}'),
  RequestAuth auth = _github,
  List<KeyValueItem> headers = const [],
}) => ApiRequestEntity(
  id: 1,
  collectionId: 1,
  folderId: null,
  name: 'hook',
  method: method,
  url: url,
  headers: headers,
  queryParams: const [],
  body: body,
  auth: auth,
);

ResolvedRequestSpec _build(
  ApiRequestEntity request, {
  Map<String, String> variables = const {},
  RequestAuth? inheritedAuth,
  RequestSpecBuilder builder = const RequestSpecBuilder(),
}) => builder.build(request, VariableResolver(variables), inheritedAuth: inheritedAuth);

RequestSpecBuilder _builderAt(DateTime now, {void Function()? onRead}) => RequestSpecBuilder(
  now: () {
    onRead?.call();
    return now;
  },
);

void main() {
  group('the signature is the one of the exact bytes that are sent', () {
    test('a JSON body: the GitHub header', () {
      // python: hmac.new(b'hunter2', b'{"a":1}', sha256).hexdigest()
      final spec = _build(_request());

      expect(utf8.decode(spec.bodyBytes!), '{"a":1}');
      expect(
        spec.headers['X-Hub-Signature-256'],
        'sha256=6e73a1a57a6e6edb9dff174d2a53bc61a27cfc639a2964743ed35fd59c8bc82d',
      );
    });

    test('agrees with an HMAC computed over spec.bodyBytes by the crypto package', () {
      final spec = _build(_request(body: const RequestBody(type: BodyType.raw, rawText: 'line 1\r\nZoë 🚀 {{x}}')));

      final expected = Hmac(sha256, utf8.encode('hunter2')).convert(spec.bodyBytes!).toString();

      expect(spec.headers['X-Hub-Signature-256'], 'sha256=$expected');
    });

    test('{{variables}} in the body are resolved first, and the secret is a variable too', () {
      // python: hmac.new(b'sec-from-var', b'{"user":"ann"}', sha256).hexdigest()
      final spec = _build(
        _request(
          body: const RequestBody(type: BodyType.raw, rawText: '{"user":"{{who}}"}'),
          auth: const RequestAuth(type: AuthType.hmac, hmacSecret: '{{whsec}}'),
        ),
        variables: {'who': 'ann', 'whsec': 'sec-from-var'},
      );

      expect(utf8.decode(spec.bodyBytes!), '{"user":"ann"}');
      expect(
        spec.headers['X-Hub-Signature-256'],
        'sha256=3d2217fa40411c6d4fb67672dbafe834663bf6adc982b1dab6e71b1a91f3b856',
      );
    });

    test('{{variables}} in the templates and the header name are resolved', () {
      // python: hmac.new(b'hunter2', b'v9::{"a":1}', sha256).hexdigest()
      final spec = _build(
        _request(
          auth: const RequestAuth(
            type: AuthType.hmac,
            hmacSecret: 'hunter2',
            hmacPayloadTemplate: '{{prefix}}:{body}',
            hmacHeaderName: 'X-{{brand}}-Sig',
            hmacHeaderTemplate: '{{scheme}}={signature}',
          ),
        ),
        variables: {'prefix': 'v9:', 'brand': 'Acme', 'scheme': 'hmac'},
      );

      expect(spec.headers['X-Acme-Sig'], 'hmac=d6582eb6c72e41e6495c20a11a21af33269ec549576317152da736e7bc0d098e');
    });

    test('no body signs the empty string', () {
      // python: hmac.new(b's3cret', b'', sha256).hexdigest()
      final spec = _build(
        _request(
          method: HttpMethod.get,
          body: RequestBody.empty,
          auth: const RequestAuth(type: AuthType.hmac, hmacSecret: 's3cret'),
        ),
      );

      expect(spec.bodyBytes, isNull);
      expect(
        spec.headers['X-Hub-Signature-256'],
        'sha256=91dfac70c5348b04e1babb8b421ac92cec08b565b49ca16130dccb72503647b7',
      );
    });

    test('an urlencoded body is signed as it is serialised', () {
      // python: hmac.new(b'hunter2', b'a=1&b=x+y', sha256).hexdigest()
      final spec = _build(
        _request(
          body: RequestBody(
            type: BodyType.urlEncoded,
            urlEncodedFields: [KeyValueItem(key: 'a', value: '1'), KeyValueItem(key: 'b', value: 'x y')],
          ),
        ),
      );

      expect(utf8.decode(spec.bodyBytes!), 'a=1&b=x+y');
      expect(
        spec.headers['X-Hub-Signature-256'],
        'sha256=befdd1b006a518a4128c8d30a6beafda550294eedf8262d3f998c08e1c007601',
      );
    });

    test('a GraphQL body is signed as the JSON that is sent', () {
      // python: hmac.new(b'hunter2', b'{"query":"{ ping }","variables":{"a":1}}', sha256).hexdigest()
      final spec = _build(
        _request(
          body: const RequestBody(type: BodyType.graphql, graphqlQuery: '{ ping }', graphqlVariables: '{"a": 1}'),
        ),
      );

      expect(utf8.decode(spec.bodyBytes!), '{"query":"{ ping }","variables":{"a":1}}');
      expect(
        spec.headers['X-Hub-Signature-256'],
        'sha256=ca660bc2ed0a96c7b68d588fef6c7c8ce29d76e3ce4132046afd2924219bedb5',
      );
    });

    test('a form-data body without a file is signed with the boundary it is sent with', () {
      // python: hmac.new(b'hunter2', b'--B\r\nContent-Disposition: form-data; name="a"\r\n\r\n1\r\n--B--\r\n', sha256)
      final spec = _build(
        _request(body: RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'a', value: '1')])),
        builder: RequestSpecBuilder(boundary: () => 'B'),
      );

      expect(utf8.decode(spec.bodyBytes!), '--B\r\nContent-Disposition: form-data; name="a"\r\n\r\n1\r\n--B--\r\n');
      expect(
        spec.headers['X-Hub-Signature-256'],
        'sha256=bd0143381b6f49762ca63503aea0c92e3d57bd6d7e5f9828248f53c0e93fa3be',
      );
    });

    test('a body that sends a file cannot be signed, and says so instead of signing something else', () {
      final formWithFile = _request(
        body: RequestBody(
          type: BodyType.formData,
          formFields: [KeyValueItem(key: 'f', value: 'C:/files/a.bin', kind: FormFieldKind.file)],
        ),
      );
      final binary = _request(
        body: const RequestBody(type: BodyType.binary).withBinaryFile(
          KeyValueItem(key: '', value: 'C:/files/a.bin', kind: FormFieldKind.file),
        ),
      );

      for (final request in [formWithFile, binary]) {
        expect(
          () => _build(request),
          throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('cannot sign a body that sends a file'))),
        );
      }
    });

    test('the same file body is fine with another auth type', () {
      final spec = _build(
        _request(
          body: const RequestBody(type: BodyType.binary).withBinaryFile(
            KeyValueItem(key: '', value: 'C:/files/a.bin', kind: FormFieldKind.file),
          ),
          auth: const RequestAuth(type: AuthType.bearer, bearerToken: 't'),
        ),
      );

      expect(spec.upload, isNotNull);
    });
  });

  group('the timestamp', () {
    test('Stripe: the current time, once, in the payload and the header', () {
      // python: hmac.new(b'hunter2', b'1700000000.{"a":1}', sha256).hexdigest()
      var reads = 0;
      final spec = _build(_request(auth: _preset(HmacPreset.stripe)), builder: _builderAt(_clock, onRead: () => reads++));

      expect(
        spec.headers['Stripe-Signature'],
        't=1700000000,v1=56b25cbf563812b38800e5f4dd1febfde087d36841155e70b3aa285517e1570a',
      );
      expect(reads, 1, reason: 'the clock is read once per build');
    });

    test('Slack: the signature and the timestamp header carry the same, fixed, timestamp', () {
      // python: hmac.new(b'hunter2', b'v0:1531420618:{"a":1}', sha256).hexdigest()
      var reads = 0;
      final auth = _preset(HmacPreset.slack).copyWith(
        hmacTimestampSource: HmacTimestampSource.fixed,
        hmacTimestampValue: ' 1531420618 ',
      );

      final spec = _build(_request(auth: auth), builder: _builderAt(_clock, onRead: () => reads++));

      expect(spec.headers['X-Slack-Request-Timestamp'], '1531420618');
      expect(
        spec.headers['X-Slack-Signature'],
        'v0=baaf478490886569ea1f503e8a8c3bd4d09ab08fd51532ca987ba126e9d37b89',
      );
      expect(reads, 0, reason: 'a fixed timestamp does not look at the clock');
    });

    test('Slack with the clock: the timestamp header is the clock, in whole seconds', () {
      final spec = _build(_request(auth: _preset(HmacPreset.slack)), builder: _builderAt(_clock.add(const Duration(milliseconds: 999))));

      expect(spec.headers['X-Slack-Request-Timestamp'], '1700000000');
    });

    test('two sends a second apart are signed differently, one at the same instant identically', () {
      final auth = _preset(HmacPreset.stripe);

      final first = _build(_request(auth: auth), builder: _builderAt(_clock));
      final again = _build(_request(auth: auth), builder: _builderAt(_clock));
      final later = _build(_request(auth: auth), builder: _builderAt(_clock.add(const Duration(seconds: 1))));

      expect(again.headers['Stripe-Signature'], first.headers['Stripe-Signature']);
      expect(later.headers['Stripe-Signature'], isNot(first.headers['Stripe-Signature']));
      expect(later.headers['Stripe-Signature'], startsWith('t=1700000001,v1='));
    });

    test('a fixed timestamp may be a variable', () {
      final auth = _preset(HmacPreset.stripe).copyWith(
        hmacTimestampSource: HmacTimestampSource.fixed,
        hmacTimestampValue: '{{ts}}',
      );

      final spec = _build(_request(auth: auth), variables: {'ts': '1700000000'});

      expect(
        spec.headers['Stripe-Signature'],
        't=1700000000,v1=56b25cbf563812b38800e5f4dd1febfde087d36841155e70b3aa285517e1570a',
      );
    });

    test('a fixed timestamp that is empty is an error when the scheme needs a timestamp, and not when it does not', () {
      final stripe = _preset(HmacPreset.stripe).copyWith(hmacTimestampSource: HmacTimestampSource.fixed);
      final github = _github.copyWith(hmacTimestampSource: HmacTimestampSource.fixed);

      expect(
        () => _build(_request(auth: stripe)),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('fixed timestamp is empty'))),
      );
      expect(_build(_request(auth: github)).headers, contains('X-Hub-Signature-256'));
    });

    test('a scheme without a timestamp never reads the clock', () {
      var reads = 0;

      _build(_request(), builder: _builderAt(_clock, onRead: () => reads++));

      expect(reads, 0);
    });
  });

  group('headers', () {
    test('Shopify: base64 in its own header', () {
      // python: base64(hmac.new(b'hunter2', b'{"a":1}', sha256).digest())
      final spec = _build(_request(auth: _preset(HmacPreset.shopify)));

      expect(spec.headers['X-Shopify-Hmac-Sha256'], 'bnOhpXpubtud/xdNKlO8YaJ8/GOaKWR0PtNf1ZyLyC0=');
    });

    test('the request\'s own rows stay, and a row of the signature header is replaced whatever its letter case', () {
      final spec = _build(
        _request(headers: [KeyValueItem(key: 'x-hub-signature-256', value: 'stale'), KeyValueItem(key: 'X-Own', value: '1')]),
      );

      expect(spec.headers.keys.where((k) => k.toLowerCase() == 'x-hub-signature-256'), ['X-Hub-Signature-256']);
      expect(spec.headers['X-Hub-Signature-256'], startsWith('sha256=6e73a1a5'));
      expect(spec.headers['X-Own'], '1');
      expect(spec.headers['Content-Type'], 'application/json');
    });

    test('no header name: nothing is added', () {
      final spec = _build(_request(auth: _github.copyWith(hmacHeaderName: '')));

      expect(spec.headers.keys, ['Content-Type']);
    });
  });

  group('inheritance', () {
    test('a request that inherits is signed with the HMAC auth of the folder or collection', () {
      final spec = _build(_request(auth: const RequestAuth()), inheritedAuth: _github);

      expect(spec.headers['X-Hub-Signature-256'], startsWith('sha256=6e73a1a5'));
    });

    test('an own auth of another type is not signed', () {
      final spec = _build(
        _request(auth: const RequestAuth(type: AuthType.none)),
        inheritedAuth: _github,
      );

      expect(spec.headers.keys, ['Content-Type']);
    });
  });

  group('undefined variables', () {
    test('are found in the secret, the templates, the header names and a fixed timestamp', () {
      const auth = RequestAuth(
        type: AuthType.hmac,
        hmacSecret: '{{secret}}',
        hmacPayloadTemplate: '{{p}}{body}',
        hmacHeaderName: '{{h}}',
        hmacHeaderTemplate: '{{t}}{signature}',
        hmacTimestampHeader: '{{th}}',
        hmacTimestampSource: HmacTimestampSource.fixed,
        hmacTimestampValue: '{{ts}}',
      );

      final missing = const RequestSpecBuilder().undefinedVariables(_request(auth: auth), VariableResolver(const {}));

      expect({for (final v in missing) v.name: v.places.single}, {
        'secret': 'the HMAC secret',
        'p': 'the HMAC signed payload',
        'h': 'the HMAC header name',
        't': 'the HMAC header value',
        'th': 'the HMAC timestamp header',
        'ts': 'the HMAC fixed timestamp',
      });
    });

    test('a defined secret is not reported, and a fixed timestamp is only looked at when it is used', () {
      const auth = RequestAuth(type: AuthType.hmac, hmacSecret: '{{secret}}', hmacTimestampValue: '{{unused}}');

      final missing = const RequestSpecBuilder().undefinedVariables(_request(auth: auth), VariableResolver({'secret': 's'}));

      expect(missing, isEmpty);
    });
  });

  group('the preview', () {
    test('is the signature build puts on the request', () {
      final request = _request(auth: _preset(HmacPreset.stripe));
      final builder = _builderAt(_clock);
      final resolver = VariableResolver(const {});

      final preview = builder.previewHmac(request, resolver);
      final spec = builder.build(request, resolver);

      expect(preview.problem, isNull);
      expect(preview.signed!.headers['Stripe-Signature'], spec.headers['Stripe-Signature']);
      expect(preview.signed!.payloadText, '1700000000.{"a":1}');
    });

    test('says why a file body has none', () {
      final request = _request(
        body: const RequestBody(type: BodyType.binary).withBinaryFile(
          KeyValueItem(key: '', value: 'C:/a.bin', kind: FormFieldKind.file),
        ),
      );

      final preview = const RequestSpecBuilder().previewHmac(request, VariableResolver(const {}));

      expect(preview.signed, isNull);
      expect(preview.problem, contains('cannot sign a body that sends a file'));
    });

    test('says why an unreadable GraphQL variables text has none, and has nothing for another auth type', () {
      final graphql = _request(body: const RequestBody(type: BodyType.graphql, graphqlQuery: '{ a }', graphqlVariables: '{'));
      final bearer = _request(auth: const RequestAuth(type: AuthType.bearer));

      expect(const RequestSpecBuilder().previewHmac(graphql, VariableResolver(const {})).problem, contains('not valid JSON'));
      final other = const RequestSpecBuilder().previewHmac(bearer, VariableResolver(const {}));
      expect(other.signed, isNull);
      expect(other.problem, isNull);
    });
  });

  group('code snippets', () {
    test('cURL carries the computed signature header', () {
      final spec = _build(_request());

      final snippet = const CurlGenerator().generate(spec);

      expect(snippet, contains("--header 'X-Hub-Signature-256: sha256=6e73a1a57a6e6edb9dff174d2a53bc61a27cfc639a2964743ed35fd59c8bc82d'"));
      expect(snippet, contains("--data-raw '{\"a\":1}'"));
    });

    test('a signature that covers the clock gets a comment, in the comment style of the language', () {
      final stripe = _preset(HmacPreset.stripe);

      expect(HmacSnippetNote.needed(stripe), isTrue);
      expect(HmacSnippetNote.append('curl x', 'curl', stripe), 'curl x\n# ${HmacSnippetNote.text}');
      expect(HmacSnippetNote.append('fetch(x);\n', 'javascript_fetch', stripe), 'fetch(x);\n// ${HmacSnippetNote.text}\n');
      expect(HmacSnippetNote.append('print(1)', 'python_requests', _preset(HmacPreset.slack)), endsWith('# ${HmacSnippetNote.text}'));
    });

    test('a signature that does not change with the time gets none', () {
      expect(HmacSnippetNote.needed(_github), isFalse);
      expect(HmacSnippetNote.needed(_preset(HmacPreset.shopify)), isFalse);
      expect(HmacSnippetNote.needed(_preset(HmacPreset.stripe).copyWith(hmacTimestampSource: HmacTimestampSource.fixed)), isFalse);
      expect(HmacSnippetNote.needed(const RequestAuth(type: AuthType.bearer)), isFalse);
      expect(HmacSnippetNote.append('curl x', 'curl', _github), 'curl x');
    });
  });
}
