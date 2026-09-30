import 'package:flutter/foundation.dart' show compute;
import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../entities/imported_collection.dart';
import '../services/har_parser.dart';
import '../services/imported_collection_writer.dart';

/// Turns a HAR recording into one new collection holding a request per
/// recorded call.
final class ImportHarUseCase implements UseCase<ImportSummary, String> {
  final ImportedCollectionWriter _writer;
  const ImportHarUseCase(this._writer);

  @override
  Future<ImportSummary> call(String text) async {
    final parsed = await compute(HarParser.parse, text);
    if (parsed.requests.isEmpty) throw const ImportException('the recording holds no request that can be replayed.');
    final written = await _writer.write(ImportedCollection(parsed.name, parsed.requests));
    return ImportSummary(
      format: ImportFormat.har,
      collectionIds: [written.collectionId],
      collectionName: parsed.name,
      requests: written.requests,
      skipped: parsed.skipped,
    );
  }
}
