import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/request_scripts_dao.dart';
import '../../domain/entities/request_scripts_entity.dart';
import '../../domain/repositories/request_scripts_repository.dart';

final class RequestScriptsRepositoryImpl implements RequestScriptsRepository {
  final RequestScriptsDao _dao;
  const RequestScriptsRepositoryImpl(this._dao);

  @override
  Future<RequestScriptsEntity?> get(int requestId) async {
    final row = await _dao.findByRequest(requestId);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> save(RequestScriptsEntity scripts) => _dao.upsert(
        RequestScriptsCompanion.insert(
          requestId: Value(scripts.requestId),
          assertionsJson: Value(scripts.assertionsJson),
          extractorsJson: Value(scripts.extractorsJson),
        ),
      );

  @override
  Stream<RequestScriptsEntity?> watch(int requestId) =>
      _dao.watchByRequest(requestId).map((r) => r == null ? null : _toEntity(r));

  RequestScriptsEntity _toEntity(RequestScript r) => RequestScriptsEntity(
        requestId: r.requestId,
        assertionsJson: r.assertionsJson,
        extractorsJson: r.extractorsJson,
      );
}
