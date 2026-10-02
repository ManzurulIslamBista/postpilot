import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/workplace_view_model.dart';

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
      builder: (_) => _SecretsWarningDialog(secrets: secrets, repository: vm.activeWorkplace?.gitRepoUrl ?? 'the repository'),
    );
    if (confirmed != true) return false;
  }

  await vm.syncWithGit();
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
