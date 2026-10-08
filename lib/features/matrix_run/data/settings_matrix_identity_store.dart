import 'dart:convert';
import '../../../core/database/daos/settings_dao.dart';
import '../domain/entities/matrix_identity.dart';
import '../domain/repositories/matrix_identity_store.dart';

/// Keeps a workplace's identities as one JSON value in the settings table (`setting_entries`), under a key that names
/// the workplace. That table is local to this device: it is not part of `workspace.json`, of a Git push or of a backup,
/// which is where the secret values of an identity must never end up.
final class SettingsMatrixIdentityStore implements MatrixIdentityStore {
  static const keyPrefix = 'matrix.identities.';

  final SettingsDao _dao;

  /// The id of the active workplace; null when there is none (a key of its own, `default`, then).
  final Future<String?> Function() _workplaceId;

  SettingsMatrixIdentityStore(this._dao, this._workplaceId);

  Future<String> _key() async {
    final id = await _workplaceId();
    return '$keyPrefix${id == null || id.isEmpty ? 'default' : id}';
  }

  @override
  Future<List<MatrixIdentity>> load() async {
    try {
      final text = await _dao.get(await _key());
      if (text == null) return const [];
      final decoded = jsonDecode(text);
      final list = decoded is Map ? decoded['identities'] : null;
      if (list is! List) return const [];
      return [
        for (final item in list) ?MatrixIdentity.fromJson(item),
      ];
    } catch (_) {
      // A damaged value means no identities, not a crash when the dialog opens.
      return const [];
    }
  }

  @override
  Future<void> save(List<MatrixIdentity> identities) async {
    final key = await _key();
    if (identities.isEmpty) {
      await _dao.remove(key);
      return;
    }
    await _dao.put(key, jsonEncode({'v': 1, 'identities': [for (final i in identities) i.toJson()]}));
  }
}
