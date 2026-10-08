import 'package:flutter/foundation.dart' show compute;
import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../traffic_recorder/domain/usecases/create_collection_from_recording_usecase.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../entities/imported_collection.dart';
import '../../../request_builder/domain/services/importers/upload_path_note.dart';
import '../services/har_cleanup.dart';
import '../services/har_parser.dart';
import '../services/imported_collection_writer.dart';

/// A HAR importer that can also clean the recording up before it makes a collection of it.
abstract interface class CleanableHarImporter {
  Future<ImportSummary> importCleaned(String text);
}

/// Turns a HAR recording into one new collection holding a request per
/// recorded call; or, as "Clean up" (see [importCleaned]), into the clean
/// collection the traffic recorder makes of an app's calls.
final class ImportHarUseCase implements UseCase<ImportSummary, String>, CleanableHarImporter {
  final ImportedCollectionWriter _writer;

  /// Writes the clean collection with its environment and saved examples; without it only the plain import is available.
  final CreateCollectionFromRecordingUseCase? _recorded;

  const ImportHarUseCase(this._writer, {this._recorded});

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

  /// The recording as a clean collection: static files, analytics and preflights dropped, repeated calls merged into one request
  /// each (ids in the path become variables), requests in folders by their first path segment, credentials made secret
  /// variables of a new environment that is left empty for the person to fill in, and the answers kept as examples. See
  /// [HarCleanup]. Calls to hosts other than the busiest one are left out.
  @override
  Future<ImportSummary> importCleaned(String text) async {
    final recorded = _recorded;
    if (recorded == null) throw const ImportException('the clean-up is not available in this build.');
    final cleanup = await compute(HarCleanup.build, text);
    if (cleanup.plan.isEmpty) {
      throw const ImportException(
        'the clean-up left no call of an API: everything in the recording was static files, analytics, preflights or calls that got no answer. '
        'Untick "Clean up" to import every call as it was recorded.',
      );
    }
    final created = await recorded(cleanup.plan);
    return ImportSummary(
      format: ImportFormat.har,
      collectionIds: [created.collectionId],
      collectionName: created.collectionName,
      folders: created.folders,
      requests: created.requests,
      environments: created.environmentId == null ? 0 : 1,
      environmentName: created.environmentName,
      skipped: cleanup.skipped,
      // The plan's own notes (a body that was left out) come back in the created result, after the clean-up's.
      notes: [...cleanup.notes, ...created.notes],
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
