import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/inherited_defaults.dart';
import '../../domain/usecases/resolve_request_defaults_usecase.dart';

/// What the request being edited inherits from its collection and folders, kept ready so the Headers,
/// Auth and Tests tabs can show it read-only next to what the request has of its own. Bound to the
/// request's collection and folder; it refreshes when either changes (a request moved to another
/// folder binds again) and whenever a default of that collection is edited, wherever that happened.
final class InheritedDefaultsViewModel extends ChangeNotifier {
  final ResolveRequestDefaultsUseCase _resolve;

  InheritedDefaultsViewModel(this._resolve);

  int? _collectionId;
  int? _folderId;
  InheritedDefaults _inherited = InheritedDefaults.none;
  bool _loaded = false;
  bool _disposed = false;
  StreamSubscription<void>? _changes;
  Future<void>? _refreshing;
  bool _stale = false;

  InheritedDefaults get inherited => _inherited;

  /// False until the first read finishes; until then the tabs show nothing inherited rather than "nothing".
  bool get isLoaded => _loaded;

  /// The folder the request is in, null at the collection's top level.
  int? get folderId => _folderId;
  int? get collectionId => _collectionId;

  void bind(int collectionId, {int? folderId}) {
    if (_collectionId == collectionId && _folderId == folderId) return;
    final sameCollection = _collectionId == collectionId;
    _collectionId = collectionId;
    _folderId = folderId;
    if (!sameCollection) {
      _changes?.cancel();
      _changes = _resolve.changes(collectionId).listen((_) => refresh(), onError: (_) {});
    }
    refresh();
  }

  /// Reads again. A call that arrives while a read is under way makes it read once more when it is
  /// done (what it saw may be out of date by then) and completes with it.
  Future<void> refresh() {
    if (_collectionId == null || _disposed) return Future.value();
    final running = _refreshing;
    if (running != null) {
      _stale = true;
      return running;
    }
    return _refreshing = _refreshUntilCurrent();
  }

  Future<void> _refreshUntilCurrent() async {
    try {
      do {
        _stale = false;
        await _readOnce();
      } while (_stale && !_disposed);
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _readOnce() async {
    final collectionId = _collectionId;
    final folderId = _folderId;
    if (collectionId == null) return;
    try {
      final next = await _resolve.forFolder(collectionId, folderId);
      if (_disposed || collectionId != _collectionId || folderId != _folderId) return;
      _inherited = next;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // What is inherited is shown for information; a failed read leaves the last known state.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _changes?.cancel();
    super.dispose();
  }
}
