import '../../../core/widgets/busy_label.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../domain/entities/import_format.dart';
import '../domain/entities/import_summary.dart';
import 'view_models/import_any_view_model.dart';

/// One paste-and-import dialog for every supported format (Postman collections and environments, Insomnia,
/// HAR, OpenAPI/Swagger, cURL, PostPilot backup). The format is detected as
/// you paste and can be overridden by hand. Returns what was imported, or null
/// if the user cancelled or the import failed.
///
/// [collectionId]/[folderId] only affect cURL commands: given, they are added
/// there; otherwise they go into a new collection.
class ImportAnyDialog extends StatefulWidget {
  final int? collectionId;
  final int? folderId;

  const ImportAnyDialog({super.key, this.collectionId, this.folderId});

  static Future<ImportSummary?> show(BuildContext context, {int? collectionId, int? folderId}) =>
      showDialog<ImportSummary>(
        context: context,
        builder: (_) => ImportAnyDialog(collectionId: collectionId, folderId: folderId),
      );

  @override
  State<ImportAnyDialog> createState() => _ImportAnyDialogState();
}

class _ImportAnyDialogState extends State<ImportAnyDialog> {
  final _controller = TextEditingController();
  late final ImportAnyViewModel _viewModel;

  /// Set when the import left things out or changed them: the dialog then stays
  /// open on that list instead of closing behind a snackbar nobody can read in time.
  ImportSummary? _result;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<ImportAnyViewModel>();
  }

  @override
  void dispose() {
    _controller.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final summary = await _viewModel.import(collectionId: widget.collectionId, folderId: widget.folderId);
    if (summary == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary.description)));
    if (summary.notes.isNotEmpty) {
      setState(() => _result = summary);
      return;
    }
    Navigator.pop(context, summary);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ImportAnyViewModel>.value(
      value: _viewModel,
      child: Consumer<ImportAnyViewModel>(
        // Esc and a barrier tap dismiss the dialog (and dispose the ViewModel)
        // even though Cancel is disabled, so block them while importing.
        builder: (context, vm, _) => PopScope(
          canPop: !vm.isImporting && _result == null,
          // On the result list, Esc and a barrier tap still hand the summary back, like Done does.
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _result != null) Navigator.pop(context, _result);
          },
          child: _result == null ? _buildForm(context, vm) : _ImportResultDialog(summary: _result!),
        ),
      ),
    );
  }

  /// What was detected, and the picker that overrides it: side by side, and one above the other on a phone, where the picker
  /// (as wide as its longest format name) leaves the detected format no room.
  Widget _formatRow(BuildContext context, ImportAnyViewModel vm) {
    final detected = _DetectedFormat(vm: vm, importsIntoNewCollection: widget.collectionId == null);
    if (MediaQuery.sizeOf(context).width < 600) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [detected, const SizedBox(height: 4), _FormatPicker(vm: vm, expanded: true)]);
    }
    return Row(children: [Expanded(child: detected), const SizedBox(width: 8), _FormatPicker(vm: vm)]);
  }

  Widget _buildForm(BuildContext context, ImportAnyViewModel vm) {
    return AlertDialog(
      title: const Text('Import'),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a Postman collection or environment, Insomnia export, HAR file, OpenAPI/Swagger document, '
              'cURL command or PostPilot backup. The format is detected for you.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 12,
              style: context.textStyles.mono.copyWith(fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Paste here'),
              onChanged: vm.setText,
            ),
            const SizedBox(height: 8),
            _formatRow(context, vm),
            if (vm.format == ImportFormat.har) _CleanUpOption(vm: vm),
            if (vm.error != null) ...[
              const SizedBox(height: 8),
              Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: vm.isImporting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: vm.canImport ? _import : null,
          child: BusyLabel(busy: vm.isImporting, label: 'Import', busyLabel: 'Importing…'),
        ),
      ],
    );
  }
}

/// What an import that left things out or changed them reports: the summary line, then one sentence
/// per skipped or changed item, so the user knows what is missing before trusting the result.
class _ImportResultDialog extends StatelessWidget {
  final ImportSummary summary;
  const _ImportResultDialog({required this.summary});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    return AlertDialog(
      title: Text(summary.notesHeading),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.description, style: textStyles.body),
            const SizedBox(height: 12),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Scrollbar(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: summary.notes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, index) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 8),
                          child: Icon(Icons.info_outline, size: 14, color: colors.secondaryText),
                        ),
                        Expanded(child: SelectableText(summary.notes[index], style: textStyles.caption)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context, summary), child: const Text('Done'))],
    );
  }
}


/// "Clean up (recommended)": what a HAR recording gets before it becomes a collection. Off, every call is imported as recorded.
class _CleanUpOption extends StatelessWidget {
  final ImportAnyViewModel vm;
  const _CleanUpOption({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: CheckboxListTile(
        value: vm.cleanHar,
        onChanged: vm.isImporting ? null : (value) => vm.setCleanHar(value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Clean up (recommended)'),
        subtitle: Text(
          'Drops static files, analytics, trackers and CORS preflights. Repeated calls become one request, with ids in the path as '
          'variables, in folders by the first path segment. Tokens and keys become empty secret variables of a new environment. '
          'Off: every call is imported exactly as recorded.',
          style: context.textStyles.caption,
        ),
      ),
    );
  }
}

class _DetectedFormat extends StatelessWidget {
  final ImportAnyViewModel vm;
  final bool importsIntoNewCollection;
  const _DetectedFormat({required this.vm, required this.importsIntoNewCollection});

  @override
  Widget build(BuildContext context) {
    final caption = context.textStyles.caption;
    if (!vm.hasText) return Text('Nothing pasted yet', style: caption.copyWith(color: context.colors.secondaryText));
    final format = vm.format;
    if (format == ImportFormat.unknown) {
      return Row(
        children: [
          Icon(Icons.help_outline, size: 16, color: context.colors.secondaryText),
          const SizedBox(width: 6),
          Expanded(child: Text("Couldn't recognise this format. Pick one on the right to try anyway.", style: caption)),
        ],
      );
    }
    final intoNew = format == ImportFormat.curl && importsIntoNewCollection ? ' (into a new collection)' : '';
    return Row(
      children: [
        Icon(Icons.check_circle_outline, size: 16, color: context.colors.statusSuccess),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${vm.selected == null ? 'Detected' : 'Importing as'}: ${format.label}$intoNew',
            style: caption,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// `unknown` doubles as the "Auto-detect" entry: a null dropdown value would
/// show the hint instead of a selected item.
class _FormatPicker extends StatelessWidget {
  final ImportAnyViewModel vm;

  /// Fills the width it is given, with long names cut short, instead of being as wide as the longest name.
  final bool expanded;
  const _FormatPicker({required this.vm, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ImportFormat>(
      value: vm.selected ?? ImportFormat.unknown,
      isDense: true,
      isExpanded: expanded,
      items: [
        const DropdownMenuItem(value: ImportFormat.unknown, child: Text('Auto-detect', overflow: TextOverflow.ellipsis)),
        for (final format in ImportFormat.values)
          if (format != ImportFormat.unknown) DropdownMenuItem(value: format, child: Text(format.label, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: vm.isImporting ? null : (format) => vm.selectFormat(format == ImportFormat.unknown ? null : format),
    );
  }
}
