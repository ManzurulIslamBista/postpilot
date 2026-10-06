import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../domain/services/production_guard.dart';

/// "You are about to change data in Production." Returns whether to go ahead.
/// Cancel is the default, so a stray Enter never sends. A request that deletes
/// data is always asked about: it never offers "don't ask again".
Future<bool> confirmProductionSend(BuildContext context, ProductionWarning warning, {required void Function() onSilence}) async {
  var silence = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final colors = context.colors;
        return AlertDialog(
          icon: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: colors.statusError.withValues(alpha: 0.13), shape: BoxShape.circle),
            child: Icon(Icons.shield_outlined, color: colors.statusError, size: 24),
          ),
          title: Text('Send to ${warning.environmentName}?'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(warning.description, style: context.textStyles.body),
                const SizedBox(height: 8),
                Text(
                  warning.reason ?? 'The active environment looks like production, so this will change real data.',
                  style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                ),
                const SizedBox(height: 10),
                if (warning.destructive)
                  Text(
                    'Deleting data is always asked about, even if you chose not to be asked again.',
                    style: context.textStyles.caption.copyWith(color: colors.statusError),
                  )
                else
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: silence,
                    onChanged: (v) => setState(() => silence = v ?? false),
                    title: const Text("Don't ask again until PostPilot restarts"),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.statusError),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Send anyway'),
            ),
          ],
        );
      },
    ),
  );
  if (ok == true && silence && !warning.destructive) onSilence();
  return ok ?? false;
}
