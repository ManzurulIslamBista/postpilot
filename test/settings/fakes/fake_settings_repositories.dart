import 'dart:async';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/settings/domain/repositories/request_settings_repository.dart';
import 'package:postpilot/features/settings/domain/repositories/settings_repository.dart';

final class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository([AppSettings initial = const AppSettings()]) : _current = initial;

  AppSettings _current;
  final StreamController<AppSettings> _changes = StreamController<AppSettings>.broadcast();

  /// Every value passed to [save], in order.
  final List<AppSettings> saved = [];
  int resets = 0;

  /// Thrown by [save] and [reset] while set.
  Object? failWith;

  @override
  AppSettings get current => _current;

  @override
  Future<void> load() async {}

  @override
  Stream<AppSettings> watch() => Stream.multi((controller) {
        controller.add(_current);
        final subscription = _changes.stream.listen(controller.add);
        controller.onCancel = subscription.cancel;
      }, isBroadcast: true);

  @override
  Future<void> save(AppSettings settings) async {
    final failure = failWith;
    if (failure != null) throw failure;
    _current = settings;
    saved.add(settings);
    _changes.add(settings);
  }

  @override
  Future<void> reset() async {
    final failure = failWith;
    if (failure != null) throw failure;
    resets++;
    _current = const AppSettings();
    _changes.add(_current);
  }

  /// A change the view model did not make itself, such as a restore.
  void changeElsewhere(AppSettings settings) {
    _current = settings;
    _changes.add(settings);
  }
}

final class FakeRequestSettingsRepository implements RequestSettingsRepository {
  final Map<int, RequestSettings> stored = {};

  /// Every call to [save], in order.
  final List<({int requestId, RequestSettings settings})> saves = [];

  /// Held back until completed, for the request ids listed.
  final Map<int, Completer<RequestSettings>> gates = {};

  Object? saveFailure;
  Object? getFailure;

  @override
  Future<RequestSettings> get(int requestId) {
    final failure = getFailure;
    if (failure != null) return Future.error(failure);
    final gate = gates[requestId];
    if (gate != null) return gate.future;
    return Future.value(stored[requestId] ?? RequestSettings.none);
  }

  @override
  Stream<RequestSettings> watch(int requestId) => Stream.value(stored[requestId] ?? RequestSettings.none);

  @override
  Future<void> save(int requestId, RequestSettings settings) async {
    final failure = saveFailure;
    if (failure != null) throw failure;
    saves.add((requestId: requestId, settings: settings));
    stored[requestId] = settings;
  }

  @override
  Future<void> delete(int requestId) async => stored.remove(requestId);
}
