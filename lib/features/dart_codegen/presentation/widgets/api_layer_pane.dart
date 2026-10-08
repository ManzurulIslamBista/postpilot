import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../domain/services/dart_model_generator.dart';
import '../../domain/services/state_layer.dart';
import '../view_models/api_layer_view_model.dart';
import 'generated_files_view.dart';
import 'model_diff_panel.dart';

/// Turns a collection into a Dart API layer: pick the collection, choose the
/// shape, generate, then copy the files or save them straight into a project.
class ApiLayerPane extends StatefulWidget {
  /// Preselected collection, e.g. the one the user right-clicked.
  final int? initialCollectionId;
  const ApiLayerPane({super.key, this.initialCollectionId});

  @override
  State<ApiLayerPane> createState() => _ApiLayerPaneState();
}

class _ApiLayerPaneState extends State<ApiLayerPane> {
  late final ApiLayerViewModel _vm = locator<ApiLayerViewModel>();
  late final TextEditingController _package = TextEditingController(text: _vm.packageName);

  @override
  void initState() {
    super.initState();
    final collections = context.read<CollectionsViewModel>().collections;
    _vm.collectionId = widget.initialCollectionId ?? collections.firstOrNull?.id;
  }

  @override
  void dispose() {
    _package.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collections = context.watch<CollectionsViewModel>().collections;
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        if (collections.isEmpty) {
          return const EmptyHint(
            icon: Icons.folder_open,
            title: 'No collections yet',
            message: 'Create or import a collection first. Its requests become the methods of the API layer.',
          );
        }
        final selected = collections.any((c) => c.id == _vm.collectionId) ? _vm.collectionId : collections.first.id;
        final top = <Widget>[
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey(selected),
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Collection', prefixIcon: Icon(Icons.folder_outlined, size: 18)),
                      items: [for (final c in collections) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                      onChanged: (id) => _vm.update(collection: id),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: TextField(
                      controller: _package,
                      decoration: const InputDecoration(labelText: 'Package name', prefixIcon: Icon(Icons.inventory_2_outlined, size: 18)),
                      onChanged: (v) => _vm.update(package: v),
                    ),
                  ),
                  SegmentedButton<DartModelStyle>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [for (final s in DartModelStyle.values) ButtonSegment(value: s, label: Text(s.label, style: const TextStyle(fontSize: 12)))],
                    selected: {_vm.modelStyle},
                    onSelectionChanged: (s) => _vm.update(style: s.first),
                  ),
                  FilterChip(
                    label: const Text('Repository + use cases'),
                    selected: _vm.domainLayer,
                    onSelected: (v) => _vm.update(domain: v),
                  ),
                  FilterChip(
                    label: const Text('All fields optional'),
                    selected: _vm.allNullable,
                    onSelected: (v) => _vm.update(nullable: v),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('State layer', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                      const SizedBox(height: 2),
                      Tooltip(
                        message: _vm.stateLayer.description,
                        child: SegmentedButton<StateLayerStyle>(
                          key: const ValueKey('state-layer'),
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: [
                            for (final s in StateLayerStyle.values) ButtonSegment(value: s, label: Text(s.label, style: const TextStyle(fontSize: 12))),
                          ],
                          selected: {_vm.stateLayer},
                          onSelectionChanged: (s) => _vm.update(state: s.first),
                        ),
                      ),
                    ],
                  ),
                  GradientButton(
                    label: 'Generate',
                    icon: Icons.auto_awesome,
                    loading: _vm.isBusy,
                    onPressed: _vm.generate,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Each request becomes a Dio method; {{variables}} and :params in the URL become typed arguments; '
                'saved response examples become DTO classes.',
                style: context.textStyles.caption.copyWith(color: colors.secondaryText),
              ),
              const SizedBox(height: 10),
              if (_vm.error != null) InfoBanner(kind: BannerKind.error, message: _vm.error!, margin: const EdgeInsets.only(bottom: 8)),
              // What changed since the remembered version comes first, then the notes; together they scroll
              // instead of pushing the files off a small screen.
              if (_vm.diff != null || (_vm.canRemember && !_vm.hasBaseline) || _vm.notes.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_vm.diff != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ModelDiffPanel(diff: _vm.diff!, maxHeight: 200, onRemember: _vm.diff!.isEmpty ? null : _vm.rememberCurrent),
                          )
                        else if (_vm.canRemember && !_vm.hasBaseline)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Tooltip(
                              message:
                                  'Keeps the shape of these DTO classes. The next generation starts with what changed since, and writing the files remembers them too.',
                              child: TextButton.icon(
                                onPressed: _vm.rememberCurrent,
                                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                                label: const Text('Remember this version'),
                              ),
                            ),
                          ),
                        for (final note in _vm.notes) InfoBanner(message: note, margin: const EdgeInsets.only(bottom: 8)),
                      ],
                    ),
                  ),
                ),
        ];
        final files = GeneratedFilesView(
          files: _vm.files,
          downloadName: 'api-layer',
          emptyTitle: 'Pick a collection and press Generate',
          emptyMessage: 'Tip: send a request and use "Save as example" so its response gets a typed DTO.',
          // The version written to disk is the one the next generation is compared with.
          onSaved: _vm.rememberCurrent,
        );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            // The options, the notes and the files do not fit one screen of a phone or of a short dialog: the page
            // scrolls and the files get a fixed height, instead of being squeezed to a few pixels by what is above them.
            builder: (context, c) => c.maxWidth < 640 || c.maxHeight < 600
                ? SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...top, SizedBox(height: 380, child: files)]),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...top, Expanded(child: files)]),
          ),
        );
      },
    );
  }
}
