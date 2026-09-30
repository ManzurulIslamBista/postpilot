import '../../../../core/database/daos/request_settings_dao.dart';
import '../../domain/entities/request_settings.dart';
import '../../domain/repositories/request_settings_repository.dart';

final class RequestSettingsRepositoryImpl implements RequestSettingsRepository {
  final RequestSettingsDao _dao;
  const RequestSettingsRepositoryImpl(this._dao);

  @override
  Future<RequestSettings> get(int requestId) async => RequestSettings.decode(await _dao.get(requestId));

  @override
  Stream<RequestSettings> watch(int requestId) => _dao.watch(requestId).map(RequestSettings.decode);

  @override
  Future<void> save(int requestId, RequestSettings settings) =>
      settings.isEmpty ? _dao.remove(requestId) : _dao.put(requestId, settings.encode());

  @override
  Future<void> delete(int requestId) => _dao.remove(requestId);
}
