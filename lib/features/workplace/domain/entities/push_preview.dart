import '../services/workspace_diff.dart';

/// What pushing the open workplace to Git would do, worked out before it does it.
final class PushPreview {
  /// The repository already has a `workspace.json` on the branch.
  final bool remoteExists;

  /// The repository's file is not the one this workplace last synced with:
  /// someone else (or another device) pushed since.
  final bool remoteChanged;

  /// [remoteChanged] because this workplace never synced with the repository, which
  /// already has a different `workspace.json`, rather than because someone pushed since.
  final bool neverSynced;

  /// Local file compared with the repository's.
  final WorkspaceChangeSummary changes;

  /// A commit message written from [changes].
  final String suggestedMessage;

  const PushPreview({
    required this.remoteExists,
    required this.remoteChanged,
    this.neverSynced = false,
    required this.changes,
    required this.suggestedMessage,
  });

  bool get hasChanges => !changes.isEmpty;
}
