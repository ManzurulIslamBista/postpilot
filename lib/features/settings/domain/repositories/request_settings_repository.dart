import '../entities/request_settings.dart';

abstract interface class RequestSettingsRepository {
  /// The overrides of [requestId]; [RequestSettings.none] when it has none
  /// stored or what is stored cannot be read.
  Future<RequestSettings> get(int requestId);

  Stream<RequestSettings> watch(int requestId);

  /// Stores [settings] for [requestId]; overrides that are all "use global"
  /// are not stored at all.
  Future<void> save(int requestId, RequestSettings settings);

  Future<void> delete(int requestId);
}
