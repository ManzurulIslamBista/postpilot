import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../request_flow/presentation/widgets/flow_section.dart';
import '../../../settings/presentation/widgets/synced_text_field.dart';
import '../../domain/entities/cleanup_settings.dart';
import '../view_models/cleanup_section_view_model.dart';

/// "Clean up what this request creates": the section of a request's Settings tab that says where the created id is in
/// the response and how the record is undone. Off, it is a header with one line; a request that looks like a create
/// (an Odoo `create`, a POST whose answer holds an id) also gets a banner that switches it on in one click. Designed to
/// sit inside the page's scroll view, so it lays out as a plain Column.
///
/// The setting itself ([cleanup]) belongs to the Settings tab, which saves every [onChanged].
class CleanupSection extends StatefulWidget {
  final int requestId;
  final CleanupSettings cleanup;
  final ValueChanged<CleanupSettings> onChanged;

  /// Replaces the one from the service locator, for a test.
  @visibleForTesting
  final CleanupSectionViewModel? viewModel;

  const CleanupSection({super.key, required this.requestId, required this.cleanup, required this.onChanged, this.viewModel});

  @override
  State<CleanupSection> createState() => _CleanupSectionState();
}

class _CleanupSectionState extends State<CleanupSection> {
  late final CleanupSectionViewModel _viewModel;

  /// Whether the id is named by a path: true from the start for a request that has one, and while the person has chosen it
  /// but not typed it yet.
  late bool _byPath = widget.cleanup.idPath.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? locator<CleanupSectionViewModel>();
    _viewModel.load(widget.requestId);
  }

  @override
  void didUpdateWidget(covariant CleanupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) {
      _byPath = widget.cleanup.idPath.isNotEmpty;
      _viewModel.load(widget.requestId);
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _change(CleanupSettings next) => widget.onChanged(next);

  void _setByPath(bool value) {
    setState(() => _byPath = value);
    // Back to automatic forgets the path.
    if (!value && widget.cleanup.idPath.isNotEmpty) _change(widget.cleanup.copyWith(idPath: ''));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        // Quiet until it is known: a section that flashes a spinner in the middle of the Settings tab would be noise.
        if (_viewModel.isLoading || _viewModel.request == null) return const SizedBox.shrink();
        final cleanup = widget.cleanup;
        final suggestion = _viewModel.suggestionFor(cleanup);
        final muted = context.textStyles.caption.copyWith(color: context.colors.secondaryText);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            if (suggestion != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InfoBanner(
                  key: const ValueKey('cleanup-suggestion'),
                  title: suggestion.title,
                  message: 'The records it creates can be deleted again once a run is done.',
                  trailing: TextButton(
                    key: const ValueKey('cleanup-use-suggestion'),
                    onPressed: () {
                      setState(() => _byPath = suggestion.settings.idPath.isNotEmpty);
                      _change(suggestion.settings.copyWith(request: cleanup.request));
                    },
                    child: const Text('Use it'),
                  ),
                ),
              ),
            FlowSection(
              key: const ValueKey('cleanup-section'),
              title: 'Clean up what this request creates',
              summary: cleanup.summary,
              enabled: cleanup.enabled,
              onToggle: (on) => _change(cleanup.copyWith(enabled: on)),
              child: _Editor(
                cleanup: cleanup,
                byPath: _byPath,
                undoRequests: _viewModel.undoRequests,
                onByPath: _setByPath,
                onChanged: _change,
              ),
            ),
            Text(
              'Kept until you close PostPilot: nothing about the records is saved. Deleting goes through the normal send, '
              'so the production lock asks first.',
              style: muted,
            ),
          ],
        );
      },
    );
  }
}

class _Editor extends StatelessWidget {
  final CleanupSettings cleanup;
  final bool byPath;
  final List<String> undoRequests;
  final ValueChanged<bool> onByPath;
  final ValueChanged<CleanupSettings> onChanged;

  const _Editor({required this.cleanup, required this.byPath, required this.undoRequests, required this.onByPath, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final muted = context.textStyles.caption.copyWith(color: context.colors.secondaryText);
    final label = context.textStyles.body.copyWith(fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where is the created id?', style: label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: const ValueKey('cleanup-id-auto'),
              label: const Text('Find it automatically'),
              selected: !byPath,
              onSelected: (_) => onByPath(false),
            ),
            ChoiceChip(
              key: const ValueKey('cleanup-id-path'),
              label: const Text('At this JSON path'),
              selected: byPath,
              onSelected: (_) => onByPath(true),
            ),
          ],
        ),
        if (byPath) ...[
          const SizedBox(height: 8),
          SyncedTextField(
            key: const ValueKey('cleanup-id-path-field'),
            value: cleanup.idPath,
            labelText: 'JSON path of the id',
            hintText: r'data.id   or   $.result[0].id',
            onChanged: (text) => onChanged(cleanup.copyWith(idPath: text)),
          ),
        ],
        const FlowHint(
          'Automatic reads an Odoo create (an id or a list of ids), then id, data.id, result.id and result of a REST answer.',
        ),
        const SizedBox(height: 14),
        Text('How is it undone?', style: label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final undo in CleanupUndo.values)
              ChoiceChip(
                key: ValueKey('cleanup-undo-${undo.name}'),
                label: Text(undo.label),
                selected: cleanup.undo == undo,
                onSelected: (_) => onChanged(cleanup.copyWith(undo: undo)),
              ),
          ],
        ),
        FlowHint(_undoHint(cleanup.undo)),
        if (cleanup.undo == CleanupUndo.request) ...[
          const SizedBox(height: 8),
          _UndoRequestPicker(cleanup: cleanup, undoRequests: undoRequests, onChanged: onChanged),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'The delete is sent with {{created.id}}, {{created.ids}}, {{created.count}} and one {{created.<field>}} '
            'for each field of the answer.',
            style: muted,
          ),
        ),
      ],
    );
  }

  static String _undoHint(CleanupUndo undo) => switch (undo) {
        CleanupUndo.auto => 'An Odoo create is undone with unlink; any other POST with a DELETE of this URL plus the id.',
        CleanupUndo.odooUnlink =>
          'Sends unlink with the created ids to the same Odoo server, with this request\'s headers and authentication.',
        CleanupUndo.restDelete => 'Sends DELETE <this URL>/<id> for each created record, with this request\'s authentication.',
        CleanupUndo.request => 'Sends another request of this collection, once for each create.',
      };
}

class _UndoRequestPicker extends StatelessWidget {
  final CleanupSettings cleanup;
  final List<String> undoRequests;
  final ValueChanged<CleanupSettings> onChanged;

  const _UndoRequestPicker({required this.cleanup, required this.undoRequests, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final chosen = cleanup.request.trim();
    final options = [...undoRequests, if (chosen.isNotEmpty && !undoRequests.contains(chosen)) chosen];
    if (options.isEmpty) {
      return Text(
        'This collection has no other request to send.',
        style: context.textStyles.caption.copyWith(color: context.colors.statusWarning),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('cleanup-undo-request-$chosen-${options.length}'),
      initialValue: chosen.isEmpty ? null : chosen,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Request that deletes it'),
      hint: const Text('Pick a request'),
      items: [
        for (final name in options)
          DropdownMenuItem<String>(
            value: name,
            child: Text(undoRequests.contains(name) ? name : '$name (not found)', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (name) => onChanged(cleanup.copyWith(request: name ?? '')),
    );
  }
}
