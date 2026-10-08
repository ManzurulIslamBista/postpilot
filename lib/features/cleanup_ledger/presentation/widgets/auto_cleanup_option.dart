import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../view_models/cleanup_ledger.dart';

/// "Auto clean up after the run": the one tick the collection runner's setup gets. Ticked, a finished run deletes what
/// it created without waiting for the button (the production lock still asks). A choice for this session only, kept on
/// the ledger so it survives closing and reopening the runner. Shows nothing where there is no ledger.
class AutoCleanupOption extends StatelessWidget {
  /// Replaces the one from the service locator, for a test.
  @visibleForTesting
  final CleanupLedger? ledger;

  const AutoCleanupOption({super.key, this.ledger});

  @override
  Widget build(BuildContext context) {
    final source = ledger ?? (locator.isRegistered<CleanupLedger>() ? locator<CleanupLedger>() : null);
    if (source == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) => InkWell(
        onTap: () => source.autoCleanup = !source.autoCleanup,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              key: const ValueKey('auto-cleanup'),
              value: source.autoCleanup,
              onChanged: (value) => source.autoCleanup = value ?? false,
            ),
            // Flexible: on a narrow screen the label wraps instead of running out of the dialog.
            const Flexible(
              child: Tooltip(
                message: 'Requests with "Clean up what this request creates" switched on (Settings tab) have the records they '
                    'made deleted when the run is done. On a production environment you are asked first. '
                    'Without this tick the run ends with a list of them and a Delete button.',
                child: Text('Auto clean up after the run'),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
