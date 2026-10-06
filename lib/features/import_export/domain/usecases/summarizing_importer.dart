import '../entities/import_summary.dart';

/// An importer that can say what it imported and what it left out, not only
/// which collection it made. `ImportAnyUseCase` prefers it over reading the
/// result back from the database, so its notes reach the import dialog.
abstract interface class SummarizingImporter {
  Future<ImportSummary> importWithSummary(String text);
}
