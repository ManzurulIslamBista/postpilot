import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/entity_kind.dart';
import '../../domain/repositories/documentation_repository.dart';

/// Backs the description editor of one collection, folder or request. Edits are
/// saved shortly after typing stops, and whatever is still waiting is written
/// when the view model is disposed.
final class EntityDocsViewModel with ChangeNotifier {
  final DocumentationRepository _repository;
  final EntityKind kind;
  final int localId;
  final Duration _debounce;

  EntityDocsViewModel(
    this._repository,
    this.kind,
    this.localId, {
    this._debounce = const Duration(milliseconds: 500),
  }) {
    _load();
  }

  String markdown = '';
  bool isLoading = true;
  String? saveError;

  Timer? _timer;
  bool _dirty = false;
  bool _disposed = false;

  Future<void> _load() async {
    final stored = await _repository.markdownOf(kind, localId);
    if (_disposed) return;
    if (!_dirty) markdown = stored;
    isLoading = false;
    notifyListeners();
  }

  /// The editor owns the text while typing, so listeners are not notified.
  void update(String text) {
    if (text == markdown && !_dirty) return;
    markdown = text;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(_debounce, flush);
  }

  /// Writes any unsaved text now. A failed write keeps the text marked unsaved
  /// so the next edit or flush tries again.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return;
    _dirty = false;
    try {
      await _repository.setMarkdown(kind, localId, markdown);
      _setSaveError(null);
    } catch (e) {
      _dirty = true;
      _setSaveError('Could not save the description: $e');
    }
  }

  void _setSaveError(String? message) {
    if (saveError == message) return;
    saveError = message;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(flush());
    super.dispose();
  }
}
