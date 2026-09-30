import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/response_examples_dao.dart';
import '../../domain/entities/response_example_entity.dart';
import '../../domain/repositories/response_example_repository.dart';

final class ResponseExampleRepositoryImpl implements ResponseExampleRepository {
  final ResponseExamplesDao _dao;
  const ResponseExampleRepositoryImpl(this._dao);

  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => _dao.watchByRequest(requestId).map(
        (rows) => rows
            .map((r) => ResponseExampleEntity(
                  id: r.id,
                  requestId: r.requestId,
                  name: r.name,
                  statusCode: r.statusCode,
                  headers: (jsonDecode(r.headersJson) as Map<String, dynamic>).cast<String, String>(),
                  body: r.body,
                  savedAt: r.savedAt,
                ))
            .toList(),
      );

  @override
  Future<int> add(ResponseExampleEntity example) => _dao.add(
        ResponseExamplesCompanion.insert(
          requestId: example.requestId,
          name: example.name,
          statusCode: example.statusCode,
          headersJson: Value(jsonEncode(example.headers)),
          body: Value(example.body),
          savedAt: Value(example.savedAt),
        ),
      );

  @override
  Future<void> delete(int id) => _dao.deleteExample(id);
}
