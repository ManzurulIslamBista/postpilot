import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/response_examples_table.dart';

part 'response_examples_dao.g.dart';

@DriftAccessor(tables: [ResponseExamples])
class ResponseExamplesDao extends DatabaseAccessor<AppDatabase> with _$ResponseExamplesDaoMixin {
  ResponseExamplesDao(super.db);

  Stream<List<ResponseExample>> watchByRequest(int requestId) =>
      (select(responseExamples)
            ..where((t) => t.requestId.equals(requestId))
            ..orderBy([(t) => OrderingTerm.desc(t.savedAt)]))
          .watch();

  Future<int> add(ResponseExamplesCompanion entry) => into(responseExamples).insert(entry);

  Future<void> deleteExample(int id) => (delete(responseExamples)..where((t) => t.id.equals(id))).go();
}
