import 'package:flutter/foundation.dart';
import '../../domain/entities/generated_file.dart';
import '../../domain/services/api_layer_generator.dart';
import '../../domain/services/dart_model_generator.dart';
import '../../domain/usecases/build_api_layer_usecase.dart';

/// Backs the "Collection to API layer" tab: remembers the options and runs the
/// generation, which reads the collection, so it is asynchronous.
final class ApiLayerViewModel with ChangeNotifier {
  final BuildApiLayerUseCase _build;

  ApiLayerViewModel(this._build);

  int? collectionId;
  String packageName = 'app';
  DartModelStyle modelStyle = DartModelStyle.plain;
  bool domainLayer = true;

  bool isBusy = false;
  String? error;
  List<GeneratedFile> files = const [];
  List<String> notes = const [];

  void update({int? collection, String? package, DartModelStyle? style, bool? domain}) {
    if (collection != null) collectionId = collection;
    if (package != null) packageName = package;
    if (style != null) modelStyle = style;
    if (domain != null) domainLayer = domain;
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
        ),
      );
      files = result.files;
      notes = result.notes;
    } catch (e) {
      files = const [];
      notes = const [];
      error = "Couldn't read the collection: $e";
    }
    isBusy = false;
    notifyListeners();
  }
}
