import '../entities/response_example_entity.dart';

abstract interface class ResponseExampleRepository {
  /// Newest first.
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId);

  /// [example.id] is ignored; returns the new row's id.
  Future<int> add(ResponseExampleEntity example);
  Future<void> delete(int id);
}
