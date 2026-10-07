import 'package:flutter/foundation.dart';
import '../../../dart_codegen/domain/entities/generated_file.dart';
import '../../../dart_codegen/domain/services/dart_model_generator.dart' show DartModelStyle;
import '../../../dart_codegen/domain/services/state_layer.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/services/odoo_client_generator.dart';
import 'odoo_studio_view_model.dart';

/// Backs the "Flutter client" tab: which models to generate for, the options, and the generation itself. The models and
/// their fields come from the live server through the Studio's schema service (or from the model being explored, which
/// may have been pasted from a `fields_get` response), so nothing here talks to Odoo on its own.
final class OdooClientGenViewModel with ChangeNotifier {
  final OdooStudioViewModel studio;

  OdooClientGenViewModel(this.studio);

  /// The models to generate for, in the order they were ticked.
  final Set<String> selected = {};
  String search = '';
  bool includeRelated = false;
  bool includeJsonRpc = false;
  bool includeComputed = false;

  /// Use the fields ticked in the Explorer for the explored model instead of every stored field.
  bool useExplorerFields = false;
  DartModelStyle modelStyle = DartModelStyle.plain;
  StateLayerStyle stateLayer = StateLayerStyle.none;
  String folder = 'lib/odoo';

  bool isBusy = false;
  String? error;
  List<GeneratedFile> files = const [];
  List<String> notes = const [];

  /// Most rows the model list shows at once; the filter narrows it.
  static const maxVisible = 200;

  /// The models matching [search] by technical name or label.
  List<String> get visibleModels {
    final q = search.trim().toLowerCase();
    final all = studio.modelNames;
    final found = q.isEmpty ? all : all.where((m) => m.toLowerCase().contains(q) || (studio.modelLabels[m] ?? '').toLowerCase().contains(q));
    return found.take(maxVisible).toList();
  }

  void setSearch(String text) {
    search = text;
    notifyListeners();
  }

  void toggle(String model, bool on) {
    on ? selected.add(model) : selected.remove(model);
    notifyListeners();
  }

  /// Ticks the model the Explorer has open.
  void addExplored() {
    final explored = studio.info;
    if (explored == null) return;
    selected.add(explored.model);
    notifyListeners();
  }

  void update({
    bool? related,
    bool? jsonRpc,
    bool? computed,
    bool? explorerFields,
    DartModelStyle? style,
    StateLayerStyle? state,
    String? folder,
  }) {
    includeRelated = related ?? includeRelated;
    includeJsonRpc = jsonRpc ?? includeJsonRpc;
    includeComputed = computed ?? includeComputed;
    useExplorerFields = explorerFields ?? useExplorerFields;
    modelStyle = style ?? modelStyle;
    stateLayer = state ?? stateLayer;
    this.folder = folder ?? this.folder;
    notifyListeners();
  }

  Future<void> generate() async {
    if (isBusy) return;
    if (selected.isEmpty) {
      error = 'Tick at least one model first. Press "Load models" to list the models of the server.';
      notifyListeners();
      return;
    }
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      await _generate();
    } catch (e) {
      files = const [];
      notes = const [];
      error = "Couldn't generate the client: $e";
    }
    isBusy = false;
    notifyListeners();
  }

  Future<void> _generate() async {
    final connection = studio.connection;
    final connectionProblem = connection.missing;
    final explored = studio.info;
    final failures = <String>[];
    final extraNotes = <String>[];

    /// The model's fields: the explored one as it is, any other from the server (remembered per session).
    Future<OdooModelInfo?> read(String model, {required bool required}) async {
      if (explored != null && explored.model == model) return explored;
      if (connectionProblem != null) {
        if (required) failures.add('$model: $connectionProblem Connect first, or open the model in the Explorer.');
        return null;
      }
      final found = await studio.schema.fields(connection, model);
      if (found.ok) return found.value;
      if (required) {
        failures.add('$model: ${found.error}');
      } else {
        extraNotes.add('The related model $model was not generated: ${found.error}');
      }
      return null;
    }

    Set<String>? fieldsOf(String model) =>
        useExplorerFields && explored != null && explored.model == model && studio.chosenFields.isNotEmpty ? studio.chosenFields.toSet() : null;

    final infos = <OdooModelInfo>[];
    for (final model in selected) {
      final info = await read(model, required: true);
      if (info != null) infos.add(info);
    }
    if (failures.isNotEmpty) {
      files = const [];
      notes = const [];
      error = failures.join('\n');
      return;
    }
    if (includeRelated) {
      final have = {for (final i in infos) i.model};
      final wanted = <String>{
        for (final i in infos)
          ...OdooClientGenerator.relatedModels(i, fieldNames: fieldsOf(i.model), includeComputed: includeComputed),
      }..removeAll(have);
      for (final model in wanted) {
        final info = await read(model, required: false);
        if (info != null) infos.add(info);
      }
    }
    final result = const OdooClientGenerator().generate(
      infos,
      options: OdooClientOptions(
        folder: folder.trim().isEmpty ? 'lib/odoo' : folder.trim(),
        modelStyle: modelStyle,
        includeJsonRpc: includeJsonRpc,
        stateLayer: stateLayer,
        includeComputed: includeComputed,
        fieldsByModel: {for (final i in infos) i.model: ?fieldsOf(i.model)},
      ),
    );
    files = result.files;
    notes = [...extraNotes, ...result.notes];
  }
}
