import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../../domain/entities/push_preview.dart';
import '../../domain/services/workspace_diff.dart';

enum PushAction { push, pullFirst }

final class PushDecision {
  final PushAction action;
  final String message;
  final bool overwrite;
  const PushDecision(this.action, this.message, this.overwrite);
}

/// Shown before every push: what will change in the repository, a commit
/// message already written from those changes, and a warning when someone
/// else pushed in the meantime (so their work is not silently overwritten).
class PushPreviewDialog extends StatefulWidget {
  final PushPreview preview;
  final String repository;
  final String branch;

  const PushPreviewDialog({super.key, required this.preview, required this.repository, required this.branch});

  static Future<PushDecision?> show(BuildContext context, {required PushPreview preview, required String repository, required String branch}) =>
      showDialog<PushDecision>(context: context, builder: (_) => PushPreviewDialog(preview: preview, repository: repository, branch: branch));

  @override
  State<PushPreviewDialog> createState() => _PushPreviewDialogState();
}

class _PushPreviewDialogState extends State<PushPreviewDialog> {
  late final _message = TextEditingController(text: widget.preview.suggestedMessage);
  bool _overwrite = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool get _canPush {
    final p = widget.preview;
    if (p.remoteChanged && !_overwrite) return false;
    return p.hasChanges || !p.remoteExists;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final p = widget.preview;
    final grouped = <String, List<WorkspaceChange>>{};
    for (final c in p.changes.changes) {
      grouped.putIfAbsent(c.container ?? c.scope, () => []).add(c);
    }
    return ToolDialog(
      icon: Icons.cloud_upload_outlined,
      title: 'Push to ${widget.repository}',
      subtitle: 'Branch ${widget.branch} · ${p.changes.changes.length} change${p.changes.changes.length == 1 ? '' : 's'}',
      width: 640,
      height: 640,
      footerLeading: Text('Pushes workspace.json', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (p.remoteChanged)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(PushDecision(PushAction.pullFirst, _message.text, false)),
            icon: const Icon(Icons.cloud_download_outlined, size: 16),
            label: const Text('Pull first'),
          ),
        GradientButton(
          label: p.remoteChanged ? 'Overwrite and push' : 'Push',
          icon: Icons.cloud_upload_outlined,
          onPressed: _canPush ? () => Navigator.of(context).pop(PushDecision(PushAction.push, _message.text.trim(), _overwrite)) : null,
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (p.remoteChanged)
            InfoBanner(
              kind: BannerKind.warning,
              title: 'The repository has changes you do not have',
              message: 'Someone else, or another device, pushed since your last sync. Pushing now replaces their version of workspace.json with yours. '
                  'Pull first to get their work, or tick the box to overwrite it.',
              trailing: null,
            ),
          if (p.remoteChanged)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _overwrite,
              onChanged: (v) => setState(() => _overwrite = v ?? false),
              title: const Text('Overwrite their changes with mine'),
            ),
          if (!p.remoteExists) const InfoBanner(kind: BannerKind.info, message: 'The repository has no workspace.json on this branch yet: this push creates it.'),
          if (p.remoteExists && !p.hasChanges && !p.remoteChanged)
            const InfoBanner(kind: BannerKind.success, title: 'Nothing to push', message: 'The repository already has everything in this workspace.'),
          const SizedBox(height: 10),
          if (p.hasChanges) ...[
            ToolSection(
              title: 'What changes in the repository',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in grouped.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Text(entry.key, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    for (final c in entry.value) _ChangeRow(change: c),
                  ],
                ],
              ),
            ),
          ],
          ToolSection(
            title: 'Commit message',
            hint: 'Written from the changes above; edit it if you like.',
            child: TextField(controller: _message, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'Describe what changed')),
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final WorkspaceChange change;
  const _ChangeRow({required this.change});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (sign, color) = switch (change.kind) {
      WorkspaceChangeKind.added => ('+', colors.statusSuccess),
      WorkspaceChangeKind.removed => ('−', colors.statusError),
      WorkspaceChangeKind.changed => ('~', colors.statusWarning),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 20, child: Text(sign, style: context.textStyles.mono.copyWith(color: color, fontWeight: FontWeight.w800))),
          Expanded(child: Text('${change.scope.toLowerCase()} ', style: context.textStyles.caption.copyWith(color: colors.secondaryText))),
          Expanded(flex: 4, child: Text(change.label, overflow: TextOverflow.ellipsis, style: context.textStyles.mono)),
        ],
      ),
    );
  }
}
