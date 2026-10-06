import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
import '../../domain/entities/default_variable.dart';
import '../../domain/entities/inherited_defaults.dart';
import '../../domain/entities/level_defaults.dart';
import '../../domain/repositories/defaults_repository.dart';
import '../../domain/services/defaults_codec.dart';
import '../../domain/services/defaults_resolver.dart';

/// Backs the "defaults" dialog of one collection or folder: a working copy of what that level
/// passes down (headers, auth, variables, tests) that is written in one go by [save], and only then.
///
/// A collection keeps its auth and variables in tables of their own (`collection_auth`,
/// `collection_variables`, the same data its Variables and Auth dialogs edit), so for a collection
/// those two are read from and written back to them rather than copied.
final class DefaultsViewModel extends ChangeNotifier {
  final DefaultsRepository _defaults;
  final CollectionAuthRepository _collectionAuth;
  final CollectionVariableRepository _collectionVariables;

  DefaultsViewModel(this._defaults, this._collectionAuth, this._collectionVariables);

  int collectionId = 0;

  /// The folder being edited; null when it is the collection itself.
  int? folderId;
  bool get isFolder => folderId != null;

  String collectionName = '';
  String? folderName;

  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;

  List<KeyValueItem> headers = [];
  List<DefaultVariable> variables = [];

  /// The auth requests below inherit. On a folder null is "Inherit from parent"; a collection
  /// always has one ([RequestAuth.none] when none was ever set).
  RequestAuth? auth;
  List<AssertionEntity> assertions = [];
  List<ExtractorEntity> extractors = [];

  /// What this level itself inherits from above: for a folder, the collection's and the outer
  /// folders' headers, auth and tests; nothing for the collection. Shown read-only.
  InheritedDefaults above = InheritedDefaults.none;

  String? _loadedSnapshot;
  String? _loadedAuthText;

  /// The collection variables as stored when the dialog opened, by row id, and which row each
  /// editor row stands for (by the editor row's session id).
  final Map<int, CollectionVariableEntity> _storedVariables = {};
  final Map<int, int> _rowOfVariable = {};

  Future<void> load({required int collectionId, int? folderId}) async {
    this.collectionId = collectionId;
    this.folderId = folderId;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final tree = await _defaults.loadTree(collectionId);
      collectionName = tree.collectionName;
      if (folderId == null) {
        headers = [...tree.collection.headers];
        assertions = [...tree.collection.assertions];
        extractors = [...tree.collection.extractors];
        auth = tree.collection.auth ?? RequestAuth.none;
        above = InheritedDefaults.none;
        await _loadCollectionVariables();
      } else {
        final level = tree.folderDefaults[folderId] ?? LevelDefaults.empty;
        folderName = tree.folders.where((f) => f.id == folderId).firstOrNull?.name;
        headers = [...level.headers];
        variables = [...level.variables];
        auth = level.auth;
        assertions = [...level.assertions];
        extractors = [...level.extractors];
        above = DefaultsResolver.resolve(tree.chainAbove(folderId));
      }
      _loadedAuthText = _authText();
      _loadedSnapshot = _snapshot();
    } catch (e) {
      errorMessage = 'Could not read the defaults (${e.runtimeType}). Close this dialog and open it again.';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> _loadCollectionVariables() async {
    final rows = await _collectionVariables.watchByCollection(collectionId).first;
    _storedVariables
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.id, r)));
    _rowOfVariable.clear();
    variables = [
      for (final row in rows) _variableOfRow(row),
    ];
  }

  DefaultVariable _variableOfRow(CollectionVariableEntity row) {
    final variable = DefaultVariable(key: row.key, value: row.value, enabled: row.enabled);
    _rowOfVariable[variable.id] = row.id;
    return variable;
  }

  bool get hasUnsavedChanges => !isLoading && _snapshot() != _loadedSnapshot;

  void setHeaders(List<KeyValueItem> items) {
    headers = items;
    notifyListeners();
  }

  void setVariables(List<DefaultVariable> items) {
    variables = items;
    notifyListeners();
  }

  /// [value] null means "Inherit from parent" (folders only).
  void setAuth(RequestAuth? value) {
    auth = isFolder && value?.type == AuthType.inherit ? null : value;
    notifyListeners();
  }

  void setAssertions(List<AssertionEntity> items) {
    assertions = items;
    notifyListeners();
  }

  void setExtractors(List<ExtractorEntity> items) {
    extractors = items;
    notifyListeners();
  }

  /// Writes everything. True when it is stored. A row with no key is dropped (a blank row
  /// the user never filled in), a header row with a key but no value is kept: an empty
  /// value is a header.
  Future<bool> save() async {
    if (isSaving || isLoading) return false;
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      final kept = [
        for (final h in headers)
          if (h.key.trim().isNotEmpty) h,
      ];
      final keptVariables = [
        for (final v in variables)
          if (v.key.trim().isNotEmpty) v,
      ];
      if (isFolder) {
        await _defaults.saveFolder(
          folderId!,
          LevelDefaults(
            headers: kept,
            variables: keptVariables,
            auth: auth,
            assertions: assertions,
            extractors: extractors,
          ),
        );
      } else {
        await _defaults.saveCollection(
          collectionId,
          LevelDefaults(headers: kept, assertions: assertions, extractors: extractors),
        );
        await _saveCollectionAuth();
        await _saveCollectionVariables(keptVariables);
      }
      headers = kept;
      // A collection's variables were read back from their table (see [_saveCollectionVariables]).
      if (isFolder) variables = keptVariables;
      _loadedAuthText = _authText();
      _loadedSnapshot = _snapshot();
      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      // The exception can quote a value that was being written; only its type is shown.
      errorMessage = 'Could not save the defaults (${e.runtimeType}). Close this dialog and open it again to see what '
          'was stored before trying once more.';
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// The collection's auth is only written when it changed, so a collection that never had one keeps no row.
  Future<void> _saveCollectionAuth() async {
    if (_authText() == _loadedAuthText) return;
    await _collectionAuth.setAuthJson(collectionId, (auth ?? RequestAuth.none).toJsonString());
  }

  String _authText() => jsonEncode(auth?.toJson());

  Future<void> _saveCollectionVariables(List<DefaultVariable> kept) async {
    final keptRows = {
      for (final v in kept)
        if (_rowOfVariable[v.id] != null) _rowOfVariable[v.id]!,
    };
    for (final id in _storedVariables.keys.where((id) => !keptRows.contains(id))) {
      await _collectionVariables.delete(id);
    }
    for (final v in kept) {
      final row = _rowOfVariable[v.id];
      final stored = row == null ? null : _storedVariables[row];
      final unchanged = stored != null && stored.key == v.key && stored.value == v.value && stored.enabled == v.enabled;
      if (unchanged) continue;
      await _collectionVariables.upsert(
        CollectionVariableEntity(id: row ?? 0, collectionId: collectionId, key: v.key, value: v.value, enabled: v.enabled),
      );
    }
    // The rows just written have ids now; reading them again keeps a second save from adding them twice.
    await _loadCollectionVariables();
  }

  /// What would be saved, as text, to tell whether anything changed since the dialog opened.
  String _snapshot() => jsonEncode({
        'h': DefaultsCodec.headersToJson([
          for (final h in headers)
            if (h.key.trim().isNotEmpty) h,
        ]),
        'v': DefaultsCodec.variablesToJson([
          for (final v in variables)
            if (v.key.trim().isNotEmpty) v,
        ]),
        'a': auth?.toJson(),
        't': DefaultsCodec.toDoc(LevelDefaults(assertions: assertions, extractors: extractors))['tests'],
      });
}
