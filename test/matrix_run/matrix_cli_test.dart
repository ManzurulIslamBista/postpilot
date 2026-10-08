// `postpilot run workspace.json --matrix Dev,Staging,Production`: the options are parsed and checked before anything is
// sent, every environment is run on its own, the grid is printed in the report asked for, `--fail-on-diff` sets the exit
// code, and the production lock refuses a whole matrix up front.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/matrix_run/cli/matrix_command.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

BackupRequest _req(String name, String url, {HttpMethod method = HttpMethod.get, RequestBody body = RequestBody.empty}) => BackupRequest(
      request: ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: null,
        name: name,
        method: method,
        url: url,
        headers: const [],
        queryParams: const [],
        body: body,
        auth: const RequestAuth(type: AuthType.inherit),
      ),
    );

EnvironmentVariableEntity _var(String key, String value) => EnvironmentVariableEntity(id: 0, environmentId: 0, key: key, value: value, isSecret: false, enabled: true);

String _shop({List<BackupRequest>? requests}) => BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: [
        BackupEnvironment(name: 'Dev', variables: [_var('baseUrl', 'https://dev.shop.test'), _var('token', 'tok-secret-dev')]),
        BackupEnvironment(name: 'Staging', variables: [_var('baseUrl', 'https://staging.shop.test'), _var('token', 'tok-secret-staging')]),
        BackupEnvironment(name: 'Production', variables: [_var('baseUrl', 'https://api.shop.test'), _var('token', 'tok-secret-prod')]),
      ],
      collections: [
        BackupCollection(
          name: 'Shop',
          auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
          requests: requests ??
              [
                _req('List orders', '{{baseUrl}}/orders'),
                _req('Get me', '{{baseUrl}}/me'),
                _req('Create order', '{{baseUrl}}/orders', method: HttpMethod.post, body: const RequestBody(type: BodyType.raw, rawText: '{"x":1}')),
                _req('Delete order', '{{baseUrl}}/orders/1', method: HttpMethod.delete),
              ],
        ),
      ],
    ));

/// Dev and Staging answer alike except for the ids and dates that change on every call; Production denies `/me`.
final class _Fake {
  final calls = <CliRequest>[];
  bool offline = false;

  Future<CliResponse> call(CliRequest r) async {
    calls.add(r);
    if (offline) throw 'Connection refused';
    final uri = Uri.parse(r.url);
    final n = calls.length;
    final denied = uri.host == 'api.shop.test' && uri.path == '/me';
    final body = denied
        ? '{"error":"forbidden"}'
        : uri.path == '/me'
            ? '{"name":"Ann","id":$n}'
            : '{"items":[1],"id":$n,"createdAt":"2026-10-0${n % 9 + 1}T10:00:00Z"}';
    return CliResponse(
      statusCode: denied ? 403 : 200,
      statusMessage: denied ? 'Forbidden' : 'OK',
      headers: const {'content-type': 'application/json'},
      bodyBytes: utf8.encode(body),
      duration: Duration(milliseconds: 10 + n),
    );
  }

  List<String> get urls => [for (final c in calls) '${c.method} ${c.url}'];
}

(IOSink, StringBuffer) _capture() {
  final controller = StreamController<List<int>>();
  final buffer = StringBuffer();
  controller.stream.transform(utf8.decoder).listen(buffer.write);
  return (IOSink(controller.sink), buffer);
}

void main() {
  late Directory dir;
  late File workspace;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pp_cli_matrix');
    workspace = File(p.join(dir.path, 'workspace.json'))..writeAsStringSync(_shop());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<({int code, String out, String err, _Fake fake})> cli(List<String> args, {String? json, bool offline = false}) async {
    if (json != null) workspace.writeAsStringSync(json);
    final fake = _Fake()..offline = offline;
    final (out, outBuf) = _capture();
    final (err, errBuf) = _capture();
    final code = await runCli(['run', workspace.path, ...args], sender: fake.call, out: out, err: err, environment: const {});
    await out.flush();
    await err.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (code: code, out: outBuf.toString(), err: errBuf.toString(), fake: fake);
  }

  group('the option', () {
    test('environments are split on commas; blanks and repeats are dropped, the order is kept', () {
      expect(MatrixCommand.parseEnvironments(' Dev, Staging ,,Dev,Production '), ['Dev', 'Staging', 'Production']);
      expect(MatrixCommand.parseEnvironments(''), isEmpty);
      expect(MatrixCommand.parseEnvironments('Dev'), ['Dev']);
    });

    test('--matrix=a,b is read like --matrix a,b', () async {
      final r = await cli(['--matrix=Dev,Staging', '--collection', 'Shop']);
      expect(r.code, 0, reason: r.err);
      expect(r.fake.calls, hasLength(4));
    });

    test('one environment is not a comparison', () async {
      final r = await cli(['--matrix', 'Dev']);
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty);
      expect(r.err, contains('--matrix needs two or more environments'));
    });

    test('an environment the workspace does not have is named, with the ones it has', () async {
      final r = await cli(['--matrix', 'Dev,Qa']);
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty);
      expect(r.err, contains('No environment named "Qa" in the workspace (it has Dev, Staging, Production)'));
    });

    test('--matrix picks the environments itself: --env, --iterations and --data are refused', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--env', 'Dev', '--iterations', '2']);
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty);
      expect(r.err, contains('cannot be combined with --env, --iterations'));
    });

    test('--fail-on-diff and --include-writes mean nothing without --matrix', () async {
      for (final flag in ['--fail-on-diff', '--include-writes']) {
        final r = await cli([flag]);
        expect(r.code, 2, reason: flag);
        expect(r.fake.calls, isEmpty);
        expect(r.err, contains('belong to --matrix'));
      }
    });

    test('only console, markdown and csv are reports of a matrix', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--report', 'junit']);
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty);
      expect(r.err, contains('--report junit is not available with --matrix'));
    });

    test('a --request that matches nothing stops the run before anything is sent', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--request', 'Nope']);
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty);
      expect(r.err, contains('No request matches "Nope"'));
    });

    test('the help text documents the option', () async {
      final (out, buf) = _capture();
      await runCli(['--help'], out: out, environment: const {});
      await out.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(buf.toString(), allOf(contains('--matrix <a,b,c>'), contains('--include-writes'), contains('--fail-on-diff')));
    });
  });

  group('a run', () {
    test('sends only the reads, once per environment, each with its own token, one environment after the other', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--collection', 'Shop']);
      expect(r.code, 0, reason: r.err);
      expect(r.fake.urls, [
        'GET https://dev.shop.test/orders',
        'GET https://dev.shop.test/me',
        'GET https://staging.shop.test/orders',
        'GET https://staging.shop.test/me',
      ]);
      expect(r.fake.calls.map((c) => c.headers['Authorization']), [
        'Bearer tok-secret-dev',
        'Bearer tok-secret-dev',
        'Bearer tok-secret-staging',
        'Bearer tok-secret-staging',
      ]);
    });

    test('prints a block per request; ids and dates that change on every call are not a difference', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--collection', 'Shop']);
      expect(r.out, startsWith('Shop matrix run (structure and values; the first column is the reference)\n\nShop / GET List orders\n'));
      expect(r.out, contains(RegExp(r'  Dev      200 · 11 ms · \{3 keys\} #[0-9a-f]{6}\n')));
      expect(r.out, contains(RegExp(r'  Staging  200 · 13 ms · \{3 keys\} #[0-9a-f]{6}\n')));
      expect(r.out, contains('No request differs between the columns.'));
      expect(r.out, isNot(contains('differs:')));
    });

    test('the same fingerprint in both environments: ids and dates changed, the rest did not', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--collection', 'Shop']);
      final prints = RegExp(r'\{3 keys\} #([0-9a-f]{6})').allMatches(r.out).map((m) => m[1]).toList();
      expect(prints, hasLength(2));
      expect(prints.first, prints.last);
    });

    test('a difference is printed against the first environment; --fail-on-diff makes it exit 1', () async {
      final r = await cli(['--matrix', 'Dev,Staging,Production', '--collection', 'Shop', '--fail-on-diff']);
      expect(r.code, 1);
      expect(r.out, contains('Shop / GET Get me\n'));
      expect(r.out, contains('   <- differs: status 200 vs 403, body: 3 fields differ'));
      expect(r.out, contains('1 of 2 requests differ.'));
      expect(r.err, contains('--fail-on-diff: 1 of 2 requests differ between Dev, Staging, Production.'));
      expect(r.fake.urls.where((u) => u.contains('api.shop.test')), ['GET https://api.shop.test/orders', 'GET https://api.shop.test/me'],
          reason: 'reads reach Production: the lock only stops writes');
    });

    test('without --fail-on-diff a difference is reported but the exit code stays 0', () async {
      final r = await cli(['--matrix', 'Dev,Production', '--collection', 'Shop']);
      expect(r.code, 0, reason: r.err);
      expect(r.out, contains('1 of 2 requests differ.'));
    });

    test('with --fail-on-diff and nothing different the exit code is 0', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--collection', 'Shop', '--fail-on-diff']);
      expect(r.code, 0, reason: r.err);
    });

    test('--fail-on-diff does not pass a matrix in which nothing got an answer', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--collection', 'Shop', '--fail-on-diff'], offline: true);
      expect(r.code, 1);
      expect(r.err, contains('nothing was compared'));
      expect(r.out, contains('ERR Connection refused'));
    });

    test('no body, token or header value ever reaches the output', () async {
      final r = await cli(['--matrix', 'Dev,Production', '--collection', 'Shop']);
      for (final secret in ['tok-secret-dev', 'tok-secret-prod', 'forbidden', '"items"', 'Bearer']) {
        expect(r.out, isNot(contains(secret)), reason: secret);
        expect(r.err, isNot(contains(secret)), reason: secret);
      }
    });

    test('requests with the same name keep their own rows', () async {
      final r = await cli(
        ['--matrix', 'Dev,Staging', '--collection', 'Shop'],
        json: _shop(requests: [_req('Orders', '{{baseUrl}}/orders'), _req('Orders', '{{baseUrl}}/me')]),
      );
      expect(r.code, 0, reason: r.err);
      expect('Shop / GET Orders\n'.allMatches(r.out).length, 2);
      expect(r.fake.calls, hasLength(4));
    });
  });

  group('the production lock', () {
    test('reads to Production are not refused, writes are left out unless asked for', () async {
      final r = await cli(['--matrix', 'Staging,Production', '--collection', 'Shop']);
      expect(r.code, 0, reason: r.err);
      expect(r.fake.urls.every((u) => u.startsWith('GET ')), isTrue);
    });

    test('--include-writes with a production environment is refused for the whole matrix, before anything is sent', () async {
      final r = await cli(['--matrix', 'Dev,Staging,Production', '--collection', 'Shop', '--include-writes']);
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty, reason: 'Dev and Staging are not sent to either');
      expect(r.err, contains('Production lock: 2 selected requests would change data in production, so nothing was sent.'));
      expect(r.err, contains('POST   Shop / Create order'));
      expect(r.err, contains('DELETE Shop / Delete order (deletes data)'));
      expect(r.err, contains('--allow-production'));
    });

    test('--allow-production lets the writes go to every environment', () async {
      final r = await cli(['--matrix', 'Dev,Production', '--collection', 'Shop', '--include-writes', '--allow-production']);
      expect(r.code, 0, reason: r.err);
      expect(r.fake.calls, hasLength(8));
      expect(r.fake.urls.where((u) => u.startsWith('DELETE')), ['DELETE https://dev.shop.test/orders/1', 'DELETE https://api.shop.test/orders/1']);
    });

    test('--include-writes between environments that are not production sends the writes', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--collection', 'Shop', '--include-writes']);
      expect(r.code, 0, reason: r.err);
      expect(r.fake.calls, hasLength(8));
    });

    test('a host marked as production stops the writes under any environment name', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--collection', 'Shop', '--include-writes', '--production-host', 'staging.shop.test']);
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty);
      expect(r.err, contains('staging.shop.test is a production host'));
    });

    test('a workspace with only writes has nothing to send in a read-only matrix', () async {
      final r = await cli(
        ['--matrix', 'Dev,Staging'],
        json: _shop(requests: [_req('Create order', '{{baseUrl}}/orders', method: HttpMethod.post)]),
      );
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty);
      expect(r.err, contains('Nothing ran'));
      expect(r.err, contains('--include-writes'));
    });
  });

  group('the reports', () {
    test('markdown prints the table', () async {
      final r = await cli(['--matrix', 'Dev,Production', '--collection', 'Shop', '--report', 'markdown']);
      expect(r.out, startsWith('## Shop matrix run\n\nCompared: structure and values. Columns: Dev, Production;'));
      expect(r.out, contains('| Request | Dev | Production | Result |'));
      expect(r.out, contains('| Shop / GET Get me | 200 · '));
      expect(r.out, contains('DIFFERS: Production: status 200 vs 403, body: 3 fields differ |'));
    });

    test('csv prints one line per request', () async {
      final r = await cli(['--matrix', 'Dev,Production', '--collection', 'Shop', '--report', 'csv']);
      final lines = r.out.trim().split('\n');
      expect(lines.first, 'request,method,folder,Dev status,Dev ms,Dev body,Production status,Production ms,Production body,differs,differences,unexpected');
      expect(lines, hasLength(3));
      expect(lines[1], startsWith('List orders,GET,Shop,200,'));
      expect(lines[2], contains(',yes,'));
    });

    test('--out writes the report to a file and still prints the grid', () async {
      final target = p.join(dir.path, 'matrix.md');
      final r = await cli(['--matrix', 'Dev,Production', '--collection', 'Shop', '--report', 'markdown', '--out', target]);
      expect(r.code, 0, reason: r.err);
      expect(File(target).readAsStringSync(), startsWith('## Shop matrix run'));
      expect(r.out, contains('Shop / GET Get me\n'));
      expect(r.out, contains('Report written to $target'));
    });

    test('a report that cannot be written is said on stderr and the grid is still printed', () async {
      final r = await cli(['--matrix', 'Dev,Staging', '--collection', 'Shop', '--out', p.join(dir.path, 'missing', 'matrix.txt')]);
      expect(r.code, 0);
      expect(r.err, contains('Could not write the report'));
      expect(r.out, contains('Shop / GET List orders'));
    });
  });
}
