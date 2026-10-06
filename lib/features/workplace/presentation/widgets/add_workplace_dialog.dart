import '../../../../core/widgets/busy_label.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/workplace_exception.dart';
import '../view_models/workplace_view_model.dart';

const _classicTokenUrl =
    'https://github.com/settings/tokens/new?scopes=repo,read:user,user:email&description=PostPilot';

class AddWorkplaceDialog extends StatefulWidget {
  const AddWorkplaceDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, barrierDismissible: false, builder: (_) => const AddWorkplaceDialog());

  @override
  State<AddWorkplaceDialog> createState() => _AddWorkplaceDialogState();
}

class _AddWorkplaceDialogState extends State<AddWorkplaceDialog> {
  final _nameController = TextEditingController();
  final _folderController = TextEditingController();
  final _gitRepoController = TextEditingController();
  final _gitBranchController = TextEditingController(text: 'main');
  final _gitTokenController = TextEditingController();

  bool _isFolderManuallyEdited = false;
  bool _connectGit = false;
  bool _obscureToken = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _updateDefaultFolder('');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _folderController.dispose();
    _gitRepoController.dispose();
    _gitBranchController.dispose();
    _gitTokenController.dispose();
    super.dispose();
  }

  Future<void> _updateDefaultFolder(String name) async {
    if (_isFolderManuallyEdited) return;
    final vm = context.read<WorkplaceViewModel>();
    try {
      final defaultPath = await vm.getDefaultWorkplacesDirectory(workplaceName: name.isEmpty ? 'My Workplace' : name);
      if (!_isFolderManuallyEdited && mounted) {
        setState(() {
          _folderController.text = defaultPath;
        });
      }
    } catch (_) {
      // No suggestion available: the user can still type or browse for a folder.
    }
  }

  Future<void> _browseFolder() async {
    final vm = context.read<WorkplaceViewModel>();
    final selected = await vm.pickFolder(initialPath: _folderController.text);
    if (selected != null && mounted) {
      setState(() {
        _folderController.text = selected;
        _isFolderManuallyEdited = true;
      });
    }
  }

  Future<void> _openClassicTokenUrl() async {
    final uri = Uri.parse(_classicTokenUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final folder = _folderController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Please enter a workplace name');
      return;
    }
    if (folder.isEmpty) {
      setState(() => _error = 'Please enter or select a folder path');
      return;
    }

    if (_connectGit) {
      if (_gitRepoController.text.trim().isEmpty) {
        setState(() => _error = 'Please enter a Git repository URL');
        return;
      }
      if (_gitTokenController.text.trim().isEmpty) {
        setState(() => _error = 'Please enter your GitHub classic token');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final vm = context.read<WorkplaceViewModel>();
      await vm.createWorkplace(
        name: name,
        folderPath: folder,
        gitRepoUrl: _connectGit ? _gitRepoController.text.trim() : null,
        gitBranch: _connectGit ? _gitBranchController.text.trim() : 'main',
        gitToken: _connectGit ? _gitTokenController.text.trim() : null,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Workplace "$name" created successfully')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is WorkplaceException ? e.message : 'Error: $e';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    final vm = context.read<WorkplaceViewModel>();
    final realFolders = vm.usesRealFolders;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // macOS Sheet Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: colors.sidebarBackground.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.mainAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.workspaces_outlined, size: 20, color: colors.mainAccent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Add New Workplace', style: textStyles.heading.copyWith(fontSize: 16)),
                          Text(
                            'Stores all environments, collections, and requests in a single JSON file',
                            style: textStyles.caption.copyWith(color: colors.secondaryText),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Form Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Workplace Name
                      Text('Workplace Name', style: textStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Production APIs, Team Backend, Personal',
                          isDense: true,
                          prefixIcon: Icon(Icons.badge_outlined, size: 18),
                        ),
                        onChanged: (val) {
                          _updateDefaultFolder(val);
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      // Workplace Folder
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              realFolders ? 'Workplace Folder on PC' : 'Workplace Storage (this browser)',
                              style: textStyles.body.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            _isFolderManuallyEdited ? 'Custom Path' : 'Auto Selected',
                            style: textStyles.caption.copyWith(
                              color: _isFolderManuallyEdited ? colors.mainAccent : colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _folderController,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: AppFonts.monoFamily,
                                fontFamilyFallback: AppFonts.monoFallback,
                              ),
                              decoration: InputDecoration(
                                hintText: realFolders ? 'Full path of the workplace folder' : 'Name to store it under',
                                isDense: true,
                                prefixIcon: const Icon(Icons.folder_outlined, size: 18),
                              ),
                              onChanged: (_) => setState(() => _isFolderManuallyEdited = true),
                            ),
                          ),
                          if (vm.canBrowseFolders) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _isSubmitting ? null : _browseFolder,
                              icon: const Icon(Icons.folder_open, size: 16),
                              label: const Text('Browse…'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        realFolders
                            ? 'PostPilot saves all data in this folder as a single "workspace.json" file. '
                                  'If the folder already contains one, it is opened as it is.'
                            : 'The web version has no file access, so this workplace is saved in your browser. '
                                  'Use the desktop app to keep it as a real workspace.json file in a folder.',
                        style: textStyles.caption.copyWith(color: colors.secondaryText),
                      ),
                      const SizedBox(height: 20),

                      // Git Repository Connection Card
                      Material(
                        color: colors.sidebarBackground.withValues(alpha: 0.5),
                        // Not also `borderRadius:` — Material asserts (in debug builds only) that
                        // it is given a shape or a radius, never both, which crashed this dialog.
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: colors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              value: _connectGit,
                              onChanged: (val) => setState(() => _connectGit = val ?? false),
                              title: Row(
                                children: [
                                  const Icon(Icons.alt_route, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Connect Git Repository',
                                    style: textStyles.body.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                _connectGit
                                    ? 'Syncs single workspace.json directly with GitHub'
                                    : 'Optional: if unchecked, nothing is pushed to GitHub',
                                style: textStyles.caption.copyWith(color: colors.secondaryText),
                              ),
                              controlAffinity: ListTileControlAffinity.trailing,
                            ),
                            if (_connectGit) ...[
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Git Repo URL
                                    Text(
                                      'Git Repository URL',
                                      style: textStyles.caption.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _gitRepoController,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        hintText: 'https://github.com/owner/repository',
                                        isDense: true,
                                        prefixIcon: Icon(Icons.link, size: 18),
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // Branch
                                    Text('Branch', style: textStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _gitBranchController,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        hintText: 'main',
                                        isDense: true,
                                        prefixIcon: Icon(Icons.fork_right, size: 18),
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // Token Section - Classic
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'GitHub Personal Access Token (classic)',
                                            style: textStyles.caption.copyWith(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: _openClassicTokenUrl,
                                          borderRadius: BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Create Token (classic)',
                                                  style: textStyles.caption.copyWith(
                                                    color: colors.mainAccent,
                                                    fontWeight: FontWeight.w600,
                                                    decoration: TextDecoration.underline,
                                                  ),
                                                ),
                                                const SizedBox(width: 3),
                                                Icon(Icons.open_in_new, size: 12, color: colors.mainAccent),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Select "repo" scope (Full control of private repositories) when creating the classic token.',
                                      style: textStyles.caption.copyWith(fontSize: 11, color: colors.secondaryText),
                                    ),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _gitTokenController,
                                      obscureText: _obscureToken,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontFamily: AppFonts.monoFamily,
                                        fontFamilyFallback: AppFonts.monoFallback,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'ghp_...',
                                        isDense: true,
                                        prefixIcon: const Icon(Icons.key, size: 18),
                                        suffixIcon: IconButton(
                                          icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off, size: 18),
                                          onPressed: () => setState(() => _obscureToken = !_obscureToken),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colors.statusError.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.statusError.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, size: 16, color: colors.statusError),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!, style: TextStyle(color: colors.statusError, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // macOS Sheet Footer Actions
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
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: BusyLabel(busy: _isSubmitting, label: 'Create Workplace', busyLabel: 'Creating…'),
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
