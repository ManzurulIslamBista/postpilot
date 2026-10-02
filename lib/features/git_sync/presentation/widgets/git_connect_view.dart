import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/git_operation_view_model.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_token_section.dart';
import 'git_widgets.dart';

class GitConnectView extends StatefulWidget {
  const GitConnectView({super.key});

  @override
  State<GitConnectView> createState() => _GitConnectViewState();
}

class _GitConnectViewState extends State<GitConnectView> {
  final _repository = TextEditingController();
  final _branch = TextEditingController(text: GitOperationViewModel.defaultBranch);
  final _folder = TextEditingController();
  bool _includeSecrets = false;

  @override
  void dispose() {
    _repository.dispose();
    _branch.dispose();
    _folder.dispose();
    super.dispose();
  }

  Future<void> _connect(GitSyncViewModel vm) => vm.connect(
        repository: _repository.text,
        branch: _branch.text,
        basePath: _folder.text,
        includeSecrets: _includeSecrets,
      );

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    final repositoryError = GitOperationViewModel.repositoryError(_repository.text);
    final canConnect = !vm.isBusy && _repository.text.trim().isNotEmpty && repositoryError == null;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Keep this collection in a folder of a GitHub repository: commit and push your changes, '
                "pull your teammates' changes, and resolve conflicts here.",
                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
              ),
              const SizedBox(height: 16),
              GitTokenSection(
                hasToken: vm.hasToken,
                verifiedLogin: vm.verifiedLogin,
                isBusy: vm.isBusy,
                onSave: vm.saveToken,
                onOpenLink: vm.openUrl,
              ),
              const Divider(height: 32),
              TextField(
                controller: _repository,
                enabled: !vm.isBusy,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Repository',
                  hintText: 'owner/repo or https://github.com/owner/repo',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  errorText: repositoryError,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _branch,
                enabled: !vm.isBusy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  helperText: "Leave empty to use the repository's default branch.",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _folder,
                enabled: !vm.isBusy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Folder in repository (optional)',
                  hintText: 'apis/billing',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  helperText: 'Leave empty to keep the collection at the repository root. '
                      'Use a folder to keep several collections in one repository.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include credentials in commits'),
                subtitle: const Text(gitCredentialsOffHint),
                value: _includeSecrets,
                onChanged: vm.isBusy ? null : (value) => setState(() => _includeSecrets = value),
              ),
              const GitCredentialsWarning(),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: canConnect ? () => _connect(vm) : null,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Connect'),
            ),
          ),
        ),
      ],
    );
  }
}
