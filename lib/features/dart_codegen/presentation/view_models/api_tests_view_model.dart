import 'package:flutter/foundation.dart';
import '../../domain/entities/generated_file.dart';
import '../../domain/services/api_layer_generator.dart';
import '../../domain/services/api_test_generator.dart';
import '../../domain/services/dart_model_generator.dart';
import '../../domain/services/pubspec_lock_versions.dart';
import '../../domain/usecases/build_api_layer_usecase.dart';

/// Backs the "Tests" tab: the options of the API layer the tests are for, the test package to
/// import, and the result of the generation.
final class ApiTestsViewModel with ChangeNotifier {
  final BuildApiLayerUseCase _build;

  ApiTestsViewModel(this._build);

  int? collectionId;
  String packageName = 'app';
  DartModelStyle modelStyle = DartModelStyle.plain;
  bool domainLayer = true;
  bool allNullable = false;
  TestFramework framework = TestFramework.flutterTest;

  /// The text of the project's `pubspec.lock`, when the user pasted it: the dev dependencies then name
  /// versions the project already resolved.
  String lockText = '';

  bool isBusy = false;
  String? error;
  List<GeneratedFile> files = const [];
  List<String> notes = const [];
  String devDependencies = '';
  String addCommand = '';

  /// How many packages the pasted lock file named; null before anything was pasted.
  int? get lockedPackageCount => lockText.trim().isEmpty ? null : PubspecLockVersions.parse(lockText).length;

  void update({
    int? collection,
    String? package,
    DartModelStyle? style,
    bool? domain,
    bool? nullable,
    TestFramework? testFramework,
    String? lock,
  }) {
    if (collection != null) collectionId = collection;
    if (package != null) packageName = package;
    if (style != null) modelStyle = style;
    if (domain != null) domainLayer = domain;
    if (nullable != null) allNullable = nullable;
    if (testFramework != null) framework = testFramework;
    if (lock != null) lockText = lock;
    notifyListeners();
  }

  Future<void> generate() async {
    final id = collectionId;
    if (id == null || isBusy) return;
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      final spec = await _build.specs(id);
      final result = const ApiTestGenerator().generate(
        spec.name,
        spec.requests,
        options: ApiTestOptions(
          layer: ApiLayerOptions(
            packageName: packageName.trim().isEmpty ? 'app' : packageName.trim(),
            modelStyle: modelStyle,
            domainLayer: domainLayer,
            allNullable: allNullable,
          ),
          framework: framework,
          lockedVersions: PubspecLockVersions.parse(lockText),
        ),
      );
      files = result.files;
      notes = result.notes;
      devDependencies = result.devDependencies;
      addCommand = result.addCommand;
    } catch (e) {
      files = const [];
      notes = const [];
      devDependencies = '';
      addCommand = '';
      error = "Couldn't read the collection: $e";
    }
    isBusy = false;
    notifyListeners();
  }
}
