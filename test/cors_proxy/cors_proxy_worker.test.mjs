// Runs the Cloudflare Worker (tool/cors_proxy_worker.js) against a local upstream and asserts the same cases as the Dart proxy
// tests. Started by cors_proxy_worker_test.dart, or by hand: node --test test/cors_proxy/cors_proxy_worker.test.mjs
import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// The Worker file is plain `export default`; a copy named .mjs loads as a module on every Node version.
const here = dirname(fileURLToPath(import.meta.url));
const copy = join(mkdtempSync(join(tmpdir(), 'pp-worker-')), 'worker.mjs');
writeFileSync(copy, readFileSync(join(here, '..', '..', 'tool', 'cors_proxy_worker.js')));
const worker = (await import(pathToFileURL(copy).href)).default;

const TOKEN = 'worker-token-123456';
const PAGE = 'http://localhost:3000';
const HOSTED = 'https://manzurulislambista.github.io';
const WORKER = 'https://postpilot-cors-proxy.example.workers.dev';
const env = { POSTPILOT_TOKEN: TOKEN };

let upstream;
let base;
let seen = [];

before(async () => {
  upstream = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      const url = new URL(req.url, 'http://upstream');
      seen.push({ method: req.method, path: url.pathname, query: url.search.slice(1), headers: req.headers, body });
      if (url.pathname === '/echo') {
        res.writeHead(200, { 'content-type': 'application/json', 'x-upstream': 'yes' });
        res.end(JSON.stringify({ method: req.method, path: url.pathname, query: url.search.slice(1), headers: req.headers, body }));
      } else if (url.pathname === '/redirect') {
        res.writeHead(302, { location: '/echo?from=redirect' });
        res.end();
      } else if (url.pathname === '/cookies') {
        res.writeHead(200, {
          'set-cookie': ['sid=abc123; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly', 'theme=dark; Path=/; SameSite=Lax'],
        });
        res.end('cookies');
      } else if (url.pathname === '/slow-body') {
        // Answers at once and finishes long after the Worker's limit: a download, not a hang.
        res.writeHead(200, { 'content-type': 'text/plain' });
        res.write('first,');
        setTimeout(() => res.end('last'), 700);
      } else if (url.pathname === '/slow-start') {
        setTimeout(() => {
          res.writeHead(200);
          res.end('late');
        }, 1500);
      } else if (url.pathname === '/cors') {
        res.writeHead(200, { 'access-control-allow-origin': '*', 'x-postpilot-proxy-error': 'spoof', 'x-postpilot-status': '999' });
        res.end('ok');
      } else {
        res.writeHead(404);
        res.end('nothing here');
      }
    });
  });
  await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${upstream.address().port}`;
});

after(() => {
  upstream.closeAllConnections();
  upstream.close();
});

/** The call a web page makes: the real address, the token and the page's origin. */
function call(method, target, { origin = PAGE, token = TOKEN, extra = {}, body, path = '/', environment = env } = {}) {
  const headers = { ...extra };
  if (target !== null) headers['x-postpilot-url'] = target;
  if (token !== null) headers['x-postpilot-token'] = token;
  if (origin !== null) headers.origin = origin;
  return worker.fetch(new Request(WORKER + path, { method, headers, body }), environment);
}

const json = async (response) => JSON.parse(await response.text());

test('a preflight is answered by the Worker for an allowed page: origin echoed, never *, no token', async () => {
  seen = [];
  const res = await worker.fetch(
    new Request(WORKER + '/', {
      method: 'OPTIONS',
      headers: {
        origin: PAGE,
        'access-control-request-method': 'POST',
        'access-control-request-headers': 'authorization, content-type, x-postpilot-url, x-postpilot-token',
        'access-control-request-private-network': 'true',
      },
    }),
    env,
  );

  assert.equal(res.status, 204);
  assert.equal(res.headers.get('access-control-allow-origin'), PAGE);
  assert.match(res.headers.get('vary'), /Origin/);
  assert.ok(res.headers.get('access-control-allow-headers').startsWith('*'));
  assert.match(res.headers.get('access-control-allow-headers'), /authorization/);
  assert.match(res.headers.get('access-control-allow-headers'), /x-postpilot-url/);
  for (const m of ['POST', 'DELETE', 'PATCH']) assert.match(res.headers.get('access-control-allow-methods'), new RegExp(m));
  assert.equal(res.headers.get('access-control-allow-private-network'), 'true');
  assert.ok(res.headers.get('access-control-max-age'));
  assert.equal(seen.length, 0, 'a preflight is never forwarded');
});

test('a preflight from a page that is not allowed is refused with nothing the browser could read', async () => {
  const res = await worker.fetch(
    new Request(WORKER + '/', { method: 'OPTIONS', headers: { origin: 'https://evil.example', 'access-control-request-method': 'GET' } }),
    env,
  );

  assert.equal(res.status, 403);
  assert.equal(res.headers.get('access-control-allow-origin'), null);
  const body = await json(res);
  assert.equal(body.error, 'origin_not_allowed');
  assert.match(body.message, /ALLOWED_ORIGINS/);
});

test('forwards method, query, headers and body, and passes status, headers and body back with CORS headers', async () => {
  seen = [];
  const res = await call('POST', `${base}/echo?page=2&q=a%20b`, {
    extra: {
      authorization: 'Bearer abc.def',
      'content-type': 'application/json',
      'x-custom': 'custom-value',
      referer: 'http://localhost:3000/app',
      'sec-ch-ua-platform': '"Windows"',
      'cf-connecting-ip': '203.0.113.9',
      'x-forwarded-for': '203.0.113.9',
      'access-control-request-method': 'POST',
    },
    body: '{"name":"Ada"}',
    path: '/mirrored/path',
  });

  assert.equal(res.status, 200);
  assert.equal(res.headers.get('x-upstream'), 'yes');
  const echo = await json(res);
  assert.equal(echo.method, 'POST');
  assert.equal(echo.path, '/echo');
  assert.equal(echo.query, 'page=2&q=a%20b');
  assert.equal(echo.body, '{"name":"Ada"}');
  assert.equal(echo.headers.authorization, 'Bearer abc.def');
  assert.equal(echo.headers['x-custom'], 'custom-value');
  assert.equal(echo.headers['content-type'], 'application/json');
  for (const page of ['origin', 'referer', 'sec-ch-ua-platform', 'x-postpilot-url', 'x-postpilot-token', 'access-control-request-method', 'cf-connecting-ip', 'x-forwarded-for']) {
    assert.ok(!(page in echo.headers), `${page} describes the web page or the Worker, not the call`);
  }
  assert.equal(res.headers.get('access-control-allow-origin'), PAGE);
  assert.match(res.headers.get('vary'), /X-PostPilot-Url/, 'a cache must not serve ?page=1 for ?page=2');
  assert.ok(res.headers.get('access-control-expose-headers').startsWith('*'));
  assert.match(res.headers.get('access-control-expose-headers'), /x-upstream/);
  assert.equal(res.headers.get('access-control-allow-headers'), '*');
});

test('the time limit is for the server to start answering: a download that takes longer is not cut', async () => {
  const slow = { ...env, UPSTREAM_TIMEOUT_MS: '300' };
  const download = await call('GET', `${base}/slow-body`, { environment: slow });

  assert.equal(download.status, 200);
  assert.equal(await download.text(), 'first,last');

  const hang = await call('GET', `${base}/slow-start`, { environment: slow });
  assert.equal(hang.status, 502);
  assert.equal(hang.headers.get('x-postpilot-proxy-error'), 'upstream_timeout');
  assert.match((await json(hang)).message, /within 300 ms/);
});

test('forwards every method', async () => {
  seen = [];
  for (const method of ['GET', 'PUT', 'PATCH', 'DELETE', 'HEAD']) {
    const res = await call(method, `${base}/echo`, { body: method === 'PUT' || method === 'PATCH' ? 'x' : undefined });
    assert.equal(res.status, 200, method);
  }
  assert.deepEqual(seen.map((s) => s.method), ['GET', 'PUT', 'PATCH', 'DELETE', 'HEAD']);
});

test('every call but a preflight needs the token', async () => {
  seen = [];
  const missing = await call('GET', `${base}/echo`, { token: null });
  assert.equal(missing.status, 401);
  assert.equal(missing.headers.get('x-postpilot-proxy-error'), 'token_required');
  assert.equal(missing.headers.get('access-control-allow-origin'), PAGE, 'so the page can read why');

  const wrong = await call('GET', `${base}/echo`, { token: 'worker-token-123457' });
  assert.equal(wrong.status, 401);
  assert.equal(wrong.headers.get('x-postpilot-proxy-error'), 'token_invalid');

  const longer = await call('GET', `${base}/echo`, { token: TOKEN + '-and-more' });
  assert.equal(longer.status, 401);
  assert.equal(seen.length, 0);
});

test('pages on this computer and the hosted app are allowed by default, any other is refused', async () => {
  seen = [];
  for (const origin of ['http://localhost:5173', 'http://127.0.0.1:3000', 'http://[::1]:3000', 'https://localhost:8443', HOSTED]) {
    const res = await call('GET', `${base}/echo`, { origin });
    assert.equal(res.status, 200, origin);
    assert.equal(res.headers.get('access-control-allow-origin'), origin, origin);
  }
  const before = seen.length;
  for (const origin of ['https://evil.example', 'null', 'http://localhost.evil.com', 'http://127.0.0.1.evil.com', 'http://manzurulislambista.github.io', `${HOSTED}:8443`]) {
    const res = await call('GET', `${base}/echo`, { origin });
    assert.equal(res.status, 403, origin);
    assert.equal(res.headers.get('x-postpilot-proxy-error'), 'origin_not_allowed', origin);
    assert.equal(res.headers.get('access-control-allow-origin'), null, `the page must not be able to read it: ${origin}`);
  }
  assert.equal(seen.length, before, 'nothing of a refused call reaches the target');
});

test('ALLOWED_ORIGINS replaces the hosted default, localhost stays allowed', async () => {
  const environment = { POSTPILOT_TOKEN: TOKEN, ALLOWED_ORIGINS: 'https://app.example.com, https://b.example.com/' };

  assert.equal((await call('GET', `${base}/echo`, { origin: 'https://app.example.com', environment })).status, 200);
  assert.equal((await call('GET', `${base}/echo`, { origin: 'https://b.example.com', environment })).status, 200);
  assert.equal((await call('GET', `${base}/echo`, { origin: HOSTED, environment })).status, 403);
  assert.equal((await call('GET', `${base}/echo`, { origin: 'http://localhost:3000', environment })).status, 200);
});

test('a call without an Origin (not a browser) works with the token and gets no CORS headers', async () => {
  const res = await call('GET', `${base}/echo`, { origin: null });

  assert.equal(res.status, 200);
  assert.equal([...res.headers.keys()].filter((k) => k.startsWith('access-control-')).length, 0);
});

test('the target cannot spoof the Worker: its CORS and X-PostPilot headers never reach the page', async () => {
  const res = await call('GET', `${base}/cors`);

  assert.equal(res.headers.get('access-control-allow-origin'), PAGE);
  assert.equal(res.headers.get('x-postpilot-proxy-error'), null);
  assert.equal(res.headers.get('x-postpilot-status'), null);
});

test('Set-Cookie lines are repeated in one header, whole, with the comma of Expires intact', async () => {
  const res = await call('GET', `${base}/cookies`);

  assert.deepEqual(JSON.parse(res.headers.get('x-postpilot-set-cookie')), [
    'sid=abc123; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly',
    'theme=dark; Path=/; SameSite=Lax',
  ]);
  assert.match(res.headers.get('access-control-expose-headers'), /x-postpilot-set-cookie/);
  assert.ok(/^[\x20-\x7e]+$/.test(res.headers.get('x-postpilot-set-cookie')), 'ASCII only');
});

test('a redirect is passed on untouched, and shown as a 200 naming its real status when the page asks', async () => {
  seen = [];
  const plain = await call('GET', `${base}/redirect`);
  assert.equal(plain.status, 302);
  assert.equal(plain.headers.get('location'), '/echo?from=redirect');
  assert.equal(seen.length, 1, 'the Worker does not follow it');

  const hidden = await call('GET', `${base}/redirect`, { extra: { 'x-postpilot-redirects': 'manual' } });
  assert.equal(hidden.status, 200);
  assert.equal(hidden.headers.get('x-postpilot-status'), '302');
  assert.equal(hidden.headers.get('x-postpilot-status-text'), 'Found');
  assert.equal(hidden.headers.get('location'), '/echo?from=redirect');
  assert.match(hidden.headers.get('access-control-expose-headers'), /x-postpilot-status/);
  assert.equal(seen.length, 2);
});

test('health answers ok with the version and the page that was allowed, and wants the token', async () => {
  const ok = await call('GET', null, { path: '/__postpilot/health' });
  assert.equal(ok.status, 200);
  assert.deepEqual(await json(ok), { ok: true, version: '1', allowedOrigin: PAGE });
  assert.equal(ok.headers.get('access-control-allow-origin'), PAGE);

  const noToken = await call('GET', null, { path: '/__postpilot/health', token: null });
  assert.equal(noToken.status, 401);
  assert.equal(noToken.headers.get('x-postpilot-proxy-error'), 'token_required');

  const noOrigin = await call('GET', null, { path: '/__postpilot/health', origin: null });
  assert.equal((await json(noOrigin)).allowedOrigin, null);

  seen = [];
  const forwarded = await call('GET', `${base}/__postpilot/health`);
  assert.equal(forwarded.status, 404, 'a target whose path is the health path is forwarded');
  assert.equal(seen[0].path, '/__postpilot/health');
});

test('refuses to forward to itself, to a non-http address, or to nothing', async () => {
  seen = [];
  const cases = [
    [`${WORKER}/anything`, 508, 'proxy_loop'],
    ['ftp://example.com/file', 400, 'unsupported_scheme'],
    ['file:///etc/passwd', 400, 'unsupported_scheme'],
    ['/relative/path', 400, 'unsupported_scheme'],
    ['not a url', 400, 'invalid_target'],
    [null, 400, 'missing_target'],
  ];
  for (const [target, status, code] of cases) {
    const res = await call('GET', target);
    assert.equal(res.status, status, String(target));
    assert.equal(res.headers.get('x-postpilot-proxy-error'), code, String(target));
  }
  assert.equal(seen.length, 0);
});

test('a server that is not there is a 502 that names it, never the query', async () => {
  const probe = http.createServer();
  await new Promise((resolve) => probe.listen(0, '127.0.0.1', resolve));
  const closed = probe.address().port;
  await new Promise((resolve) => probe.close(resolve));

  const res = await call('GET', `http://127.0.0.1:${closed}/secret/path?api_key=SUPERSECRETVALUE`);

  assert.equal(res.status, 502);
  assert.equal(res.headers.get('x-postpilot-proxy-error'), 'upstream_unreachable');
  assert.equal(res.headers.get('access-control-allow-origin'), PAGE);
  const text = await res.text();
  assert.match(text, new RegExp(`127.0.0.1:${closed}`));
  assert.ok(!text.includes('SUPERSECRETVALUE'));
  assert.ok(!text.includes('/secret/path'));
});

test('a Worker without a token says how to set one', async () => {
  const res = await call('GET', `${base}/echo`, { environment: {} });

  assert.equal(res.status, 500);
  assert.equal(res.headers.get('x-postpilot-proxy-error'), 'not_configured');
  assert.match((await json(res)).message, /wrangler secret put POSTPILOT_TOKEN/);
});

test('nothing is logged: no value reaches the console', async () => {
  const logged = [];
  const originals = {};
  for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
    originals[level] = console[level];
    console[level] = (...args) => logged.push(args);
  }
  try {
    await call('POST', `${base}/echo?api_key=SUPERSECRETVALUE`, { extra: { authorization: 'Bearer s3cr3t' }, body: 'password=topsecret' });
    await call('GET', `${base}/echo`, { token: 'wrong-token-1234' });
    await call('GET', 'http://127.0.0.1:1/never');
  } finally {
    for (const level of Object.keys(originals)) console[level] = originals[level];
  }
  assert.deepEqual(logged, []);
});
