import '../../../core/widgets/busy_label.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/utils/file_download.dart';
import '../domain/entities/backup_export.dart';
import 'view_models/backup_view_model.dart';

/// Backup and restore of all local data: collections, environments (secret
/// values included) and global variables. Export offers copy and download;
/// restore pastes a backup and adds it as new data without overwriting anything.
class BackupDialog extends StatefulWidget {
  const BackupDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(context: context, builder: (_) => const BackupDialog());

  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog> {
  static const _previewLimit = 20000;

  final _restoreController = TextEditingController();
  late final BackupViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<BackupViewModel>();
    _viewModel.loadBackup();
  }

  @override
  void dispose() {
    _restoreController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _copy(BackupExport backup) {
    Clipboard.setData(ClipboardData(text: backup.text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup copied to clipboard')));
  }

  Future<void> _download(BackupExport backup) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await downloadFile(
        fileName: 'postpilot-backup-${_stamp(DateTime.now())}.json',
        bytes: Uint8List.fromList(utf8.encode(backup.text)),
        mimeType: 'application/json',
      );
      messenger.showSnackBar(SnackBar(content: Text(path == null ? 'Backup download started' : 'Saved to $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save file: $e")));
    }
  }

  Future<void> _restore() async {
    final summary = await _viewModel.restore(_restoreController.text);
    if (summary == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary.description)));
    Navigator.pop(context);
  }

  static String _stamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-${two(time.hour)}${two(time.minute)}';
  }

  static String _size(String text) {
    final bytes = utf8.encode(text).length;
    return bytes < 1024
        ? '$bytes B'
        : bytes < 1048576
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BackupViewModel>.value(
      value: _viewModel,
      child: Consumer<BackupViewModel>(
        // Esc and a barrier tap dismiss the dialog (and dispose the ViewModel)
        // even though the buttons are disabled, so block them while restoring.
        builder: (context, vm, _) => PopScope(
          canPop: !vm.isRestoring,
          child: Dialog(
            child: SizedBox(
              width: 640,
              height: 540,
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(child: Text('Backup & restore', style: context.textStyles.heading)),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                            onPressed: vm.isRestoring ? null : () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const TabBar(
                      tabs: [
                        Tab(text: 'Export'),
                        Tab(text: 'Restore'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(children: [_buildExportTab(context, vm), _buildRestoreTab(context, vm)]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportTab(BuildContext context, BackupViewModel vm) {
    final backup = vm.backup;
    final Widget body;
    if (vm.exportError != null) {
      body = Text(vm.exportError!, style: TextStyle(color: Theme.of(context).colorScheme.error));
    } else if (backup == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final preview = backup.text.length > _previewLimit
          ? '${backup.text.substring(0, _previewLimit)}\n... preview shortened; Copy or Download gives the whole backup.'
          : backup.text;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${backup.collections} collections, ${backup.requests} requests, ${backup.environments} environments, '
            '${backup.globalVariables} global variables (${_size(backup.text)})',
            style: context.textStyles.caption,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                onPressed: () => _copy(backup),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Download'),
                onPressed: () => _download(backup),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(preview, style: context.textStyles.mono.copyWith(fontSize: 12)),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SensitiveNotice(),
          const SizedBox(height: 12),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildRestoreTab(BuildContext context, BackupViewModel vm) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste a PostPilot backup below. Restoring adds its collections and environments as new ones; nothing you '
            'already have is changed or overwritten (a global variable whose name already exists is skipped).',
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _restoreController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: context.textStyles.mono.copyWith(fontSize: 12),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{ "format": "postpilot-backup", ... }',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (vm.restoreError != null) ...[
            const SizedBox(height: 8),
            Text(vm.restoreError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: vm.isRestoring || _restoreController.text.trim().isEmpty ? null : _restore,
              child: BusyLabel(busy: vm.isRestoring, label: 'Restore', busyLabel: 'Restoring…'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensitiveNotice extends StatelessWidget {
  const _SensitiveNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.statusError.withValues(alpha: 0.12),
        border: Border.all(color: context.colors.statusError.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: context.colors.statusError),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This backup contains secrets: variable values, tokens, passwords and API keys in plain text. '
              'Store it somewhere private and never share it.',
              style: context.textStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}
