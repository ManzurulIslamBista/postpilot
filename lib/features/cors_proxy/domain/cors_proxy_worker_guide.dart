// Pure Dart: the steps to deploy the CORS proxy as a Cloudflare Worker (tool/cors_proxy_worker.js), for people who use the
// hosted web version and cannot run a program on their computer. Shown in Settings > CORS proxy; the README repeats the
// commands, and a test keeps the two in step.
import 'cors_proxy_protocol.dart';

abstract final class CorsProxyWorkerGuide {
  static const title = 'Deploy your own CORS proxy (2 minutes)';

  static const workerName = 'postpilot-cors-proxy';

  /// The origin of the hosted web app, which the Worker allows unless told otherwise.
  static const hostedOrigin = 'https://manzurulislambista.github.io';

  static const workerSourceUrl = 'https://raw.githubusercontent.com/ManzurulIslamBista/postpilot/HEAD/tool/cors_proxy_worker.js';

  static const intro =
      'A public proxy would be open to abuse, so there is none: you run your own for free on Cloudflare Workers. '
      'Only your token opens it, and only PostPilot\'s page may use it.';

  static const steps = [
    'Create a free Cloudflare account (cloudflare.com) and install Node.js.',
    'Press "Generate a token" above and keep it ready: wrangler asks for it in the last command.',
    'Run the commands below, one by one.',
    'wrangler prints your Worker\'s address (https://$workerName.<your-name>.workers.dev). Paste it as the Proxy URL above, '
        'paste the token, switch the proxy on and press Test connection.',
  ];

  /// The commands, for the page at [pageOrigin] (null or loopback: the hosted app, which the Worker allows by default).
  static String commands({String? pageOrigin}) {
    final custom = pageOrigin != null && !CorsProxyOrigins.isLoopback(pageOrigin) && pageOrigin != hostedOrigin;
    return [
      'npm install -g wrangler',
      'wrangler login',
      'mkdir $workerName',
      'cd $workerName',
      '# PowerShell: curl.exe',
      'curl -L -o cors_proxy_worker.js $workerSourceUrl',
      'wrangler deploy cors_proxy_worker.js --name $workerName --compatibility-date 2025-01-01${custom ? ' --var ALLOWED_ORIGINS:$pageOrigin' : ''}',
      'wrangler secret put POSTPILOT_TOKEN --name $workerName',
    ].join('\n');
  }
}
