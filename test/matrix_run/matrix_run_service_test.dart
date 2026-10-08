// A matrix run on a real (in-memory) database with the real collection runner and a scripted server: each column is
// sent to its own environment with its own identity on top, the person's active environment is back afterwards however
// the run ends, only reads go out unless asked otherwise, and a production column asks once.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_column.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_grid.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_identity.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_run_service.dart';
import 'package:postpilot/features/matrix_run/domain/services/matrix_session_isolation.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/run_selection.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

final class _Sent {
  final String method;
  final String url;
  final String? authorization;
  const _Sent(this.method, this.url, this.authorization);

  @override
  String toString() => '$method $url [$authorization]';
}

/// Answers 403 to an empty bearer token and 200 with the host it was sent to otherwise.
final class _Server implements ApiClient {
  final sent = <_Sent>[];
  void Function(ApiRequestSpec spec)? onSend;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final auth = spec.headers['Authorization'];
    sent.add(_Sent(spec.method, spec.url, auth));
    onSend?.call(spec);
    final denied = auth == 'Bearer ';
    final body = denied ? '{"error":"forbidden"}' : '{"host":"${Uri.parse(spec.url).host}","path":"${Uri.parse(spec.url).path}","items":[1]}';
    return ApiHttpResponse(
      statusCode: denied ? 403 : 200,
      statusMessage: denied ? 'Forbidden' : 'OK',
      headers: const {'content-type': 'application/json'},
      bodyBytes: utf8.encode(body),
      duration: const Duration(milliseconds: 25),
    );
  }
}

final class _NoHistory implements HistoryRepository {
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// The real environments with a log of every switch, and a way to make one fail.
final class _SpyEnvironments implements EnvironmentRepository {
  final EnvironmentRepository inner;
  final log = <String>[];
  final failFor = <int>{};
  _SpyEnvironments(this.inner);

  @override
  Future<void> setActive(int id) async {
    log.add('set:$id');
    if (failFor.contains(id)) throw StateError('cannot switch');
    await inner.setActive(id);
  }

  @override
  Future<void> clearActive() async {
    log.add('clear');
    await inner.clearActive();
  }

  @override
  Stream<List<EnvironmentEntity>> watchAll() => inner.watchAll();
  @override
  Stream<EnvironmentEntity?> watchActive() => inner.watchActive();
  @override
  Future<int> create(String name) => inner.create(name);
  @override
  Future<void> rename(int id, String name) => inner.rename(id, name);
  @override
  Future<void> delete(int id) => inner.delete(id);
  @override
  Stream<List<EnvironmentVariableEntity>> watchVariables(int environmentId) => inner.watchVariables(environmentId);
  @override
  Future<void> upsertVariable(EnvironmentVariableEntity variable) => inner.upsertVariable(variable);
  @override
  Future<void> deleteVariable(int id) => inner.deleteVariable(id);
  @override
  Future<Map<String, String>> getActiveVariables() => inner.getActiveVariables();
}

final class _CountingIsolation implements MatrixSessionIsolation {
  int calls = 0;
  int inside = 0;

  @override
  Future<T> isolated<T>(Future<T> Function() body) async {
    calls++;
    inside++;
    try {
      return await body();
    } finally {
      inside--;
    }
  }
}

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late _Server server;
  late _SpyEnvironments spy;
  late int shop;
  late int dev;
  late int staging;
  late int production;
  late int listOrders;
  late int me;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    server = _Server();
    spy = _SpyEnvironments(repos.environmentRepository);
    shop = await repos.collectionRepository.createCollection('Shop');
    dev = await repos.environmentRepository.create('Dev');
    staging = await repos.environmentRepository.create('Staging');
    production = await repos.environmentRepository.create('Production');
    Future<void> variable(int env, String key, String value) => repos.environmentRepository.upsertVariable(
          EnvironmentVariableEntity(id: 0, environmentId: env, key: key, value: value, isSecret: false, enabled: true),
        );
    await variable(dev, 'host', 'https://dev.shop.test');
    await variable(dev, 'token', 'dev-token');
    await variable(staging, 'host', 'https://staging.shop.test');
    await variable(staging, 'token', 'staging-token');
    await variable(production, 'host', 'https://api.shop.test');
    await variable(production, 'token', 'prod-token');
    await repos.environmentRepository.setActive(staging);
    final auth = [KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}')];
    listOrders = await addRequest(repos, shop, 'List orders', url: '{{host}}/orders', headers: auth);
    me = await addRequest(repos, shop, 'Me', url: '{{host}}/me', headers: auth);
    await addRequest(repos, shop, 'Create order',
        method: HttpMethod.post, url: '{{host}}/orders', headers: auth, body: const RequestBody(type: BodyType.raw, rawText: '{"x":1}'));
    await addRequest(repos, shop, 'Delete order', method: HttpMethod.delete, url: '{{host}}/orders/1', headers: auth);
    spy.log.clear();
  });
  tearDown(() => db.close());

  Future<String?> activeName() async => (await repos.environmentRepository.watchActive().first)?.name;

  MatrixRunService service({MatrixSessionIsolation? sessions, bool guard = true}) {
    final resolver = BuildVariableResolverUseCase(
      repos.collectionVariableRepository,
      repos.environmentRepository,
      repos.globalVariableRepository,
      repos.defaultsRepository,
    );
    final send = SendRequestUseCase(server, resolver, _NoHistory(), repos.collectionAuthRepository);
    final scripts = RunRequestScriptsUseCase(repos.scriptsRepository, resolver, repos.environmentRepository, repos.globalVariableRepository);
    return MatrixRunService(
      CollectionRunnerService.withFolders(repos.requestRepository, send, scripts, repos.collectionRepository, (_) async {}),
      spy,
      guard: guard ? ProductionGuard(repos.environmentRepository, SafetyPrefs()) : null,
      sessions: sessions,
    );
  }

  MatrixRunSpec spec(List<MatrixColumn> columns, {bool readOnlyOnly = true, RunSelection selection = RunSelection.all}) =>
      MatrixRunSpec(collectionId: shop, collectionName: 'Shop', selection: selection, columns: columns, readOnlyOnly: readOnlyOnly);

  const devColumn = MatrixColumn(environment: 'Dev');
  const stagingColumn = MatrixColumn(environment: 'Staging');
  const productionColumn = MatrixColumn(environment: 'Production');

  test('three environments: each column is sent to its own host with its own token, and the active environment is back after', () async {
    final result = await service().run(spec([devColumn, stagingColumn, productionColumn]));

    expect(server.sent.map((s) => '${s.method} ${s.url} ${s.authorization}'), [
      'GET https://dev.shop.test/orders Bearer dev-token',
      'GET https://dev.shop.test/me Bearer dev-token',
      'GET https://staging.shop.test/orders Bearer staging-token',
      'GET https://staging.shop.test/me Bearer staging-token',
      'GET https://api.shop.test/orders Bearer prod-token',
      'GET https://api.shop.test/me Bearer prod-token',
    ]);
    expect(result.grid.rows.map((r) => r.title), ['GET List orders', 'GET Me']);
    final cell = result.grid.rows.first.cells;
    expect(cell.map((c) => c!.status), [200, 200, 200]);
    expect(cell.map((c) => jsonDecode(c!.body!)['host']), ['dev.shop.test', 'staging.shop.test', 'api.shop.test']);
    expect(result.cancelled, isFalse);
    expect(result.columnNotes, isEmpty);

    // Staging was active, so Dev needs a switch, Staging a switch back, Production another, and the last restores Staging.
    expect(spy.log, ['set:$dev', 'set:$staging', 'set:$production', 'set:$staging']);
    expect(await activeName(), 'Staging');
  });

  test('"No Environment" is restored too', () async {
    await repos.environmentRepository.clearActive();
    spy.log.clear();
    await service().run(spec([devColumn, productionColumn]));
    expect(spy.log, ['set:$dev', 'set:$production', 'clear']);
    expect(await activeName(), isNull);
  });

  test('columns that keep the active environment never switch it', () async {
    const admin = MatrixIdentity(id: 'a', name: 'admin', variables: {'token': 'admin-token'});
    const user = MatrixIdentity(id: 'u', name: 'user', variables: {'token': 'user-token'});
    await service().run(spec([const MatrixColumn(identity: admin), const MatrixColumn(identity: user)]));
    expect(spy.log, isEmpty);
    expect(server.sent.map((s) => s.authorization).toSet(), {'Bearer admin-token', 'Bearer user-token'});
    expect(server.sent.every((s) => s.url.startsWith('https://staging.shop.test/')), isTrue, reason: 'the active environment is Staging');
  });

  test('an identity beats the environment, and "anonymous" clears the token: the server says 403', () async {
    const admin = MatrixIdentity(id: 'a', name: 'admin', variables: {'token': 'admin-token'});
    const anonymous = MatrixIdentity(id: 'n', name: 'anonymous', variables: {'token': ''});
    final result = await service().run(spec([
      const MatrixColumn(environment: 'Dev'),
      const MatrixColumn(environment: 'Dev', identity: admin),
      const MatrixColumn(environment: 'Dev', identity: anonymous),
    ]));
    expect(server.sent.take(2).map((s) => s.authorization), ['Bearer dev-token', 'Bearer dev-token']);
    expect(server.sent.skip(2).take(2).map((s) => s.authorization), ['Bearer admin-token', 'Bearer admin-token']);
    expect(server.sent.skip(4).map((s) => s.authorization), ['Bearer ', 'Bearer ']);
    expect(result.grid.rows.first.cells.map((c) => c!.status), [200, 200, 403]);
    expect(await activeName(), 'Staging');
  });

  test('only the columns with an identity run in an isolated session', () async {
    final sessions = _CountingIsolation();
    var insideWhenSent = <int>[];
    server.onSend = (_) => insideWhenSent.add(sessions.inside);
    const admin = MatrixIdentity(id: 'a', name: 'admin', variables: {'token': 'admin-token'});
    await service(sessions: sessions).run(spec([const MatrixColumn(environment: 'Dev'), const MatrixColumn(environment: 'Dev', identity: admin)]));
    expect(sessions.calls, 1);
    expect(insideWhenSent, [0, 0, 1, 1], reason: 'the plain column is not isolated, the admin column is');
    expect(sessions.inside, 0);
  });

  test('read-only (the default) leaves the writes out and says how many', () async {
    final result = await service().run(spec([devColumn, stagingColumn]));
    expect(server.sent.map((s) => s.method).toSet(), {'GET'});
    expect(result.leftOut, 2);
    expect(result.grid.rows.map((r) => r.method), ['GET', 'GET']);
  });

  test('read-only off sends the writes too, in the collection order, once per column', () async {
    final result = await service().run(spec([devColumn, stagingColumn], readOnlyOnly: false));
    expect(server.sent.map((s) => '${s.method} ${Uri.parse(s.url).host}${Uri.parse(s.url).path}'), [
      'GET dev.shop.test/orders',
      'GET dev.shop.test/me',
      'POST dev.shop.test/orders',
      'DELETE dev.shop.test/orders/1',
      'GET staging.shop.test/orders',
      'GET staging.shop.test/me',
      'POST staging.shop.test/orders',
      'DELETE staging.shop.test/orders/1',
    ]);
    expect(result.leftOut, 0);
    expect(result.grid.rows.map((r) => r.title), ['GET List orders', 'GET Me', 'POST Create order', 'DELETE Delete order']);
  });

  test('a selection narrows the run: one request, or none left after the read-only filter', () async {
    var result = await service().run(spec([devColumn, stagingColumn], selection: RunSelection.requests([me])));
    expect(result.grid.rows.map((r) => r.key), ['r$me']);
    expect(server.sent.length, 2);

    server.sent.clear();
    spy.log.clear();
    final writeOnly = (await repos.requestRepository.watchByCollection(shop).first).firstWhere((r) => r.method == HttpMethod.post).id;
    result = await service().run(spec([devColumn, stagingColumn], selection: RunSelection.requests([writeOnly])));
    expect(result.grid.rows, isEmpty);
    expect(result.leftOut, 1);
    expect(server.sent, isEmpty);
    expect(spy.log, isEmpty, reason: 'nothing to send, so no environment is touched');
  });

  group('the production lock', () {
    test('a production column that would change data asks once, with the guard\'s own warning', () async {
      final asked = <ProductionWarning>[];
      await service().run(
        spec([devColumn, productionColumn], readOnlyOnly: false),
        confirm: (w) async {
          asked.add(w);
          return true;
        },
      );
      expect(asked.length, 1, reason: 'once for the column, not once per request');
      expect(asked.single.environmentName, 'Production');
      expect(asked.single.description, 'Running "Shop" sends 2 data-changing requests, 1 of them deletes data');
      expect(asked.single.destructive, isTrue);
      expect(server.sent.where((s) => s.url.contains('api.shop.test')).map((s) => s.method), ['GET', 'GET', 'POST', 'DELETE']);
    });

    test('declined: the column is not sent at all, says why, and the other columns still run', () async {
      final result = await service().run(spec([productionColumn, devColumn], readOnlyOnly: false), confirm: (_) async => false);
      expect(server.sent.where((s) => s.url.contains('api.shop.test')), isEmpty);
      expect(server.sent.where((s) => s.url.contains('dev.shop.test')).length, 4);
      expect(result.columnNotes[productionColumn.key], 'Not sent: the production confirmation for Production was declined.');
      expect(result.grid.rows.every((r) => r.cells[0]!.note != null && r.cells[0]!.status == null), isTrue);
      expect(result.grid.rows.every((r) => r.cells[1]!.status == 200), isTrue);
      expect(await activeName(), 'Staging');
    });

    test('with nobody to ask, a production column that would change data is declined, never sent', () async {
      await service().run(spec([productionColumn], readOnlyOnly: false));
      expect(server.sent, isEmpty);
    });

    test('read-only never asks: reads to production go out', () async {
      var asked = 0;
      final result = await service().run(spec([devColumn, productionColumn]), confirm: (_) async {
        asked++;
        return true;
      });
      expect(asked, 0);
      expect(result.grid.rows.first.cells.map((c) => c!.status), [200, 200]);
    });

    test('the guard\'s own switch is honoured: a silenced production environment is not asked about again', () async {
      final prefs = SafetyPrefs()..silenceForSession('Production');
      final resolver = BuildVariableResolverUseCase(
        repos.collectionVariableRepository,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.defaultsRepository,
      );
      final runner = CollectionRunnerService.withFolders(
        repos.requestRepository,
        SendRequestUseCase(server, resolver, _NoHistory(), repos.collectionAuthRepository),
        RunRequestScriptsUseCase(repos.scriptsRepository, resolver, repos.environmentRepository, repos.globalVariableRepository),
        repos.collectionRepository,
        (_) async {},
      );
      var asked = 0;
      // A delete is never silenced, so remove it: the POST alone can be silenced.
      for (final r in await repos.requestRepository.watchByCollection(shop).first) {
        if (r.method == HttpMethod.delete) await repos.requestRepository.deleteRequest(r.id);
      }
      await MatrixRunService(runner, spy, guard: ProductionGuard(repos.environmentRepository, prefs)).run(
        spec([productionColumn], readOnlyOnly: false),
        confirm: (_) async {
          asked++;
          return true;
        },
      );
      expect(asked, 0);
      expect(server.sent.map((s) => s.method), ['GET', 'GET', 'POST']);
    });
  });

  group('when things go wrong', () {
    test('an environment that no longer exists fails its column only', () async {
      final result = await service().run(spec([const MatrixColumn(environment: 'Gone'), devColumn]));
      expect(result.columnNotes['Gone|'], 'The environment "Gone" no longer exists.');
      expect(result.grid.rows.first.cells[0]!.note, 'The environment "Gone" no longer exists.');
      expect(result.grid.rows.first.cells[1]!.status, 200);
    });

    test('a column that cannot be switched fails alone, and the active environment is still restored', () async {
      spy.failFor.add(production);
      final result = await service().run(spec([devColumn, productionColumn, stagingColumn]));
      expect(result.columnNotes[productionColumn.key], contains('The column could not run'));
      expect(result.grid.rows.first.cells.map((c) => c!.status), [200, null, 200]);
      expect(result.grid.rows.first.cells[1]!.note, isNotNull);
      expect(await activeName(), 'Staging');
    });

    test('stopping ends the run, leaves the rest of the grid empty and puts the environment back', () async {
      final token = ApiCancelToken();
      server.onSend = (_) => token.cancel();
      final result = await service().run(spec([devColumn, stagingColumn, productionColumn]), cancelToken: token);
      expect(result.cancelled, isTrue);
      expect(server.sent.length, 1, reason: 'the request in flight was the only one sent');
      expect(result.grid.rows.first.cells.every((c) => c == null || c.status == null || c.status == 200), isTrue);
      expect(result.grid.rows.first.cells[2], isNull);
      expect(await activeName(), 'Staging');
    });

    test('a request with an undefined variable is an error cell and the rest of the column goes on', () async {
      await addRequest(repos, shop, 'Broken', url: '{{nowhere}}/x');
      final result = await service().run(spec([devColumn, stagingColumn]));
      final broken = result.grid.rows.firstWhere((r) => r.name == 'Broken');
      expect(broken.cells.map((c) => c!.error != null && c.status == null), [true, true]);
      expect(broken.cells.first!.error, contains('nowhere'));
      expect(result.grid.rows.where((r) => r.name != 'Broken').every((r) => r.cells.every((c) => c!.status == 200)), isTrue);
    });
  });

  test('progress is reported as cells arrive, with the column being run', () async {
    final seen = <String>[];
    await service().run(
      spec([devColumn, stagingColumn]),
      onProgress: (grid, notes, column) => seen.add('$column:${grid.rows.map((r) => r.cells.map((c) => c == null ? '.' : '${c.status}').join()).join(',')}'),
    );
    expect(seen.first, '0:..,..');
    expect(seen, contains('0:200.,..'));
    expect(seen, contains('1:200.,200.'));
    expect(seen.last, '1:200200,200200');
  });

  test('the answers are the matrix\'s to read: ids differ by environment but the rows line up by request', () async {
    final result = await service().run(spec([devColumn, productionColumn]));
    expect(result.grid.rowOf(MatrixRunService.rowKey(listOrders))!.name, 'List orders');
    final MatrixRow row = result.grid.rowOf(MatrixRunService.rowKey(me))!;
    expect(row.cells.map((c) => jsonDecode(c!.body!)['path']), ['/me', '/me']);
    expect(row.cells.every((c) => c!.contentType == 'application/json'), isTrue);
  });
}
