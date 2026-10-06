import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../domain/services/api_test_generator.dart';
import '../../domain/services/dart_model_generator.dart';
import '../view_models/api_tests_view_model.dart';
import 'generated_files_view.dart';

/// Turns a collection into the `test/` tree of its generated API layer: fixtures from the saved
/// examples, model round trips, data source tests on http_mock_adapter, and repository and use
/// case tests on mocktail. Save it into the same project folder as the API layer.
class ApiTestsPane extends StatefulWidget {
  /// Preselected collection, e.g. the one the user right-clicked.
  final int? initialCollectionId;
  const ApiTestsPane({super.key, this.initialCollectionId});

  @override
  State<ApiTestsPane> createState() => _ApiTestsPaneState();
}

class _ApiTestsPaneState extends State<ApiTestsPane> {
  late final ApiTestsViewModel _vm = locator<ApiTestsViewModel>();
  late final TextEditingController _package = TextEditingController(text: _vm.packageName);
  late final TextEditingController _lock = TextEditingController(text: _vm.lockText);

  @override
  void initState() {
    super.initState();
    final collections = context.read<CollectionsViewModel>().collections;
    _vm.collectionId = widget.initialCollectionId ?? collections.firstOrNull?.id;
  }

  @override
  void dispose() {
    _package.dispose();
    _lock.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $what')));
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
            message: 'Create or import a collection first. Its requests and saved examples become the tests.',
          );
        }
        final selected = collections.any((c) => c.id == _vm.collectionId) ? _vm.collectionId : collections.first.id;
        final locked = _vm.lockedPackageCount;
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
                  SegmentedButton<TestFramework>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [for (final f in TestFramework.values) ButtonSegment(value: f, label: Text(f.label, style: const TextStyle(fontSize: 12)))],
                    selected: {_vm.framework},
                    onSelectionChanged: (s) => _vm.update(testFramework: s.first),
                  ),
                  GradientButton(
                    label: 'Generate tests',
                    icon: Icons.science_outlined,
                    loading: _vm.isBusy,
                    onPressed: _vm.generate,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Use the same package name and options as in the API layer tab: the tests import what that tab generates. '
                'Fixtures come from the saved response examples (secrets masked); error cases come from the examples saved with an error status.',
                style: context.textStyles.caption.copyWith(color: colors.secondaryText),
              ),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    locked == null
                        ? 'Pin versions from your pubspec.lock (optional)'
                        : locked == 0
                            ? 'That is not a pubspec.lock: paste the file as it is'
                            : 'Versions read from $locked packages in your pubspec.lock',
                    style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    SizedBox(
                      height: 90,
                      child: TextField(
                        controller: _lock,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: context.textStyles.mono,
                        decoration: const InputDecoration(hintText: 'Paste the content of your project\'s pubspec.lock. Packages it already resolves keep their version.'),
                        onChanged: (v) => _vm.update(lock: v),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              if (_vm.error != null) InfoBanner(kind: BannerKind.error, message: _vm.error!, margin: const EdgeInsets.only(bottom: 8)),
              if (_vm.devDependencies.isNotEmpty)
                InfoBanner(
                  kind: BannerKind.success,
                  title: 'Add the test packages to pubspec.yaml',
                  message: _vm.addCommand.isEmpty ? _vm.devDependencies : '${_vm.devDependencies}\nor run: ${_vm.addCommand}',
                  margin: const EdgeInsets.only(bottom: 8),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copy the dev_dependencies',
                    onPressed: () => _copy(_vm.devDependencies, 'dev_dependencies'),
                  ),
                ),
              for (final note in _vm.notes) InfoBanner(message: note, margin: const EdgeInsets.only(bottom: 8)),
              Expanded(
                child: GeneratedFilesView(
                  files: _vm.files,
                  emptyTitle: 'Pick a collection and press Generate tests',
                  emptyMessage: 'Tip: send a request, then use "Save as example" on a good and on a failing response, so the tests cover both.',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
