import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../dart_codegen/domain/services/dart_model_generator.dart' show DartModelStyle;
import '../../../dart_codegen/domain/services/state_layer.dart';
import '../../../dart_codegen/presentation/widgets/generated_files_view.dart';
import '../view_models/odoo_client_gen_view_model.dart';
import '../view_models/odoo_studio_view_model.dart';

/// Odoo to Flutter: pick models (searchable, from the live server or the Explorer), choose the model style and the state
/// layer, and generate a ready-to-use client (`OdooClient`, `Domain`, `Command`, exceptions, a repository per model) that
/// is written through the safe folder writer. Credentials never end up in the generated code.
class OdooFlutterClientTab extends StatefulWidget {
  final OdooStudioViewModel viewModel;
  const OdooFlutterClientTab({super.key, required this.viewModel});

  @override
  State<OdooFlutterClientTab> createState() => _OdooFlutterClientTabState();
}

class _OdooFlutterClientTabState extends State<OdooFlutterClientTab> {
  late final OdooClientGenViewModel _gen = OdooClientGenViewModel(widget.viewModel);
  final _search = TextEditingController();
  late final _folder = TextEditingController(text: _gen.folder);

  @override
  void dispose() {
    _search.dispose();
    _folder.dispose();
    _gen.dispose();
    super.dispose();
  }

  Widget _picker(BuildContext context) {
    final studio = widget.viewModel;
    final colors = context.colors;
    final styles = context.textStyles;
    final visible = _gen.visibleModels;
    final explored = studio.info;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('model-filter'),
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Find models',
                  hintText: 'res.partner or "Contact"',
                  helperText: studio.modelNames.isEmpty ? 'Press "Load models" to list the server\'s models' : '${studio.modelNames.length} models on the server',
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
                onChanged: _gen.setSearch,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: studio.isBusy ? null : studio.loadModels,
              child: BusyLabel(busy: studio.busyLabel?.startsWith('Loading') ?? false, label: 'Load models', busyLabel: 'Loading…'),
            ),
          ],
        ),
        if (explored != null && !_gen.selected.contains(explored.model))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _gen.addExplored,
              icon: const Icon(Icons.travel_explore, size: 16),
              label: Text('Add the explored model (${explored.model})'),
            ),
          ),
        if (_gen.selected.isNotEmpty) ...[
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 84),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final model in _gen.selected)
                    InputChip(
                      key: ValueKey('selected:$model'),
                      label: Text(model, style: styles.mono),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => _gen.toggle(model, false),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Expanded(
          // A Material, not a coloured box: the list tiles paint their ink on the nearest Material.
          child: Material(
            color: colors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: colors.border)),
            clipBehavior: Clip.antiAlias,
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        studio.modelNames.isEmpty ? 'No models loaded yet.' : 'No model matches "${_gen.search}".',
                        style: styles.caption.copyWith(color: colors.secondaryText),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final model = visible[i];
                      return CheckboxListTile(
                        key: ValueKey('model:$model'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _gen.selected.contains(model),
                        onChanged: (on) => _gen.toggle(model, on ?? false),
                        title: Text(model, style: styles.mono, overflow: TextOverflow.ellipsis),
                        subtitle: Text(studio.modelLabels[model] ?? '', overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _options(BuildContext context) {
    final colors = context.colors;
    final styles = context.textStyles;
    final explored = widget.viewModel.info;
    Widget labelled(String label, Widget child) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(label, style: styles.caption.copyWith(color: colors.secondaryText)), const SizedBox(height: 2), child],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        labelled(
          'Model classes',
          Tooltip(
            message: _gen.modelStyle.description,
            child: SegmentedButton<DartModelStyle>(
              key: const ValueKey('model-style'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final s in DartModelStyle.values) ButtonSegment(value: s, label: Text(s.label, style: const TextStyle(fontSize: 12)))],
              selected: {_gen.modelStyle},
              onSelectionChanged: (s) => _gen.update(style: s.first),
            ),
          ),
        ),
        labelled(
          'State layer',
          Tooltip(
            message: _gen.stateLayer.description,
            child: SegmentedButton<StateLayerStyle>(
              key: const ValueKey('state-layer'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final s in StateLayerStyle.values) ButtonSegment(value: s, label: Text(s.label, style: const TextStyle(fontSize: 12)))],
              selected: {_gen.stateLayer},
              onSelectionChanged: (s) => _gen.update(state: s.first),
            ),
          ),
        ),
        SizedBox(
          width: 150,
          child: TextField(
            key: const ValueKey('client-folder'),
            controller: _folder,
            decoration: const InputDecoration(labelText: 'Folder', prefixIcon: Icon(Icons.folder_outlined, size: 18)),
            onChanged: (v) => _gen.update(folder: v),
          ),
        ),
        FilterChip(
          label: const Text('Include related models'),
          tooltip: 'Also generate the models its many2one fields point at (one level)',
          selected: _gen.includeRelated,
          onSelected: (v) => _gen.update(related: v),
        ),
        FilterChip(
          label: const Text('Odoo 18 JSON-RPC client'),
          tooltip: 'Also write OdooRpcClient: login session instead of an API key, for Odoo 18 and older',
          selected: _gen.includeJsonRpc,
          onSelected: (v) => _gen.update(jsonRpc: v),
        ),
        FilterChip(
          label: const Text('Computed fields'),
          selected: _gen.includeComputed,
          onSelected: (v) => _gen.update(computed: v),
        ),
        if (explored != null)
          FilterChip(
            label: Text('Explorer fields for ${explored.model}'),
            tooltip: 'Use the fields ticked in the Explorer for that model instead of every stored field',
            selected: _gen.useExplorerFields,
            onSelected: (v) => _gen.update(explorerFields: v),
          ),
        GradientButton(label: 'Generate', icon: Icons.auto_awesome, loading: _gen.isBusy, onPressed: _gen.generate),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.viewModel, _gen]),
      builder: (context, _) {
        final output = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Errors and notes scroll within a limited height, so a long list never pushes the files off a small screen.
            if (_gen.error != null || (widget.viewModel.error != null && _gen.files.isEmpty) || _gen.notes.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_gen.error != null) InfoBanner(kind: BannerKind.error, message: _gen.error!, margin: const EdgeInsets.only(bottom: 8)),
                      if (widget.viewModel.error != null && _gen.files.isEmpty)
                        InfoBanner(kind: BannerKind.error, message: widget.viewModel.error!, margin: const EdgeInsets.only(bottom: 8)),
                      for (final note in _gen.notes) InfoBanner(message: note, margin: const EdgeInsets.only(bottom: 8)),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: GeneratedFilesView(
                files: _gen.files,
                emptyTitle: 'Tick models and press Generate',
                emptyMessage: 'You get model classes, a Dio client for Odoo, a Domain builder, x2many Command helpers, exceptions '
                    'and a repository per model. The API key stays out of the code: it is a constructor argument.',
              ),
            ),
          ],
        );
        final intro = <Widget>[
          _options(context),
          const SizedBox(height: 4),
          Text(
            'Uses the connection of this Studio (Connect tab). Models and fields are read from the server; the model open in the Explorer works offline.',
            style: context.textStyles.caption.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: 10),
        ];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 760 && c.maxHeight >= 360
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...intro,
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [SizedBox(width: 300, child: _picker(context)), const SizedBox(width: 14), Expanded(child: output)],
                        ),
                      ),
                    ],
                  )
                // On a phone the options, the picker and the result do not fit one screen: the page scrolls and each part keeps a usable height.
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...intro,
                        SizedBox(height: 300, child: _picker(context)),
                        const SizedBox(height: 10),
                        SizedBox(height: 560, child: output),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}
