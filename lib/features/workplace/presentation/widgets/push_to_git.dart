import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/workplace_view_model.dart';
import 'push_preview_dialog.dart';

/// Pushes the open workplace to its Git repository and reports the outcome.
///
/// The whole workspace is written to the repository, environments included. A
/// secret-marked value (a password, a token) in one of them would therefore be
/// readable by everyone who can read the repository, so the user is asked first.
/// Returns whether the push was attempted (false when the user backed out).
Future<bool> pushWorkplaceToGit(BuildContext context, WorkplaceViewModel vm) async {
  final secrets = await vm.secretsInWorkspace();
  if (secrets.isNotEmpty) {
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _SecretsWarningDialog(secrets: secrets, repository: vm.activeWorkplace?.gitRepoUrl ?? 'the repository'),
    );
    if (confirmed != true) return false;
  }

  // What would change, with a commit message written from it, and a warning if someone else pushed meanwhile.
  final preview = await vm.previewPush();
  if (!context.mounted) return false;
  if (preview == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(vm.errorMessage ?? "Couldn't check the repository"), backgroundColor: context.colors.statusError),
    );
    return false;
  }
  final active = vm.activeWorkplace;
  final decision = await PushPreviewDialog.show(
    context,
    preview: preview,
    repository: _repositoryLabel(active?.gitRepoUrl),
    branch: active?.gitBranch ?? 'main',
  );
  if (decision == null || !context.mounted) return false;
  if (decision.action == PushAction.pullFirst) return pullWorkplaceFromGit(context, vm);

  await vm.syncWithGit(commitMessage: decision.message.isEmpty ? null : decision.message, overwrite: decision.overwrite);
  if (context.mounted) {
    final error = vm.errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Synced successfully with Git repository!'),
        backgroundColor: error != null ? context.colors.statusError : null,
      ),
    );
  }
  return true;
}

/// `https://github.com/acme/api.git` and `acme/api` both read "acme/api".
String _repositoryLabel(String? url) {
  if (url == null || url.isEmpty) return 'the repository';
  return url.replaceFirst(RegExp(r'^https?://(www\.)?github\.com/'), '').replaceFirst(RegExp(r'^git@github\.com:'), '').replaceFirst(RegExp(r'\.git$'), '');
}

/// Pulls the open workplace from its Git repository and reports the outcome. A
/// pull replaces everything in the workplace with the repository's copy, so
/// changes not yet pushed would be lost: the user is asked first.
/// Returns whether the pull was attempted.
Future<bool> pullWorkplaceFromGit(BuildContext context, WorkplaceViewModel vm) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Replace this workplace with the repository copy?'),
      content: Text(
        'Pulling replaces the collections, environments and variables in "${vm.activeWorkplace?.name ?? 'this workplace'}" '
        'with what is in the repository. Changes you have not pushed yet will be lost.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Pull and replace'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  await vm.pullFromGit();
  if (context.mounted) {
    final error = vm.errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Pulled successfully from Git repository!'),
        backgroundColor: error != null ? context.colors.statusError : null,
      ),
    );
  }
  return true;
}

class _SecretsWarningDialog extends StatelessWidget {
  static const _shown = 6;

  final List<String> secrets;
  final String repository;
  const _SecretsWarningDialog({required this.secrets, required this.repository});

  @override
  Widget build(BuildContext context) {
    final listed = secrets.take(_shown).join('\n');
    final more = secrets.length > _shown ? '\n…and ${secrets.length - _shown} more' : '';
    return AlertDialog(
      title: const Text('Push secret values to Git?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This workspace holds ${secrets.length} secret value${secrets.length == 1 ? '' : 's'} that would be '
              'written, in plain text, to workspace.json in $repository. Anyone who can read that repository can read them.',
            ),
            const SizedBox(height: 12),
            Text('$listed$more', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 12),
            const Text('Empty them first, or make sure the repository is private.'),
          ],
        ),
      ),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Push anyway'),
        ),
      ],
    );
  }
}
