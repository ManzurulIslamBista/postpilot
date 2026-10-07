import 'package:flutter/foundation.dart';
import '../../domain/entities/generated_file.dart';
import '../../domain/repositories/model_snapshot_store.dart';
import '../../domain/services/api_layer_generator.dart';
import '../../domain/services/dart_model_generator.dart';
import '../../domain/services/model_schema_diff.dart';
import '../../domain/services/state_layer.dart';
import '../../domain/usecases/build_api_layer_usecase.dart';

/// Backs the "Collection to API layer" tab: remembers the options and runs the
/// generation, which reads the collection, so it is asynchronous. With a snapshot
/// store it also compares the generated DTO classes with the version remembered for
/// the collection, so a regeneration starts with what changed.
final class ApiLayerViewModel with ChangeNotifier {
  final BuildApiLayerUseCase _build;
  final ModelSnapshotStore? _snapshots;

  ApiLayerViewModel(this._build, [this._snapshots]);

  int? collectionId;
  String packageName = 'app';
  DartModelStyle modelStyle = DartModelStyle.plain;
  bool domainLayer = true;
  bool allNullable = false;
  StateLayerStyle stateLayer = StateLayerStyle.none;

  bool isBusy = false;
  String? error;
  List<GeneratedFile> files = const [];
  List<String> notes = const [];

  /// Whether a version was remembered for the collection the files were generated from.
  bool hasBaseline = false;

  /// What changed in the DTO classes since that version; null without one.
  SchemaDiff? diff;

  SchemaSnapshot? _current;
  int? _generatedFor;

  /// Whether there are generated classes to remember and somewhere to keep them.
  bool get canRemember => _snapshots != null && _current != null && !_current!.isEmpty;

  void update({int? collection, String? package, DartModelStyle? style, bool? domain, bool? nullable, StateLayerStyle? state}) {
    if (collection != null) collectionId = collection;
    if (package != null) packageName = package;
    if (style != null) modelStyle = style;
    if (domain != null) domainLayer = domain;
    if (nullable != null) allNullable = nullable;
    if (state != null) stateLayer = state;
    notifyListeners();
  }

  Future<void> generate() async {
    final id = collectionId;
    if (id == null || isBusy) return;
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      final result = await _build(
        id,
        ApiLayerOptions(
          packageName: packageName.trim().isEmpty ? 'app' : packageName.trim(),
          modelStyle: modelStyle,
          domainLayer: domainLayer,
          allNullable: allNullable,
          stateLayer: stateLayer,
        ),
      );
      files = result.files;
      notes = result.notes;
      _current = SchemaSnapshot.ofApiLayer(result);
      _generatedFor = id;
      final baseline = await _snapshots?.load(ModelSnapshotStore.collectionSource(id));
      hasBaseline = baseline != null;
      diff = baseline == null ? null : SchemaDiffer.diff(baseline, _current!);
    } catch (e) {
      files = const [];
      notes = const [];
      _current = null;
      hasBaseline = false;
      diff = null;
      error = "Couldn't read the collection: $e";
    }
    isBusy = false;
    notifyListeners();
  }

  /// Keeps the classes that were just generated as the version the next generation is compared with. Called after the
  /// files were written to a folder, and by the "Remember this version" button for code that was copied instead.
  Future<void> rememberCurrent() async {
    final snapshot = _current;
    final id = _generatedFor;
    final store = _snapshots;
    if (snapshot == null || id == null || store == null) return;
    try {
      await store.save(ModelSnapshotStore.collectionSource(id), snapshot);
    } catch (e) {
      error = "Couldn't remember this version: $e";
      notifyListeners();
      return;
    }
    hasBaseline = true;
    diff = const SchemaDiff([]);
    notifyListeners();
  }
}
