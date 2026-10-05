import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../domain/services/dart_model_generator.dart';
import '../view_models/api_layer_view_model.dart';
import 'generated_files_view.dart';

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
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              for (final note in _vm.notes) InfoBanner(message: note, margin: const EdgeInsets.only(bottom: 8)),
              Expanded(
                child: GeneratedFilesView(
                  files: _vm.files,
                  emptyTitle: 'Pick a collection and press Generate',
                  emptyMessage: 'Tip: send a request and use "Save as example" so its response gets a typed DTO.',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
