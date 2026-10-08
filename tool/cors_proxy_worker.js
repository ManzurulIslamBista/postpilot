// PostPilot CORS proxy as a Cloudflare Worker: the same protocol as `dart run bin/postpilot.dart proxy`, for people who use
// the hosted web version and cannot run a program on their computer. Deploy your own copy (free tier is plenty):
//
//   wrangler deploy cors_proxy_worker.js --name postpilot-cors-proxy --compatibility-date 2025-01-01
//   wrangler secret put POSTPILOT_TOKEN --name postpilot-cors-proxy
//
// Settings (Worker secret / variable):
//   POSTPILOT_TOKEN  required, the secret the web app sends in X-PostPilot-Token. Every call but a preflight needs it.
//   ALLOWED_ORIGINS  optional, comma separated web pages that may use the proxy (https://app.example.com). Defaults to the
//                    hosted PostPilot. Pages on localhost / 127.0.0.1 / [::1] are always allowed.
//
// The web app sends its real request here with the target in X-PostPilot-Url. The Worker forwards it (no redirect is
// followed, a 60 second limit applies) and answers with the CORS headers the target lacks. Nothing is logged: no console
// output, no header, no body, no address.

const VERSION = '1';
const DEFAULT_ORIGINS = ['https://manzurulislambista.github.io'];
const TIMEOUT_MS = 60000;
const METHODS = 'GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS';
const REDIRECTS = [301, 302, 303, 307, 308];
const TOKEN_CHARS = /^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/;
const HOP_BY_HOP = ['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'proxy-connection', 'te', 'trailer', 'transfer-encoding', 'upgrade'];

export default {
  async fetch(request, env) {
    return handle(request, env || {});
  },
};

/** `scheme://host[:port]` written as a browser writes an Origin (default port dropped); null when it is not an origin. */
function normalizeOrigin(text) {
  const t = String(text || '').trim();
  if (!t || t.includes('*') || /\s/.test(t)) return null;
  let url;
  try {
    url = new URL(t);
  } catch (_) {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  if (url.username || url.password || url.search || url.hash || (url.pathname && url.pathname !== '/')) return null;
  return url.origin;
}

function isLoopbackOrigin(origin) {
  let url;
  try {
    url = new URL(origin);
  } catch (_) {
    return false;
  }
  const host = url.hostname.toLowerCase();
  return host === 'localhost' || host === '[::1]' || /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host);
}

/** The origin that may read the answer: the normalized Origin of the page when it is allowed, else null. */
function allowedOrigin(origin, env) {
  const normalized = normalizeOrigin(origin);
  if (!normalized) return null;
  if (isLoopbackOrigin(normalized)) return normalized;
  const configured = env.ALLOWED_ORIGINS === undefined || env.ALLOWED_ORIGINS === '' ? DEFAULT_ORIGINS : String(env.ALLOWED_ORIGINS).split(/[,\s]+/);
  return configured.map(normalizeOrigin).includes(normalized) ? normalized : null;
}

/** Compares in a time that does not depend on how many leading characters match. */
function sameToken(given, expected) {
  if (given === null || given === undefined) return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  let diff = a.length ^ b.length;
  for (let i = 0; i < b.length; i++) diff |= (i < a.length ? a[i] : 0) ^ b[i];
  return diff === 0;
}

/** A JSON array of the cookie lines in ASCII only, because a header value holds nothing else. */
function encodeSetCookies(cookies) {
  return JSON.stringify(cookies).replace(/[^\x20-\x7e]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
}

function addCors(headers, origin, expose) {
  headers.set('access-control-allow-origin', origin);
  headers.append('vary', 'Origin');
  // The address the browser requests names only the Worker and the path of the real one; without this a cache would serve
  // `?page=1` for `?page=2`, or the staging answer for the same path on production.
  headers.append('vary', 'X-PostPilot-Url');
  headers.set('access-control-allow-headers', '*');
  headers.set('access-control-allow-methods', METHODS);
  headers.set('access-control-expose-headers', ['*'].concat(expose || []).join(', '));
}

function answer(status, body, origin, errorCode) {
  const headers = new Headers({ 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  if (errorCode) headers.set('x-postpilot-proxy-error', errorCode);
  if (origin) addCors(headers, origin, ['x-postpilot-proxy-error']);
  return new Response(JSON.stringify(body), { status, headers });
}

function refuse(status, code, message, origin) {
  return answer(status, { error: code, message, proxy: 'PostPilot CORS proxy (Cloudflare Worker)' }, origin, code);
}

function preflight(request, origin) {
  const wanted = request.headers.get('access-control-request-headers');
  const method = (request.headers.get('access-control-request-method') || '').trim().toUpperCase();
  const names = ['*'];
  // A wildcard never covers Authorization, so what the page asked for is listed as well.
  if (wanted) for (const name of wanted.split(',')) if (TOKEN_CHARS.test(name.trim())) names.push(name.trim());
  const methods = new Set(METHODS.split(', '));
  if (TOKEN_CHARS.test(method)) methods.add(method);
  const headers = new Headers();
  headers.set('access-control-allow-origin', origin);
  headers.append('vary', 'Origin');
  headers.append('vary', 'Access-Control-Request-Headers');
  headers.set('access-control-allow-methods', Array.from(methods).join(', '));
  headers.set('access-control-allow-headers', names.join(', '));
  headers.set('access-control-max-age', '600');
  // Chrome asks before a public page may reach a private address.
  headers.set('access-control-allow-private-network', 'true');
  headers.set('x-postpilot-proxy', 'preflight');
  return new Response(null, { status: 204, headers });
}

/** The target as a URL, or a refusal [status, code, message]. */
function parseTarget(text, own) {
  const value = (text || '').trim();
  if (!value) return [400, 'missing_target', 'The X-PostPilot-Url header is missing. It names the address the call is for.'];
  if (/[\s\x00-\x1f\x7f]/.test(value)) return [400, 'invalid_target', 'The address in X-PostPilot-Url is not a valid URL.'];
  let url;
  try {
    url = new URL(value);
  } catch (_) {
    return /^[a-z][a-z0-9+.-]*:/i.test(value)
      ? [400, 'invalid_target', 'The address in X-PostPilot-Url is not a valid URL.']
      : [400, 'unsupported_scheme', 'Only http:// and https:// addresses can be forwarded, not "no scheme".'];
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    return [400, 'unsupported_scheme', 'Only http:// and https:// addresses can be forwarded, not "' + url.protocol.replace(':', '') + '".'];
  }
  if (!url.hostname) return [400, 'invalid_target', 'The address in X-PostPilot-Url has no host.'];
  if (url.host.toLowerCase() === own.toLowerCase()) {
    return [508, 'proxy_loop', 'That address is this proxy itself, so forwarding it would loop forever. Use the address of the real server.'];
  }
  return url;
}

async function handle(request, env) {
  const method = request.method.toUpperCase();
  const url = new URL(request.url);
  const requestedOrigin = request.headers.get('origin');
  const origin = requestedOrigin === null ? null : allowedOrigin(requestedOrigin, env);

  if (!env.POSTPILOT_TOKEN) {
    return refuse(500, 'not_configured', 'The Worker has no token yet. Run: wrangler secret put POSTPILOT_TOKEN --name <your worker name>', origin);
  }
  if (requestedOrigin !== null && origin === null) {
    const shown = requestedOrigin.replace(/\s+/g, ' ').trim().slice(0, 120);
    return refuse(403, 'origin_not_allowed', 'The page at ' + shown + ' is not allowed to use this proxy. Set the ALLOWED_ORIGINS variable of the Worker to include ' + shown + '.', null);
  }

  // The preflight a browser sends before a call with custom headers: answered here, never forwarded, no token.
  if (method === 'OPTIONS' && request.headers.get('access-control-request-method') !== null) {
    if (origin === null) return refuse(403, 'origin_required', 'A browser preflight needs an Origin header, and the origin must be allowed.', null);
    return preflight(request, origin);
  }

  const given = request.headers.get('x-postpilot-token');
  if (!given) {
    return refuse(401, 'token_required', 'The X-PostPilot-Token header is missing. Paste the token you gave the Worker into PostPilot (Settings > CORS proxy).', origin);
  }
  if (!sameToken(given, String(env.POSTPILOT_TOKEN))) {
    return refuse(401, 'token_invalid', 'The token is wrong. Paste the token you gave the Worker into PostPilot (Settings > CORS proxy).', origin);
  }

  const targetHeader = request.headers.get('x-postpilot-url');
  if (targetHeader === null && url.pathname === '/__postpilot/health' && (method === 'GET' || method === 'HEAD')) {
    return answer(200, { ok: true, version: VERSION, allowedOrigin: origin }, origin);
  }
  if (request.headers.get('upgrade') !== null) {
    return refuse(501, 'not_supported', 'This proxy forwards plain HTTP calls only: no WebSocket upgrade.', origin);
  }

  const target = parseTarget(targetHeader, url.host);
  if (Array.isArray(target)) return refuse(target[0], target[1], target[2], origin);

  const out = new Headers();
  for (const [name, value] of request.headers) {
    const lower = name.toLowerCase();
    // Origin, Referer and the Sec- headers describe the web page, not the call it makes for the person; cf-* and
    // x-forwarded-* are the Worker's own plumbing.
    if (HOP_BY_HOP.includes(lower) || lower === 'host' || lower === 'content-length' || lower === 'expect' || lower === 'origin' ||
        lower === 'referer' || lower.startsWith('sec-') || lower.startsWith('access-control-request-') || lower.startsWith('x-postpilot-') ||
        lower.startsWith('cf-') || lower.startsWith('x-forwarded-') || lower === 'x-real-ip' || lower === 'true-client-ip') continue;
    out.append(name, value);
  }
  const hasBody = method !== 'GET' && method !== 'HEAD' && request.body !== null;
  const hide = (request.headers.get('x-postpilot-redirects') || '').trim().toLowerCase() === 'manual';

  // The limit is for the server to start answering: a signal that is left armed would also cut a long download in the middle.
  const limit = new AbortController();
  // UPSTREAM_TIMEOUT_MS is for the tests; a deployed Worker keeps the 60 seconds.
  const limitMs = Number(env.UPSTREAM_TIMEOUT_MS) > 0 ? Number(env.UPSTREAM_TIMEOUT_MS) : TIMEOUT_MS;
  const timer = setTimeout(() => limit.abort(), limitMs);
  let upstream;
  try {
    upstream = await fetch(target.toString(), {
      method,
      headers: out,
      body: hasBody ? request.body : undefined,
      redirect: 'manual',
      duplex: 'half',
      signal: limit.signal,
    });
    clearTimeout(timer);
  } catch (e) {
    clearTimeout(timer);
    const timedOut = e && (e.name === 'TimeoutError' || e.name === 'AbortError');
    return timedOut
      ? refuse(502, 'upstream_timeout', target.host + ' did not answer within ' + (limitMs >= 1000 ? limitMs / 1000 + ' seconds' : limitMs + ' ms') + '. Is the server running and reachable from the internet?', origin)
      : refuse(502, 'upstream_unreachable', 'Could not reach ' + target.host + '. Check the address; a Worker can only reach servers on the public internet.', origin);
  }

  const headers = new Headers();
  const exposed = new Set();
  for (const [name, value] of upstream.headers) {
    const lower = name.toLowerCase();
    if (lower === 'set-cookie' || HOP_BY_HOP.includes(lower) || lower.startsWith('access-control-') || lower.startsWith('x-postpilot-')) continue;
    if (lower === 'content-length' && upstream.headers.has('content-encoding')) continue;
    headers.append(name, value);
    if (TOKEN_CHARS.test(lower)) exposed.add(lower);
  }
  // A browser hides Set-Cookie from a page: the lines are repeated in one header, as a JSON array.
  const cookies = typeof upstream.headers.getSetCookie === 'function' ? upstream.headers.getSetCookie() : [];
  for (const cookie of cookies) headers.append('set-cookie', cookie);
  if (cookies.length) {
    headers.set('x-postpilot-set-cookie', encodeSetCookies(cookies));
    exposed.add('x-postpilot-set-cookie');
  }
  // A browser follows a 3xx by itself and never shows it to the page: on request it is shown as a 200 naming its status.
  const hidden = hide && REDIRECTS.includes(upstream.status);
  if (hidden) {
    headers.set('x-postpilot-status', String(upstream.status));
    headers.set('x-postpilot-status-text', String(upstream.statusText || '').replace(/\s+/g, ' ').trim());
    exposed.add('x-postpilot-status');
    exposed.add('x-postpilot-status-text');
  }
  if (origin) addCors(headers, origin, Array.from(exposed));
  const bodyless = method === 'HEAD' || upstream.status < 200 || upstream.status === 204 || upstream.status === 304;
  return new Response(bodyless ? null : upstream.body, {
    status: hidden ? 200 : upstream.status,
    statusText: hidden ? 'OK' : upstream.statusText,
    headers,
  });
}
