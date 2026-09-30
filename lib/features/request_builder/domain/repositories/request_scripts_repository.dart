import '../entities/request_scripts_entity.dart';

abstract interface class RequestScriptsRepository {
  /// `null` when the request has no scripts saved yet.
  Future<RequestScriptsEntity?> get(int requestId);

  /// Inserts or replaces the single row for [scripts.requestId].
  Future<void> save(RequestScriptsEntity scripts);
  Stream<RequestScriptsEntity?> watch(int requestId);
}
