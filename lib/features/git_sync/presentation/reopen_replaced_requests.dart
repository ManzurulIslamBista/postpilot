import 'package:flutter/widgets.dart';
import '../../shell/presentation/shell_view_model.dart';

/// Brings the open request tabs in line with requests a Git operation rewrote in the database.
/// Deleted ones close. Changed ones that are open are closed now and opened again after the next frame:
/// tabs are keyed by request id, so closing and reopening within one frame would keep the stale editor state
/// (whose auto-save would then overwrite what was just pulled).
void reopenReplacedRequests(ShellViewModel shell, List<int> changedRequestIds, List<int> deletedRequestIds) {
  final selectedId = shell.selectedRequestId;
  for (final id in deletedRequestIds) {
    shell.closeRequest(id);
  }
  final open = shell.openRequestIds.toSet();
  final stale = changedRequestIds.where(open.contains).toList();
  if (stale.isEmpty) return;
  for (final id in stale) {
    shell.closeRequest(id);
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final id in stale) {
      shell.selectRequest(id);
    }
    if (selectedId != null && !deletedRequestIds.contains(selectedId)) shell.selectRequest(selectedId);
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}
