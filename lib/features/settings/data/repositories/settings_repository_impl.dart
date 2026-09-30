import 'dart:async';
import '../../../../core/database/daos/settings_dao.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

final class SettingsRepositoryImpl implements SettingsRepository {
  static const storageKey = 'app_settings';

  final SettingsDao _dao;
  final StreamController<AppSettings> _changes = StreamController<AppSettings>.broadcast();
  AppSettings _current = const AppSettings();

  SettingsRepositoryImpl(this._dao);

  @override
  AppSettings get current => _current;

  @override
  Future<void> load() async {
    try {
      _current = AppSettings.decode(await _dao.get(storageKey));
    } catch (_) {
      _current = const AppSettings();
    }
    _changes.add(_current);
  }

  @override
  Stream<AppSettings> watch() => Stream.multi((controller) {
        controller.add(_current);
        final subscription = _changes.stream.listen(controller.add);
        controller.onCancel = subscription.cancel;
      }, isBroadcast: true);

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
    _changes.add(settings);
    await _dao.put(storageKey, settings.encode());
  }

  @override
  Future<void> reset() async {
    _current = const AppSettings();
    _changes.add(_current);
    await _dao.remove(storageKey);
  }
}
