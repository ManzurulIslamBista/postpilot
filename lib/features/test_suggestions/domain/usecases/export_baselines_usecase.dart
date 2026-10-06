import '../../../import_export/domain/services/collection_loader.dart';
import '../repositories/request_baseline_repository.dart';
import '../services/baseline_file.dart';

/// Gathers every baseline of this device into a [BaselineFile], each named by the collection, folder, name and
/// method of its request (the names the command line selects requests by), for `postpilot run --baseline-file`.
final class ExportBaselinesUseCase {
  final RequestBaselineRepository _baselines;
  final CollectionLoader _loader;

  const ExportBaselinesUseCase(this._baselines, this._loader);

  Future<BaselineFile> call() async {
    final stored = await _baselines.all();
    if (stored.isEmpty) return BaselineFile.empty;
    final byRequest = {for (final s in stored) s.requestId: s};
    final entries = <BaselineFileEntry>[];
    for (final loaded in await _loader.loadAll()) {
      final folders = {for (final f in loaded.folders) f.id: f};
      String folderPath(int? id) {
        final names = <String>[];
        var current = id;
        for (var guard = 0; current != null && guard < 50; guard++) {
          final folder = folders[current];
          if (folder == null) break;
          names.insert(0, folder.name);
          current = folder.parentFolderId;
        }
        return names.join('/');
      }

      for (final request in loaded.requests) {
        final baseline = byRequest[request.id];
        if (baseline == null) continue;
        entries.add(BaselineFileEntry(
          collection: loaded.collection.name,
          folder: folderPath(request.folderId),
          name: request.name,
          method: request.method.label,
          snapshot: baseline.snapshot,
          recordedAt: baseline.recordedAt,
        ));
      }
    }
    return BaselineFile(entries);
  }
}
