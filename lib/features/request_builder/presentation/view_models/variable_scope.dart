import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/dynamic_variables.dart';
import '../../domain/entities/variable_info.dart';
import '../../domain/usecases/list_variables_usecase.dart';

/// The variables visible to the request being edited, kept ready so a text
/// field can colour its `{{tokens}}` synchronously and show a token's value on
/// hover. It is bound to a collection (variables are layered per collection)
/// and to the request's folder, whose variables (and those of the folders
/// above it) are visible too, and refreshes when asked to, whenever a variable
/// of the active environment, a folder, the collection or the globals changes
/// (or another environment becomes active), and when [refreshOn] notifies.
final class VariableScope extends ChangeNotifier {
  final ListVariablesUseCase _listVariables;
  final Listenable? _refreshOn;

  VariableScope(this._listVariables, {this._refreshOn}) {
    _refreshOn?.addListener(refresh);
  }

  int? _collectionId;
  int? _folderId;
  Map<String, VariableInfo> _variables = const {};
  bool _loaded = false;
  bool _disposed = false;
  StreamSubscription<void>? _changes;
  Future<void>? _refreshing;
  bool _stale = false;

  /// False until the first load finishes; until then nothing is flagged as
  /// undefined, so tokens do not flash red while the scopes are being read.
  bool get isLoaded => _loaded;

  /// [folderId] is the folder the request is in (null = the collection's top
  /// level); a request moved to another folder binds again with the new one.
  void bindCollection(int collectionId, {int? folderId}) {
    if (_collectionId == collectionId && _folderId == folderId) return;
    final sameCollection = _collectionId == collectionId;
    _collectionId = collectionId;
    _folderId = folderId;
    if (!sameCollection) {
      _changes?.cancel();
      _changes = _listVariables.changes(collectionId).listen((_) => refresh(), onError: (_) {});
    }
    refresh();
  }

  /// Reads the variables again. A call that arrives while a read is under way
  /// makes it read once more when it is done (what it saw may be out of date
  /// by then) and completes with it, so awaiting [refresh] always means the
  /// state is current.
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
    final id = _collectionId;
    final folderId = _folderId;
    if (id == null) return;
    try {
      final next = await _listVariables(id, folderId: folderId);
      if (_disposed || id != _collectionId || folderId != _folderId) return;
      final changed = !_loaded || !mapEquals(_variables, next);
      _variables = next;
      _loaded = true;
      if (changed) notifyListeners();
    } catch (_) {
      // Colouring and hover are conveniences; a failed read just leaves the last known state.
    }
  }

  /// Whether `{{name}}` resolves to something when the request is sent.
  bool isDefined(String name) => _variables.containsKey(name) || DynamicVariables.names.contains(name);

  /// What `{{name}}` stands for, for the hover card.
  VariableInfo describe(String name) {
    final known = _variables[name];
    if (known != null) return known;
    final sample = DynamicVariables.shared.resolve(name);
    if (sample != null) return VariableInfo(name: name, source: VariableSource.dynamic, value: sample);
    return VariableInfo.unresolved(name);
  }

  @override
  void dispose() {
    _disposed = true;
    _changes?.cancel();
    _refreshOn?.removeListener(refresh);
    super.dispose();
  }
}
