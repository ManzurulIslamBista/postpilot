// The causes of a 401 or 403 that are not about the credential: Odoo's access rights, a firewall in front of the API, an IP allow-list,
// a CSRF token, a method the URL does not allow, a rate limit, a signature or a clock, and a credential lost in a redirect.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_doctor_input.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_finding.dart';
import 'package:postpilot/features/auth_doctor/domain/services/auth_doctor.dart';
import 'auth_doctor_fixtures.dart';

const _odooAccessError =
    '{"name":"odoo.exceptions.AccessError","message":"You are not allowed to access \'Contact\' (res.partner) records.\\n\\n'
    'This operation is allowed for the following groups:\\n\\t- Contact Creation\\n\\nContact your administrator to request access if necessary.",'
    '"arguments":["x"],"context":{},"debug":"Traceback (most recent call last):\\n  File \\"/odoo/odoo/http.py\\", line 1, in dispatch\\nodoo.exceptions.AccessError: x"}';

void main() {
  group('Odoo', () {
    test('an AccessError is read by the Odoo error parser: the model, the groups that may, and the live lookup that exists', () {
      final findings = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, body: _odooAccessError));

      final odoo = byId(findings, 'forbidden.odoo');
      expect(odoo.confidence, FindingConfidence.certain);
      expect(odoo.title, 'Odoo: Access denied');
      expect(odoo.explanation, contains('Contact (res.partner)'));
      expect(odoo.fix, contains('Contact Creation'));
      expect(odoo.fix, contains('Look it up on the server'));
      expect(odoo.evidence.first, 'Odoo exception: odoo.exceptions.AccessError');
      expect(findings.first.id, 'forbidden.odoo');
    });

    test('an invalid API key of the JSON-2 API, with the way to make a new one', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        body: '{"name":"werkzeug.exceptions.Unauthorized","message":"Invalid apikey","arguments":[],"debug":""}',
      ));

      final odoo = byId(findings, 'forbidden.odoo');
      expect(odoo.title, 'Odoo: Invalid API key');
      expect(odoo.fix, contains('New API Key'));
    });

    test('plain text from an older controller is read too', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        body: "You are not allowed to access 'Sales Order' (sale.order) records.",
      ));

      final odoo = byId(findings, 'forbidden.odoo');
      expect(odoo.explanation, contains('Sales Order (sale.order)'));
    });

    test('a JSON 403 that is not Odoo is not called Odoo', () {
      final findings = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, body: '{"message":"Forbidden"}'));

      expect(ids(findings), isNot(contains('forbidden.odoo')));
    });
  });

  group('a firewall or CDN answered, not the API', () {
    test('Cloudflare: its server header and an HTML block page', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        responseHeaders: const {'Server': 'cloudflare', 'CF-RAY': '8a1b2c3d4e5f6a7b-AMS', 'Content-Type': 'text/html; charset=UTF-8'},
        body: '<!DOCTYPE html><html><head><title>Attention Required! | Cloudflare</title></head><body><h1>Sorry, you have been blocked</h1></body></html>',
      ));

      final waf = byId(findings, 'forbidden.waf');
      expect(waf.confidence, FindingConfidence.likely);
      expect(waf.title, 'Cloudflare blocked the request');
      expect(waf.evidence, containsAll(['server: cloudflare', 'cf-ray: 8a1b2c3d4e5f6a7b-AMS']));
      expect(waf.explanation, contains('the token was never looked at'));
    });

    test('Cloudflare in front of an API that answers in JSON is the API\'s own answer', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        responseHeaders: const {'Server': 'cloudflare', 'Content-Type': 'application/json'},
        body: '{"error":"forbidden"}',
      ));

      expect(ids(findings), isNot(contains('forbidden.waf')));
    });

    test('Akamai: the reference number is read out of the entity-encoded page', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        responseHeaders: const {'Server': 'AkamaiGHost', 'Content-Type': 'text/html'},
        body: '<HTML><HEAD><TITLE>Access Denied</TITLE></HEAD><BODY><H1>Access Denied</H1>You don\'t have permission to access this server.<P>'
            'Reference&#32;&#35;18&#46;7e3d2f17&#46;1696000000&#46;1a2b3c4d</BODY></HTML>',
      ));

      final waf = byId(findings, 'forbidden.waf');
      expect(waf.title, 'Akamai blocked the request');
      expect(waf.evidence, contains('Reference #18.7e3d2f17.1696000000.1a2b3c4d'));
    });

    test('AWS CloudFront and WAF', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        responseHeaders: const {'Server': 'CloudFront', 'Content-Type': 'text/html'},
        body: '<html><body><h1>ERROR: The request could not be satisfied</h1>Request blocked. We can\'t connect to the server for this app or website.</body></html>',
      ));

      expect(byId(findings, 'forbidden.waf').title, 'AWS WAF or CloudFront blocked the request');
    });

    test('a bare nginx 403 page is only a possibility, and says a web server refused the path', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        responseHeaders: const {'Server': 'nginx/1.24.0', 'Content-Type': 'text/html'},
        body: '<html><head><title>403 Forbidden</title></head><body><center><h1>403 Forbidden</h1></center><hr><center>nginx/1.24.0</center></body></html>',
      ));

      final server = byId(findings, 'forbidden.web-server');
      expect(server.confidence, FindingConfidence.possible);
      expect(ids(findings), isNot(contains('forbidden.waf')));
    });
  });

  group('IP allow-list wording', () {
    test('the server\'s own message is quoted', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        body: '{"message":"Your IP address 203.0.113.9 is not allowed to access this resource."}',
      ));

      final ip = byId(findings, 'forbidden.ip-allowlist');
      expect(ip.confidence, FindingConfidence.likely);
      expect(ip.evidence, ['The server said: "Your IP address 203.0.113.9 is not allowed to access this resource."']);
      expect(ip.fix, contains('PostPilot never looks that address up'));
    });

    test('allow-list and whitelist wording is found, an unrelated 403 is not', () {
      for (final body in ['Request from a non-whitelisted network', 'This endpoint has an IP restriction.', 'You are not in the allow-list']) {
        expect(ids(AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, body: body))), contains('forbidden.ip-allowlist'), reason: body);
      }
      expect(ids(AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, body: '{"error":"forbidden"}'))), isNot(contains('forbidden.ip-allowlist')));
    });
  });

  group('CSRF, Origin, Referer, X-Requested-With', () {
    const cookie = {'Cookie': 'sessionid=abc123def456', 'Content-Type': 'application/x-www-form-urlencoded'};
    const django = '<!DOCTYPE html><html><body><h1>Forbidden <span>(403)</span></h1><p>CSRF verification failed. Request aborted.</p></body></html>';

    test('a cookie session without a CSRF header, after the server says CSRF', () {
      final findings = AuthDoctor.diagnose(rejected(status: 403, method: 'POST', headers: cookie, authType: AuthType.none, body: django));

      final csrf = byId(findings, 'forbidden.csrf');
      expect(csrf.confidence, FindingConfidence.likely);
      expect(csrf.evidence, contains('The request has no header with "csrf" or "xsrf" in its name.'));
    });

    test('a request that does send a CSRF header is not told to', () {
      final findings = AuthDoctor.diagnose(rejected(
        status: 403,
        method: 'POST',
        headers: {...cookie, 'X-CSRF-Token': 'abcdef0123456789'},
        authType: AuthType.none,
        body: django,
      ));

      expect(ids(findings), isNot(contains('forbidden.csrf')));
    });

    test('Laravel\'s 419 is a rejection the doctor answers', () {
      final findings = AuthDoctor.diagnose(rejected(status: 419, method: 'POST', headers: cookie, authType: AuthType.none, body: '{"message":"CSRF token mismatch."}'));

      expect(ids(findings), contains('forbidden.csrf'));
    });

    test('Django\'s origin check names the Origin header', () {
      final findings = AuthDoctor.diagnose(rejected(
        status: 403,
        method: 'POST',
        headers: cookie,
        authType: AuthType.none,
        body: '{"detail":"CSRF Failed: Origin checking failed - null does not match any trusted origins."}',
      ));

      expect(byId(findings, 'forbidden.origin').title, 'The server wants an Origin header');
      expect(ids(findings), contains('forbidden.csrf'));
    });

    test('X-Requested-With', () {
      final findings = AuthDoctor.diagnose(rejected(status: 403, headers: const {'Cookie': 's=1'}, authType: AuthType.none, body: 'X-Requested-With header required'));

      expect(ids(findings), contains('forbidden.xhr'));
    });

    test('a cookie-only POST that got an empty 403 is a possibility, a Bearer call is not', () {
      final cookieOnly = AuthDoctor.diagnose(rejected(status: 403, method: 'POST', headers: const {'Cookie': 's=1'}, authType: AuthType.none));
      expect(byId(cookieOnly, 'forbidden.csrf-maybe').confidence, FindingConfidence.possible);

      final bearer = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, method: 'POST'));
      expect(ids(bearer), isNot(contains('forbidden.csrf-maybe')));
    });
  });

  group('the Allow header', () {
    test('a method the URL does not allow is certain', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        method: 'POST',
        responseHeaders: const {'Allow': 'GET, HEAD'},
      ));

      final method = byId(findings, 'forbidden.method');
      expect(method.confidence, FindingConfidence.certain);
      expect(method.title, 'This URL does not allow POST');
      expect(method.evidence, ['Allow: GET, HEAD', 'The request method: POST']);
    });

    test('a method that is on the list is left alone', () {
      final findings = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, responseHeaders: const {'Allow': 'GET, HEAD'}));

      expect(ids(findings), isNot(contains('forbidden.method')));
    });
  });

  group('rate limit', () {
    test('no requests remaining, with the reset time as a Unix time: certain, and how long to wait', () {
      final findings = AuthDoctor.diagnose(withBearer(
        'opaque-token-0123456789abcdef',
        status: 403,
        responseHeaders: {'X-RateLimit-Remaining': '0', 'X-RateLimit-Limit': '60', 'X-RateLimit-Reset': '${epoch(clock) + 600}'},
      ));

      final limit = byId(findings, 'forbidden.rate-limit');
      expect(limit.confidence, FindingConfidence.certain);
      expect(limit.explanation, contains('It resets in 10 minutes.'));
      expect(limit.evidence, containsAll(['Remaining: 0', 'Limit: 60']));
    });

    test('Retry-After in seconds, and as a date', () {
      final seconds = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, responseHeaders: const {'Retry-After': '120'}));
      expect(byId(seconds, 'forbidden.rate-limit').explanation, contains('retry after 2 minutes'));
      expect(byId(seconds, 'forbidden.rate-limit').confidence, FindingConfidence.likely);

      final date = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, responseHeaders: const {'Retry-After': 'Thu, 08 Oct 2026 12:05:00 GMT'}));
      expect(byId(date, 'forbidden.rate-limit').explanation, contains('retry in 5 minutes'));
    });

    test('the words alone, and requests that remain', () {
      final worded = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, body: '{"message":"API rate limit exceeded for user ID 42."}'));
      expect(byId(worded, 'forbidden.rate-limit').confidence, FindingConfidence.likely);

      final remaining = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, responseHeaders: const {'X-RateLimit-Remaining': '58'}));
      expect(ids(remaining), isNot(contains('forbidden.rate-limit')));
    });
  });

  group('signatures and clocks', () {
    const sigv4 = 'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20261008/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-date, Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7';

    test('RequestTimeTooSkewed, with the difference between the two clocks', () {
      final findings = AuthDoctor.diagnose(rejected(
        status: 403,
        headers: const {'Authorization': sigv4},
        authType: AuthType.awsSignatureV4,
        responseHeaders: const {'Date': 'Thu, 08 Oct 2026 12:20:00 GMT', 'Content-Type': 'application/xml'},
        body: '<?xml version="1.0" encoding="UTF-8"?><Error><Code>RequestTimeTooSkewed</Code>'
            '<Message>The difference between the request time and the current time is too large.</Message></Error>',
      ));

      final skew = byId(findings, 'signature.clock-skew');
      expect(skew.confidence, FindingConfidence.certain);
      expect(skew.explanation, contains('differ by 20 minutes'));
      expect(skew.evidence, contains('The server\'s Date header is 20 minutes ahead of this computer.'));
    });

    test('a signed request whose clock is far off is likely a clock problem even without the words', () {
      final findings = AuthDoctor.diagnose(rejected(
        status: 403,
        headers: const {'Authorization': sigv4},
        authType: AuthType.awsSignatureV4,
        responseHeaders: const {'Date': 'Thu, 08 Oct 2026 11:30:00 GMT'},
      ));

      final skew = byId(findings, 'signature.clock-skew');
      expect(skew.confidence, FindingConfidence.likely);
      expect(skew.evidence, contains('The server\'s Date header is 30 minutes behind this computer.'));
    });

    test('SignatureDoesNotMatch for SigV4 points at the region and service', () {
      final findings = AuthDoctor.diagnose(rejected(
        status: 403,
        headers: const {'Authorization': sigv4},
        authType: AuthType.awsSignatureV4,
        body: '<Error><Code>SignatureDoesNotMatch</Code><Message>The request signature we calculated does not match the signature you provided.</Message></Error>',
      ));

      final mismatch = byId(findings, 'signature.mismatch');
      expect(mismatch.confidence, FindingConfidence.likely);
      expect(mismatch.fix, contains('region and the service'));
    });

    test('an HMAC signature the server does not accept points at the settings that decide it', () {
      final findings = AuthDoctor.diagnose(rejected(
        status: 401,
        method: 'POST',
        headers: const {'X-Hub-Signature-256': 'sha256=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7'},
        authType: AuthType.hmac,
        body: '{"error":"Signature mismatch"}',
      ));

      final mismatch = byId(findings, 'signature.mismatch');
      expect(mismatch.fix, contains('the signed payload'));
      expect(mismatch.fix, contains('exact bytes that are sent'));
      expect(mismatch.evidence, contains('Auth type: HMAC signature'));
      // The signature header is a credential, so nothing is "missing".
      expect(ids(findings), isNot(contains('credential.none-sent')));
    });

    test('a signature error from a hand-made HMAC scheme gets the general advice', () {
      final findings = AuthDoctor.diagnose(rejected(
        status: 401,
        headers: const {'X-Signature': 'abcdef0123456789abcdef'},
        authType: AuthType.apiKey,
        apiKeyName: 'X-Signature',
        body: '{"error":"Invalid signature"}',
      ));

      expect(byId(findings, 'signature.mismatch').fix, contains('exact bytes that are signed'));
    });
  });

  group('a credential lost in a redirect', () {
    test('http to https drops the credential: certain when the hop is known', () {
      final findings = AuthDoctor.diagnose(rejected(
        redirects: const [AuthRedirectHop(from: 'http://example.com/api/orders', to: 'https://example.com/api/orders', status: 301)],
        url: 'https://example.com/api/orders',
      ));

      final dropped = byId(findings, 'redirect.credentials-dropped');
      expect(dropped.confidence, FindingConfidence.certain);
      expect(dropped.evidence, contains('Redirect 301: http://example.com to https://example.com'));
    });

    test('another host or another port drops it; a subdomain of the same host does not', () {
      bool dropped(String from, String to) => ids(AuthDoctor.diagnose(rejected(redirects: [AuthRedirectHop(from: from, to: to)]))).contains('redirect.credentials-dropped');

      expect(dropped('https://app.example.com/x', 'https://login.other.net/x'), isTrue);
      expect(dropped('https://example.com/x', 'https://example.com:8443/x'), isTrue);
      expect(dropped('https://example.com/x', 'https://api.example.com/x'), isFalse);
      expect(dropped('https://example.com/x', 'https://example.com/y'), isFalse);
    });

    test('without a known hop, an http URL is a possibility; https, localhost and a private address are not', () {
      Iterable<String> found(String url, {int status = 401}) => ids(AuthDoctor.diagnose(rejected(url: url, status: status)));

      expect(found('http://api.example.com/v1/orders'), contains('redirect.http'));
      expect(found('https://api.example.com/v1/orders'), isNot(contains('redirect.http')));
      expect(found('http://localhost:3000/v1/orders'), isNot(contains('redirect.http')));
      expect(found('http://192.168.1.20/v1/orders'), isNot(contains('redirect.http')));
      expect(found('http://api.example.com/v1/orders', status: 403), isNot(contains('redirect.http')));
    });

    test('a request that sent no credential has nothing to lose', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {},
        authType: AuthType.none,
        redirects: const [AuthRedirectHop(from: 'http://example.com/x', to: 'https://example.com/x')],
      ));

      expect(ids(findings), isNot(contains('redirect.credentials-dropped')));
    });
  });
}
