import 'package:flutter/foundation.dart' show compute;
import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../entities/imported_collection.dart';
import '../../../request_builder/domain/services/importers/upload_path_note.dart';
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
      notes: _notesOf(parsed),
    );
  }

  /// A HAR file names the files a form uploaded but not where they were, so each one has to be chosen again.
  List<String> _notesOf(ParsedHar parsed) {
    final bodies = [for (final request in parsed.requests) request.body];
    final files = bodies.fold<int>(0, (total, body) => total + body.formFields.where((f) => f.isFile).length);
    return [
      if (files == 1)
        '1 file field was imported with only the name of its file: a HAR recording does not say where the file was. '
            'Choose the file again on the Body tab.',
      if (files > 1)
        '$files file fields were imported with only the names of their files: a HAR recording does not say where a file was. '
            'Choose each file again on the Body tab.',
      ?UploadPathNote.of(UploadPathNote.machineSpecificIn(bodies)),
    ];
  }
}
