import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_detector.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _Environments implements EnvironmentRepository {
  final EnvironmentEntity? active;
  _Environments(this.active);

  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.value(active);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

EnvironmentEntity _env(String name) => EnvironmentEntity(id: 1, name: name, isActive: true);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ProductionDetector', () {
    test('recognises production by name', () {
      for (final name in ['Production', 'prod', 'Prod (EU)', 'live', 'acme-prod', 'acme_PRD', 'ProdEU']) {
        expect(ProductionDetector.isProduction(name), isTrue, reason: name);
      }
      for (final name in ['Staging', 'Development', 'producer', 'products', 'delivery', 'No Environment']) {
        expect(ProductionDetector.isProduction(name), isFalse, reason: name);
      }
    });

    test('extra words extend it', () {
      expect(ProductionDetector.isProduction('eu-west'), isFalse);
      expect(ProductionDetector.isProduction('eu-west', extraWords: ['EU-West']), isFalse, reason: 'a hyphenated name is split into words, so the extra word must be one of them');
      expect(ProductionDetector.isProduction('customer-a', extraWords: ['customer']), isTrue);
    });

    test('only data-changing methods count', () {
      expect(ProductionDetector.changesData(HttpMethod.get), isFalse);
      expect(ProductionDetector.changesData(HttpMethod.head), isFalse);
      expect(ProductionDetector.changesData(HttpMethod.options), isFalse);
      for (final m in [HttpMethod.post, HttpMethod.put, HttpMethod.patch, HttpMethod.delete]) {
        expect(ProductionDetector.changesData(m), isTrue);
      }
    });
  });

  group('ProductionGuard', () {
    test('warns for a write in production, never for a read or a safe environment', () async {
      final prefs = SafetyPrefs();
      final prod = ProductionGuard(_Environments(_env('Production')), prefs);
      final warning = await prod.checkSend(HttpMethod.delete, 'Delete user');
      expect(warning, isNotNull);
      expect(warning!.environmentName, 'Production');
      expect(warning.description, contains('DELETE'));
      expect(await prod.checkSend(HttpMethod.get, 'List users'), isNull);
      expect(await ProductionGuard(_Environments(_env('Staging')), prefs).checkSend(HttpMethod.post, 'x'), isNull);
      expect(await ProductionGuard(_Environments(null), prefs).checkSend(HttpMethod.post, 'x'), isNull);
    });

    test('can be switched off and silenced for the session', () async {
      final prefs = SafetyPrefs();
      final guard = ProductionGuard(_Environments(_env('Production')), prefs);
      guard.silenceForSession('Production');
      expect(await guard.checkSend(HttpMethod.post, 'x'), isNull);

      final other = SafetyPrefs();
      await other.setConfirmProductionWrites(false);
      expect(await ProductionGuard(_Environments(_env('Production')), other).checkSend(HttpMethod.post, 'x'), isNull);
    });

    test('a run warns once with the number of writes', () async {
      final guard = ProductionGuard(_Environments(_env('prod')), SafetyPrefs());
      final w = await guard.checkRun(3, 'Orders');
      expect(w!.description, contains('3 data-changing requests'));
      expect(await guard.checkRun(0, 'Orders'), isNull);
    });

    test('preferences persist', () async {
      final a = SafetyPrefs();
      await a.setConfirmProductionWrites(false);
      await a.setKeepSecretsLocal(false);
      await a.setExtraWords(['eu', ' ', 'us']);
      final b = SafetyPrefs();
      await b.load();
      expect(b.confirmProductionWrites, isFalse);
      expect(b.keepSecretsLocal, isFalse);
      expect(b.extraWords, ['eu', 'us']);
    });
  });
}
