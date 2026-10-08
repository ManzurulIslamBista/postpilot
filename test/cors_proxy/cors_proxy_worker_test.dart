// Runs the Node test of the Cloudflare Worker (tool/cors_proxy_worker.js) as part of the Dart suite, and keeps the deploy steps
// shown in the app and in the README in step with the commands the Worker file documents.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/cors_proxy/domain/cors_proxy_worker_guide.dart';

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test(
    'the Worker behaves like the Dart proxy: token, origin allow-list, forwarding, preflight, cookies, redirects',
    () async {
      final result = await Process.run('node', ['--test', 'test/cors_proxy/cors_proxy_worker.test.mjs']);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('# fail 0'));
    },
    skip: _hasNode() ? false : 'Node.js is not installed',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  group('deploy steps', () {
    test('the commands in the app are the ones the Worker file and the README give', () {
      final commands = CorsProxyWorkerGuide.commands();
      final worker = File('tool/cors_proxy_worker.js').readAsStringSync();
      final readme = File('README.md').readAsStringSync();

      for (final line in commands.split('\n').where((l) => !l.startsWith('#'))) {
        expect(readme, contains(line), reason: 'README is missing: $line');
      }
      expect(worker, contains('wrangler deploy cors_proxy_worker.js --name ${CorsProxyWorkerGuide.workerName} --compatibility-date 2025-01-01'));
      expect(worker, contains('wrangler secret put POSTPILOT_TOKEN --name ${CorsProxyWorkerGuide.workerName}'));
      expect(worker, contains(CorsProxyWorkerGuide.hostedOrigin), reason: 'the Worker allows the hosted app by default');
    });

    test('a page hosted elsewhere is allowed with a variable; the hosted app and localhost need none', () {
      expect(CorsProxyWorkerGuide.commands(), isNot(contains('ALLOWED_ORIGINS')));
      expect(CorsProxyWorkerGuide.commands(pageOrigin: 'http://localhost:5000'), isNot(contains('ALLOWED_ORIGINS')));
      expect(CorsProxyWorkerGuide.commands(pageOrigin: CorsProxyWorkerGuide.hostedOrigin), isNot(contains('ALLOWED_ORIGINS')));
      expect(
        CorsProxyWorkerGuide.commands(pageOrigin: 'https://tools.example.com'),
        contains('--var ALLOWED_ORIGINS:https://tools.example.com'),
      );
    });
  });
}
