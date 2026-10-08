import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/utils/file_download.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/code_block.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/domain/repositories/collection_repository.dart';
import '../../environments/domain/repositories/environment_repository.dart';
import '../../environments/domain/repositories/global_variable_repository.dart';
import '../../safety/data/safety_prefs.dart';
import '../../workplace/presentation/view_models/workplace_view_model.dart';
import '../data/ci_workflow_writer.dart';
import '../domain/entities/ci_options.dart';
import 'ci_setup_view_model.dart';

/// "Set up CI": picks what the pipeline runs and shows the GitHub Actions workflow (and the GitLab CI job and a shell
/// script) it makes, ready to copy or to save into the repository of the workplace.
class CiSetupDialog extends StatefulWidget {
  /// The collection the dialog was opened from; the workflow then runs only that collection (it can be changed).
  final String? collectionName;

  /// Replaces the one the injector's repositories build, for a test.
  @visibleForTesting
  final CiSetupViewModel? viewModel;

  const CiSetupDialog({super.key, this.collectionName, this.viewModel});

  static Future<void> show(BuildContext context, {String? collectionName}) =>
      ToolDialog.show(context, (_) => CiSetupDialog(collectionName: collectionName));

  @override
  State<CiSetupDialog> createState() => _CiSetupDialogState();
}

class _CiSetupDialogState extends State<CiSetupDialog> {
  late final CiSetupViewModel _vm;
  final _path = TextEditingController();
  final _cron = TextEditingController();
  final _ref = TextEditingController(text: 'main');

  @override
  void initState() {
    super.initState();
    _vm = widget.viewModel ?? _build();
    _vm.load(collectionName: widget.collectionName).then((_) {
      if (!mounted) return;
      _path.text = _vm.options.workspacePath;
    });
  }

  CiSetupViewModel _build() {
    final workplace = context.read<WorkplaceViewModel>();
    final active = workplace.activeWorkplace;
    return CiSetupViewModel(
      environments: locator<EnvironmentRepository>(),
      globals: locator<GlobalVariableRepository>(),
      collections: locator<CollectionRepository>(),
      writer: createCiWorkflowWriter(),
      project: CiProject(
        folderPath: active != null && workplace.repository.usesRealFolders ? active.folderPath : null,
        name: active?.name ?? '',
      ),
      productionWords: locator.isRegistered<SafetyPrefs>() ? locator<SafetyPrefs>().extraWords : const [],
    );
  }

  @override
  void dispose() {
    _path.dispose();
    _cron.dispose();
    _ref.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save({bool overwrite = false}) async {
    final result = await _vm.saveToRepository(overwrite: overwrite);
    if (!mounted) return;
    if (result is WorkflowNeedsConfirmation) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace the existing workflow?'),
          content: Text(
            '${result.path} already exists and is different from this one: it was edited by hand, or made with other choices. '
            'Saving replaces it. Copy what you need from it first if you are not sure.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace it')),
          ],
        ),
      );
      if (replace == true && mounted) await _save(overwrite: true);
    }
  }

  /// A browser cannot write into the repository: the file of the chosen kind is downloaded for the person to commit.
  Future<void> _download() async {
    final text = _vm.text;
    if (text == null) return;
    final name = _vm.target.fileName.split('/').last;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await downloadFile(fileName: name, bytes: Uint8List.fromList(utf8.encode(text)), mimeType: 'text/plain');
      messenger.showSnackBar(SnackBar(content: Text('Downloaded $name. Put it at ${_vm.target.fileName} in your repository.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't make the download: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final github = _vm.target == CiTarget.github;
        return ToolDialog(
          icon: Icons.rocket_launch_outlined,
          title: 'Set up CI',
          subtitle: 'Run this workspace on every push and on a schedule, and see what broke',
          width: 1120,
          height: 740,
          footerLeading: _footerText(context),
          actions: [
            if (!_vm.canWriteFiles)
              FilledButton.icon(
                onPressed: _vm.text == null ? null : _download,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text('Download ${_vm.target.fileName.split('/').last}'),
              )
            else if (github)
              FilledButton(
                onPressed: _vm.canSaveToRepository ? _save : null,
                child: BusyLabel(
                  busy: _vm.isSaving,
                  label: 'Save to .github/workflows/',
                  busyLabel: 'Saving…',
                  icon: Icons.save_outlined,
                ),
              ),
          ],
          child: _vm.isLoading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 860;
                    final form = _Form(vm: _vm, path: _path, cron: _cron, ref: _ref);
                    final preview = _Preview(vm: _vm);
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 380, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: form)),
                          VerticalDivider(width: 1, color: context.colors.border),
                          Expanded(child: Padding(padding: const EdgeInsets.all(16), child: preview)),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [form, const SizedBox(height: 8), SizedBox(height: 420, child: preview)],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget? _footerText(BuildContext context) {
    final colors = context.colors;
    final message = _vm.saveMessage;
    if (message != null) {
      return Text(
        message,
        style: context.textStyles.caption.copyWith(color: _vm.saveFailed ? colors.statusError : colors.statusSuccess),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (_vm.target != CiTarget.github) return null;
    final blocker = _vm.saveBlocker;
    if (blocker != null) {
      return Text(blocker, style: context.textStyles.caption.copyWith(color: colors.secondaryText), maxLines: 3, overflow: TextOverflow.ellipsis);
    }
    return Text(
      'Saves into the repository that holds this workplace. A different file already there is never replaced without asking.',
      style: context.textStyles.caption.copyWith(color: colors.secondaryText),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The choices.
class _Form extends StatelessWidget {
  final CiSetupViewModel vm;
  final TextEditingController path;
  final TextEditingController cron;
  final TextEditingController ref;
  const _Form({required this.vm, required this.path, required this.cron, required this.ref});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final o = vm.options;
    final problems = vm.problems;
    final scheduled = o.scheduled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoBanner(
          title: 'Why Flutter is installed',
          message: 'PostPilot is a Flutter project: "flutter pub get" needs the Flutter SDK, even though its command line is plain Dart. '
              'The workflow installs it with subosito/flutter-action; the first run is slower, later ones use a cache.',
        ),
        const SizedBox(height: 16),
        ToolSection(
          title: 'What to run',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
                key: ValueKey('env-${o.environment}'),
                initialValue: o.environment,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Environment'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No environment')),
                  for (final e in vm.environments) DropdownMenuItem<String?>(value: e.name, child: Text(e.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: vm.setEnvironment,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('col-${o.collection}'),
                initialValue: o.collection,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Collection', errorText: problems['collection']),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All collections')),
                  for (final name in vm.collectionNames) DropdownMenuItem<String?>(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: vm.setCollection,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: path,
                decoration: InputDecoration(
                  labelText: 'Workspace file in the repository',
                  errorText: problems['workspacePath'],
                  errorMaxLines: 3,
                  helperText: _pathHelp(),
                  helperMaxLines: 3,
                ),
                onChanged: vm.setWorkspacePath,
              ),
            ],
          ),
        ),
        ToolSection(
          title: 'When',
          hint: 'On every push and pull request, and from the Actions tab, always. A schedule makes it a monitor.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<CiSchedulePreset>(
                key: ValueKey('schedule-${o.schedule.name}'),
                initialValue: o.schedule,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Schedule'),
                items: [for (final s in CiSchedulePreset.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: (s) => vm.setSchedule(s ?? CiSchedulePreset.none),
              ),
              if (o.schedule == CiSchedulePreset.custom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: cron,
                  style: context.textStyles.mono,
                  decoration: InputDecoration(
                    labelText: 'Cron expression (UTC)',
                    hintText: '17 6 * * *',
                    errorText: problems['cron'],
                    errorMaxLines: 4,
                  ),
                  onChanged: vm.setCustomCron,
                ),
              ],
              if (scheduled && o.schedule != CiSchedulePreset.custom)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Cron: ${o.cron} (UTC)', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                ),
            ],
          ),
        ),
        ToolSection(
          title: 'Options',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Check(
                value: o.failOnSkip,
                onChanged: vm.setFailOnSkip,
                title: 'Fail when a request is skipped',
                subtitle: 'For example an OAuth 2.0 request that needs someone to sign in.',
              ),
              _Check(
                value: o.bail,
                onChanged: vm.setBail,
                title: 'Stop at the first failure',
                subtitle: 'The rest of the requests do not run.',
              ),
              _Check(
                value: o.openIssueOnFailure && scheduled,
                onChanged: scheduled ? vm.setOpenIssue : null,
                title: 'Open a GitHub issue when a scheduled run fails',
                subtitle: scheduled
                    ? 'One issue, found by its label "postpilot-monitor"; later failures comment on it.'
                    : 'Choose a schedule first.',
              ),
              _Check(
                value: o.allowProduction,
                onChanged: vm.setAllowProduction,
                title: 'Allow production',
                subtitle: 'Off: requests that change data are refused when the environment looks like production.',
                danger: true,
              ),
              if (o.allowProduction)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: InfoBanner(
                    kind: BannerKind.error,
                    title: 'Production can be changed by every run',
                    message: 'With this on, each push and pull request (and each scheduled run) may send POST, PUT, PATCH and DELETE '
                        'requests to production. Leave it off unless that is exactly what you want.',
                  ),
                )
              else if (vm.environmentLooksProduction)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: InfoBanner(
                    kind: BannerKind.warning,
                    message: 'This environment looks like production. The lock stays on: a run that includes a request which changes data '
                        'is refused as a whole (exit code 2). Pick a read-only collection to monitor it.',
                  ),
                ),
            ],
          ),
        ),
        ToolSection(
          title: 'PostPilot version',
          child: TextField(
            controller: ref,
            decoration: InputDecoration(
              labelText: 'Branch, tag or commit',
              errorText: problems['postpilotRef'],
              errorMaxLines: 3,
              helperText: 'main follows the newest PostPilot. Pin a tag or commit for runs that never change under you.',
              helperMaxLines: 3,
            ),
            onChanged: vm.setPostpilotRef,
          ),
        ),
        _Secrets(vm: vm),
      ],
    );
  }

  String _pathHelp() {
    final root = vm.repositoryRoot;
    if (root == null) return 'Relative to the root of the repository. This workplace is not inside one yet.';
    return vm.workspaceFileFound
        ? 'Found in the repository. Commit and push it: the workflow reads it from there.'
        : 'This workplace has no workspace.json yet: it is written when you save a change.';
  }
}

class _Check extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String subtitle;
  final bool danger;
  const _Check({required this.value, required this.onChanged, required this.title, required this.subtitle, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      activeColor: danger ? colors.statusError : null,
      title: Text(title, style: danger ? TextStyle(color: colors.statusError, fontWeight: FontWeight.w600) : null),
      subtitle: Text(subtitle, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
    );
  }
}

/// The secrets the pipeline needs, by name.
class _Secrets extends StatelessWidget {
  final CiSetupViewModel vm;
  const _Secrets({required this.vm});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final secrets = vm.options.secrets;
    return ToolSection(
      title: 'Secrets to create',
      hint: 'Secret values never go into the file: only their names do. Create one secret per line in the CI system.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (secrets.isEmpty)
            Text(
              'The chosen environment has no secret variables.',
              style: context.textStyles.caption.copyWith(color: colors.secondaryText),
            )
          else
            for (final s in secrets)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Flexible(child: SelectableText(s.secretName, style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'value of ${s.variable}',
                        style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          for (final why in vm.skippedSecrets)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(why, style: context.textStyles.caption.copyWith(color: colors.statusWarning)),
            ),
        ],
      ),
    );
  }
}

/// The generated file, with a switch between the three kinds.
class _Preview extends StatelessWidget {
  final CiSetupViewModel vm;
  const _Preview({required this.vm});

  @override
  Widget build(BuildContext context) {
    final text = vm.text;
    final problems = vm.problems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chips wrap on a narrow screen where a segmented button would overflow.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in CiTarget.values)
              ChoiceChip(label: Text(t.label), selected: vm.target == t, onSelected: (_) => vm.setTarget(t)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: text == null
              ? SingleChildScrollView(
                  child: InfoBanner(
                    kind: BannerKind.warning,
                    title: 'Fix this to see the file',
                    message: problems.values.join('\n'),
                  ),
                )
              : CodeBlock(text: text, label: vm.target.fileName, copyMessage: 'Copied'),
        ),
      ],
    );
  }
}
