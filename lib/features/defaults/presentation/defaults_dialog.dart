import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/enums/auth_type.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../request_builder/domain/entities/request_auth.dart';
import '../../request_builder/presentation/view_models/variable_scope.dart';
import '../../request_builder/presentation/widgets/auth_editor.dart';
import '../../request_builder/presentation/widgets/key_value_editor.dart';
import '../../scripting/presentation/widgets/assertions_editor.dart';
import '../../scripting/presentation/widgets/extractors_editor.dart';
import '../../shell/presentation/shell_view_model.dart';
import 'view_models/defaults_view_model.dart';
import 'widgets/default_variables_editor.dart';
import 'widgets/inherited_headers_list.dart';
import 'widgets/origin_chip.dart';

/// Opens the defaults of a collection ([folderId] null) or of one of its folders: the headers, auth,
/// variables and tests every request below passes through. What they mean, outermost level first
/// (the collection, then each folder from the top one down, then the request itself):
///
///  * Headers: a request or an inner folder replaces an inherited header of the same name (case is
///    ignored) and can switch one off with a disabled entry of that name.
///  * Auth: a request set to "Inherit from parent" takes the nearest folder that sets an auth, else
///    the collection's. A folder's "Inherit from parent" sets none; its "No Auth" is a setting too.
///  * Variables: data variables of a run, then the active environment, then folder variables
///    (innermost folder first), then the collection's, then globals.
///  * Tests: the collection's, then each folder's from the outermost, before the request's own.
///
/// The edits are written together by Save, nothing before.
Future<void> showDefaultsDialog(BuildContext context, {required int collectionId, int? folderId}) =>
    ToolDialog.show<void>(
      context,
      (_) => DefaultsDialog(collectionId: collectionId, folderId: folderId),
      barrierDismissible: false,
    );

/// The defaults of the collection of the open request (the first collection when no tab is open),
/// for the command palette.
Future<void> showCurrentCollectionDefaults(BuildContext context) async {
  final shell = context.read<ShellViewModel>();
  final collections = context.read<CollectionsViewModel>();
  final location = await shell.selectedRequestLocation();
  final collectionId = location?.collectionId ?? collections.collections.firstOrNull?.id;
  if (!context.mounted) return;
  if (collectionId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('There is no collection yet: create one first, then set its defaults')),
    );
    return;
  }
  await showDefaultsDialog(context, collectionId: collectionId);
}

class DefaultsDialog extends StatefulWidget {
  final int collectionId;
  final int? folderId;

  /// Replaces the one the injector builds, for a test.
  @visibleForTesting
  final DefaultsViewModel? viewModel;

  /// Replaces the variable scope the fields colour their `{{tokens}}` with, for a test.
  @visibleForTesting
  final VariableScope? variableScope;

  const DefaultsDialog({super.key, required this.collectionId, this.folderId, this.viewModel, this.variableScope});

  @override
  State<DefaultsDialog> createState() => _DefaultsDialogState();
}

class _DefaultsDialogState extends State<DefaultsDialog> {
  late final DefaultsViewModel _viewModel;
  late final VariableScope? _scope;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? locator<DefaultsViewModel>();
    _viewModel.load(collectionId: widget.collectionId, folderId: widget.folderId);
    // The `{{tokens}}` of the fields are coloured and explained like in a request, with the folder's own variables.
    _scope = widget.variableScope ?? (locator.isRegistered<VariableScope>() ? locator<VariableScope>() : null);
    _scope?.bindCollection(widget.collectionId, folderId: widget.folderId);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _scope?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final label = _viewModel.isFolder ? 'Folder defaults saved' : 'Collection defaults saved';
    if (!await _viewModel.save() || !mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(label)));
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits, and any token you fetched, have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if ((discard ?? false) && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final dialog = ChangeNotifierProvider<DefaultsViewModel>.value(
      value: _viewModel,
      child: Consumer<DefaultsViewModel>(
        builder: (context, vm, _) => PopScope(
          // Not dismissible by a scrim click or Esc with edits in it: they live only in memory until Save.
          canPop: !vm.hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmDiscard();
          },
          child: ToolDialog(
            icon: Icons.tune,
            title: vm.isFolder ? 'Folder defaults' : 'Collection defaults',
            subtitle: _subtitle(vm),
            width: 860,
            height: 640,
            footerLeading: _Footer(vm: vm),
            actions: [
              TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: vm.isLoading || vm.isSaving || !vm.hasUnsavedChanges ? null : _save,
                child: BusyLabel(busy: vm.isSaving, label: 'Save', busyLabel: 'Saving…'),
              ),
            ],
            child: vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ToolTabs(
                    tabs: [
                      ToolTab(label: 'Headers', icon: Icons.view_list_outlined, child: _HeadersTab(vm: vm)),
                      ToolTab(label: 'Auth', icon: Icons.lock_outline, child: _AuthTab(vm: vm)),
                      ToolTab(label: 'Variables', icon: Icons.data_object, child: _VariablesTab(vm: vm)),
                      ToolTab(label: 'Tests', icon: Icons.fact_check_outlined, child: _TestsTab(vm: vm)),
                    ],
                  ),
          ),
        ),
      ),
    );
    return scope == null ? dialog : ChangeNotifierProvider<VariableScope>.value(value: scope, child: dialog);
  }

  String _subtitle(DefaultsViewModel vm) {
    if (vm.isFolder) return '${vm.collectionName}  ›  ${vm.folderName ?? 'folder'}';
    return vm.collectionName;
  }
}

class _Footer extends StatelessWidget {
  final DefaultsViewModel vm;
  const _Footer({required this.vm});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = context.textStyles.caption;
    if (vm.errorMessage != null) {
      return Text(vm.errorMessage!, style: caption.copyWith(color: colors.statusError), maxLines: 3);
    }
    return Text(
      vm.hasUnsavedChanges ? 'Not saved yet.' : 'Everything is saved.',
      style: caption.copyWith(color: colors.secondaryText),
    );
  }
}

/// A tab body: the help text, then what the level inherits, then the editor.
class _TabBody extends StatelessWidget {
  final List<Widget> children;
  const _TabBody({required this.children});

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: children);
}

class _HeadersTab extends StatelessWidget {
  final DefaultsViewModel vm;
  const _HeadersTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    final target = vm.isFolder ? 'this folder' : 'this collection';
    return _TabBody(
      children: [
        InfoBanner(
          title: 'Sent with every request in $target',
          message: 'Headers are added in this order: the collection, each folder from the outermost, then the request. '
              'A header with the same name (letter case is ignored) from a more specific level replaces the one above. '
              'To switch an inherited header off for everything below, add it here with the same name and untick it.',
        ),
        const SizedBox(height: 12),
        if (vm.above.headers.isNotEmpty) ...[
          _SectionTitle('Inherited from above'),
          InheritedHeadersList(headers: vm.above.headers, own: vm.headers),
          const SizedBox(height: 16),
          _SectionTitle(vm.isFolder ? 'Headers of this folder' : 'Headers of this collection'),
        ],
        KeyValueEditor(items: vm.headers, onChanged: vm.setHeaders),
      ],
    );
  }
}

class _AuthTab extends StatelessWidget {
  final DefaultsViewModel vm;
  const _AuthTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    final inheritedAuth = vm.above.auth;
    final inheritedOrigin = vm.above.authOrigin;
    return _TabBody(
      children: [
        InfoBanner(
          title: vm.isFolder ? 'Auth of this folder' : 'Auth of this collection',
          message: vm.isFolder
              ? 'A request set to "Inherit from parent" uses the nearest folder above it that sets an auth, '
                  'and the collection\'s when none does. Choose "Inherit from parent" here to leave it to the levels '
                  'above; "No Auth" switches the inherited auth off for everything in this folder.'
              : 'A request set to "Inherit from parent" uses this auth, unless a folder above it sets its own: '
                  'the nearest folder wins.',
        ),
        const SizedBox(height: 12),
        if (vm.isFolder && (vm.auth == null) && inheritedOrigin != null && inheritedAuth != null) ...[
          Row(
            children: [
              Text(
                inheritedAuth.type == AuthType.none
                    ? 'Inherits: no auth, '
                    : 'Inherits ${inheritedAuth.type.label}, ',
                style: context.textStyles.body,
              ),
              OriginChip(origin: inheritedOrigin),
            ],
          ),
          const SizedBox(height: 12),
        ],
        AuthEditor(
          auth: vm.auth ?? const RequestAuth(type: AuthType.inherit),
          allowInherit: vm.isFolder,
          collectionId: vm.collectionId,
          folderId: vm.folderId,
          onChanged: vm.setAuth,
        ),
      ],
    );
  }
}

class _VariablesTab extends StatelessWidget {
  final DefaultsViewModel vm;
  const _VariablesTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    return _TabBody(
      children: [
        InfoBanner(
          title: vm.isFolder ? 'Variables of this folder' : 'Variables of this collection',
          message: vm.isFolder
              ? 'Use them as {{name}} in the requests of this folder and its sub-folders. A request sees them '
                  'after the active environment: the order is a run\'s data row, the environment, the folders '
                  '(innermost first), the collection, the globals. A secret\'s value is hidden and kept out of shared workspace files.'
              : 'The same variables as "Variables" in the collection menu, saved with the rest here. Folders can '
                  'define their own, which win over these; the active environment wins over both.',
        ),
        const SizedBox(height: 12),
        DefaultVariablesEditor(items: vm.variables, onChanged: vm.setVariables, allowSecret: vm.isFolder),
      ],
    );
  }
}

class _TestsTab extends StatelessWidget {
  final DefaultsViewModel vm;
  const _TestsTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    return _TabBody(
      children: [
        InfoBanner(
          title: vm.isFolder ? 'Tests of this folder' : 'Tests of this collection',
          message: 'Run for every request below, before the request\'s own: the collection\'s first, then each folder\'s '
              'from the outermost. Their results say where they come from. Values, paths and header names can use {{name}}.',
        ),
        const SizedBox(height: 12),
        if (vm.above.tests.isNotEmpty) ...[
          _SectionTitle('Inherited from above'),
          for (final level in vm.above.tests)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  OriginChip(origin: level.origin),
                  const SizedBox(width: 8),
                  Text(
                    '${level.assertions.length} check${level.assertions.length == 1 ? '' : 's'}, '
                    '${level.extractors.length} variable extractor${level.extractors.length == 1 ? '' : 's'}',
                    style: textStyles.caption.copyWith(color: colors.secondaryText),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
        Text('Assertions', style: textStyles.heading),
        const SizedBox(height: 8),
        AssertionsEditor(items: vm.assertions, onChanged: vm.setAssertions),
        const SizedBox(height: 24),
        Text('Extract variables', style: textStyles.heading),
        Text(
          'Copy a value from the response into a variable so the next request can use {{name}}.',
          style: textStyles.caption.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: 8),
        ExtractorsEditor(items: vm.extractors, onChanged: vm.setExtractors),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: context.textStyles.caption.copyWith(
            color: context.colors.secondaryText,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
      );
}
