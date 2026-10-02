import '../../../../core/widgets/busy_label.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/usecases/git_discover_usecase.dart';
import '../view_models/git_clone_view_model.dart';
import '../view_models/git_operation_view_model.dart';
import 'git_token_section.dart';
import 'git_widgets.dart';

class GitClonePanel extends StatefulWidget {
  final ValueChanged<int> onCloned;
  const GitClonePanel({super.key, required this.onCloned});

  @override
  State<GitClonePanel> createState() => _GitClonePanelState();
}

class _GitClonePanelState extends State<GitClonePanel> {
  final _repository = TextEditingController();
  final _branch = TextEditingController(text: GitOperationViewModel.defaultBranch);

  @override
  void dispose() {
    _repository.dispose();
    _branch.dispose();
    super.dispose();
  }

  void _inputChanged(GitCloneViewModel vm) {
    vm.resetSearch();
    setState(() {});
  }

  Future<void> _clone(GitCloneViewModel vm) async {
    final collectionId = await vm.clone();
    if (collectionId != null && mounted) widget.onCloned(collectionId);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitCloneViewModel>();
    final repositoryError = GitOperationViewModel.repositoryError(_repository.text);
    final canSearch = !vm.isBusy && _repository.text.trim().isNotEmpty && repositoryError == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GitPanelTitle(
          title: 'Clone from Git',
          subtitle: 'Create a new collection from a GitHub repository',
          busyLabel: vm.busyLabel,
          canClose: vm.canClose,
        ),
        GitBusyBar(busy: vm.isBusy),
        if (vm.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: GitBanner(message: vm.errorMessage!, kind: GitBannerKind.error),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                onChanged: (_) => _inputChanged(vm),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _branch,
                enabled: !vm.isBusy,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Branch'),
                onChanged: (_) => _inputChanged(vm),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: canSearch ? () => vm.discover(repository: _repository.text, branch: _branch.text) : null,
                  child: BusyLabel(
                    busy: vm.isBusy && (vm.busyLabel?.startsWith('Searching') ?? false),
                    icon: Icons.search,
                    label: 'Find collections',
                    busyLabel: 'Searching…',
                  ),
                ),
              ),
              if (vm.hasSearched) ...[const SizedBox(height: 16), _Results(vm: vm)],
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: vm.canClose ? () => Navigator.pop(context) : null, child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: vm.canClone ? () => _clone(vm) : null,
                child: BusyLabel(
                  busy: vm.isBusy && (vm.busyLabel?.startsWith('Cloning') ?? false),
                  icon: Icons.download,
                  label: 'Clone',
                  busyLabel: 'Cloning…',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  final GitCloneViewModel vm;
  const _Results({required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.found.isEmpty) {
      return const GitBanner(
        kind: GitBannerKind.warning,
        message:
            'No PostPilot collections were found on this branch. Check the repository and branch, or push a '
            'collection to it first with "Git sync…".',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          vm.found.length == 1 ? '1 collection found' : '${vm.found.length} collections found',
          style: context.textStyles.caption.copyWith(color: context.colors.secondaryText, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        RadioGroup<DiscoveredCollection>(
          groupValue: vm.selected,
          onChanged: (collection) {
            if (collection != null && !vm.isBusy) vm.select(collection);
          },
          child: Column(
            children: [
              for (final collection in vm.found)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Radio<DiscoveredCollection>(value: collection),
                  title: Text(collection.name.isEmpty ? '(unnamed)' : collection.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    collection.basePath.isEmpty ? 'Repository root' : collection.basePath,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
                  ),
                  onTap: vm.isBusy ? null : () => vm.select(collection),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
