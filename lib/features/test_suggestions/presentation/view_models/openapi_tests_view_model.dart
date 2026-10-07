import 'package:flutter/foundation.dart';
import '../../domain/openapi/generated_case.dart';
import '../../domain/openapi/openapi_test_generator.dart';
import '../../domain/usecases/generate_openapi_tests_usecase.dart';

/// Backs "Generate tests from OpenAPI…": reads a document into a preview (how many requests of each kind, what
/// they expect), lets the person tick what to write and how many at most, and writes them into a collection.
final class OpenApiTestsViewModel with ChangeNotifier {
  /// Reads [text] into a suite. The app runs it on its own isolate: a large document would freeze the window.
  final Future<GeneratedSuite> Function(String text) _read;

  /// Writes a selection into a collection.
  final Future<GeneratedTestsResult> Function(int collectionId, GeneratedSuite suite, GeneratedSelection selection) _write;

  OpenApiTestsViewModel({
    this.collectionId,
    Future<GeneratedSuite> Function(String text)? read,
    required this._write,
  }) : _read = read ?? ((text) => compute(OpenApiTestGenerator.generate, text));

  int? collectionId;
  String spec = '';
  GeneratedSuite? suite;
  GeneratedSelection? selection;
  final Set<TestCategory> categories = {...TestCategory.values};
  int cap = GeneratedSuite.defaultCap;

  /// What is wrong with the cap field as typed, or null.
  String? capError;
  bool busy = false;
  String? error;
  GeneratedTestsResult? result;
  bool _disposed = false;

  bool get canPreview => !busy && spec.trim().isNotEmpty;

  bool get canGenerate => !busy && collectionId != null && (selection?.cases.isNotEmpty ?? false) && result == null && capError == null;

  void setCollection(int? id) {
    collectionId = id;
    result = null;
    _notify();
  }

  void setSpec(String text) {
    spec = text;
    // A different document is a different suite: the old preview no longer describes it.
    suite = null;
    selection = null;
    result = null;
    error = null;
    _notify();
  }

  Future<void> preview() async {
    if (!canPreview) return;
    busy = true;
    error = null;
    result = null;
    _notify();
    try {
      suite = await _read(spec);
      _reselect();
    } catch (e) {
      suite = null;
      selection = null;
      error = 'The document could not be read: ${'$e'.replaceFirst('ImportException: ', '')}';
    } finally {
      busy = false;
      _notify();
    }
  }

  void toggleCategory(TestCategory category) {
    if (!categories.remove(category)) categories.add(category);
    _reselect();
    _notify();
  }

  /// [text] as the most requests to write; anything that is not a whole number from 1 up is told, not guessed.
  void setCap(String text) {
    final n = int.tryParse(text.trim());
    if (n == null || n < 1) {
      capError = 'Enter a whole number, 1 or more.';
    } else {
      capError = null;
      cap = n;
      _reselect();
    }
    _notify();
  }

  void _reselect() {
    final current = suite;
    selection = current?.select(categories: categories, cap: cap);
  }

  Future<void> generate() async {
    final target = collectionId;
    final current = suite;
    final chosen = selection;
    if (!canGenerate || target == null || current == null || chosen == null) return;
    busy = true;
    error = null;
    _notify();
    try {
      result = await _write(target, current, chosen);
    } catch (e) {
      error = 'The requests could not be created: $e';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
