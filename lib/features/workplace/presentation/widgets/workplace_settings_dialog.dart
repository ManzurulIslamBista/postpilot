import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/workplace_entity.dart';
import '../view_models/workplace_view_model.dart';

const _classicTokenUrl = 'https://github.com/settings/tokens/new?scopes=repo,read:user,user:email&description=PostPilot';

class WorkplaceSettingsDialog extends StatefulWidget {
  final WorkplaceEntity workplace;
  const WorkplaceSettingsDialog({super.key, required this.workplace});

  static Future<void> show(BuildContext context, WorkplaceEntity workplace) => showDialog(
        context: context,
        builder: (_) => WorkplaceSettingsDialog(workplace: workplace),
      );

  @override
  State<WorkplaceSettingsDialog> createState() => _WorkplaceSettingsDialogState();
}

class _WorkplaceSettingsDialogState extends State<WorkplaceSettingsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _gitRepoController;
  late final TextEditingController _gitBranchController;
  late final TextEditingController _gitTokenController;
  bool _connectGit = false;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workplace.name);
    _gitRepoController = TextEditingController(text: widget.workplace.gitRepoUrl ?? '');
    _gitBranchController = TextEditingController(text: widget.workplace.gitBranch);
    _gitTokenController = TextEditingController(text: widget.workplace.gitToken ?? '');
    _connectGit = widget.workplace.isGitConnected;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gitRepoController.dispose();
    _gitBranchController.dispose();
    _gitTokenController.dispose();
    super.dispose();
  }

  Future<void> _openClassicTokenUrl() async {
    final uri = Uri.parse(_classicTokenUrl);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _save() async {
    final vm = context.read<WorkplaceViewModel>();
    final updated = widget.workplace.copyWith(
      name: _nameController.text.trim(),
      gitRepoUrl: _connectGit && _gitRepoController.text.trim().isNotEmpty ? _gitRepoController.text.trim() : null,
      gitBranch: _connectGit && _gitBranchController.text.trim().isNotEmpty ? _gitBranchController.text.trim() : 'main',
      gitToken: _connectGit && _gitTokenController.text.trim().isNotEmpty ? _gitTokenController.text.trim() : null,
    );
    await vm.updateWorkplace(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Workplace?'),
        content: Text('Remove "${widget.workplace.name}" from PostPilot? Local files will remain on disk.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.colors.statusError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final vm = context.read<WorkplaceViewModel>();
      await vm.deleteWorkplace(widget.workplace.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: colors.sidebarBackground.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Workplace Settings', style: textStyles.heading.copyWith(fontSize: 16)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Workplace Name', style: textStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(isDense: true),
                      ),
                      const SizedBox(height: 16),

                      Text('Folder on PC', style: textStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.sidebarBackground.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_outlined, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.workplace.folderPath,
                                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => context.read<WorkplaceViewModel>().revealInFinder(),
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('Open'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Git connection
                      SwitchListTile(
                        value: _connectGit,
                        onChanged: (val) => setState(() => _connectGit = val),
                        title: const Text('Connected Git Repository'),
                        subtitle: const Text('Sync single workspace.json with GitHub'),
                      ),
                      if (_connectGit) ...[
                        const SizedBox(height: 10),
                        Text('Repository URL', style: textStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _gitRepoController,
                          decoration: const InputDecoration(hintText: 'https://github.com/owner/repo', isDense: true),
                        ),
                        const SizedBox(height: 10),
                        Text('Branch', style: textStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _gitBranchController,
                          decoration: const InputDecoration(hintText: 'main', isDense: true),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text('GitHub Personal Access Token (classic)',
                                  style: textStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                            ),
                            InkWell(
                              onTap: _openClassicTokenUrl,
                              child: Text('Create Token (classic)',
                                  style: textStyles.caption.copyWith(color: colors.mainAccent, decoration: TextDecoration.underline)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _gitTokenController,
                          obscureText: _obscureToken,
                          decoration: InputDecoration(
                            hintText: 'ghp_...',
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off, size: 18),
                              onPressed: () => setState(() => _obscureToken = !_obscureToken),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),
                      const Divider(),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Delete this workplace', style: TextStyle(color: colors.statusError, fontWeight: FontWeight.bold)),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: colors.statusError),
                            onPressed: _delete,
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: colors.sidebarBackground.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
