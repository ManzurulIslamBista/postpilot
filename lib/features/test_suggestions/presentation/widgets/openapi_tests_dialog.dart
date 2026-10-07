import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/method_badge.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../domain/openapi/generated_case.dart';
import '../../domain/usecases/generate_openapi_tests_usecase.dart';
import '../view_models/openapi_tests_view_model.dart';

/// "Generate tests from OpenAPI…": reads an OpenAPI 3 or Swagger 2 document (pasted, opened from a file or
/// downloaded from the address the collection was last updated from), shows what would be written, and writes a
/// `Tests` folder of requests with assertions into the collection.
class OpenApiTestsDialog extends StatefulWidget {
  /// The collection the tests go into; chosen in the dialog when null.
  final int? collectionId;

  /// Replace what the app builds, for a test.
  @visibleForTesting
  final OpenApiTestsViewModel? viewModel;
  @visibleForTesting
  final Future<String?> Function()? pickFile;
  @visibleForTesting
  final Future<String> Function(String url)? download;

  const OpenApiTestsDialog({super.key, this.collectionId, this.viewModel, this.pickFile, this.download});

  static Future<void> show(BuildContext context, {int? collectionId}) =>
      ToolDialog.show(context, (_) => OpenApiTestsDialog(collectionId: collectionId));

  @override
  State<OpenApiTestsDialog> createState() => _OpenApiTestsDialogState();
}

class _OpenApiTestsDialogState extends State<OpenApiTestsDialog> {
  final _url = TextEditingController();
  final _spec = TextEditingController();
  final _cap = TextEditingController(text: '${GeneratedSuite.defaultCap}');
  late final OpenApiTestsViewModel _vm = widget.viewModel ?? _defaultViewModel();
  String? _sourceError;
  bool _fetching = false;

  OpenApiTestsViewModel _defaultViewModel() {
    final id = widget.collectionId ?? context.read<CollectionsViewModel>().collections.firstOrNull?.id;
    final useCase = locator<GenerateOpenApiTestsUseCase>();
    return OpenApiTestsViewModel(collectionId: id, write: useCase.call);
  }

  @override
  void initState() {
    super.initState();
    if (widget.viewModel == null) _restoreSource();
  }

  @override
  void dispose() {
    _url.dispose();
    _spec.dispose();
    _cap.dispose();
    // A view model that was handed in belongs to whoever made it.
    if (widget.viewModel == null) _vm.dispose();
    super.dispose();
  }

  String? get _collectionName {
    for (final c in context.read<CollectionsViewModel>().collections) {
      if (c.id == _vm.collectionId) return c.name;
    }
    return null;
  }

  /// The address "Update from OpenAPI" last downloaded this collection's document from, when it was used.
  String get _prefKey => 'openapi.source.${_collectionName ?? ''}';

  Future<void> _restoreSource() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final saved = prefs.getString(_prefKey);
      if (saved != null && _url.text.isEmpty) setState(() => _url.text = saved);
    } catch (_) {}
  }

  Future<String> _fetch(String url) async {
    final response = await locator<ApiClient>().send(ApiRequestSpec(
      method: 'GET',
      url: url,
      headers: const {'Accept': 'application/json, application/yaml, */*'},
      options: const ApiRequestOptions(maxResponseBytes: 32 * 1024 * 1024),
    ));
    if (!response.isSuccess) throw 'The server answered ${response.statusCode} ${response.statusMessage}.';
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<void> _download() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _fetching = true;
      _sourceError = null;
    });
    try {
      final text = await (widget.download ?? _fetch)(url);
      _spec.text = text;
      _vm.setSpec(text);
      try {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) await prefs.setString(_prefKey, url);
      } catch (_) {}
    } catch (e) {
      _sourceError = "Couldn't download the document: $e";
    }
    if (mounted) setState(() => _fetching = false);
  }

  Future<void> _openFile() async {
    try {
      final text = await (widget.pickFile ?? _pickText)();
      if (text == null) return;
      _spec.text = text;
      _vm.setSpec(text);
      if (mounted) setState(() => _sourceError = null);
    } catch (e) {
      if (mounted) setState(() => _sourceError = "Couldn't open the file: $e");
    }
  }

  static Future<String?> _pickText() async {
    const group = XTypeGroup(label: 'OpenAPI or Swagger document', extensions: ['json', 'yaml', 'yml']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    if (await file.length() > 32 * 1024 * 1024) throw 'The file is larger than 32 MB.';
    return file.readAsString();
  }

  @override
  Widget build(BuildContext context) {
    final collections = context.watch<CollectionsViewModel>().collections;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final vm = _vm;
        final selection = vm.selection;
        final done = vm.result;
        return ToolDialog(
          icon: Icons.fact_check_outlined,
          title: 'Generate tests from OpenAPI',
          subtitle: 'Contract, negative, boundary and auth tests for every operation',
          width: 900,
          height: 720,
          actions: [
            if (done != null)
              FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done'))
            else
              FilledButton(
                onPressed: vm.canGenerate ? vm.generate : null,
                child: BusyLabel(
                  busy: vm.busy && vm.suite != null,
                  icon: Icons.playlist_add,
                  label: selection == null ? 'Generate requests' : 'Generate ${selection.cases.length} ${selection.cases.length == 1 ? 'request' : 'requests'}',
                  busyLabel: 'Writing…',
                ),
              ),
          ],
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SourceSection(
                dialog: this,
                collections: [for (final c in collections) (c.id, c.name)],
                vm: vm,
                fetching: _fetching,
              ),
              if (vm.error != null) ...[const SizedBox(height: 10), InfoBanner(kind: BannerKind.error, message: vm.error!)],
              if (_sourceError != null) ...[const SizedBox(height: 10), InfoBanner(kind: BannerKind.error, message: _sourceError!)],
              if (done != null) ...[const SizedBox(height: 10), _DoneBanner(result: done)],
              if (vm.suite != null && selection != null && done == null) ...[
                const SizedBox(height: 14),
                _Preview(vm: vm, selection: selection, capField: _cap),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SourceSection extends StatelessWidget {
  final _OpenApiTestsDialogState dialog;
  final List<(int, String)> collections;
  final OpenApiTestsViewModel vm;
  final bool fetching;
  const _SourceSection({required this.dialog, required this.collections, required this.vm, required this.fetching});

  @override
  Widget build(BuildContext context) {
    final picker = DropdownButtonFormField<int>(
      key: ValueKey(vm.collectionId),
      initialValue: collections.any((c) => c.$1 == vm.collectionId) ? vm.collectionId : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Write the tests into collection'),
      items: [for (final c in collections) DropdownMenuItem(value: c.$1, child: Text(c.$2, overflow: TextOverflow.ellipsis))],
      onChanged: (id) {
        vm.setCollection(id);
        dialog._url.clear();
        dialog._restoreSource();
      },
    );
    final urlField = TextField(
      controller: dialog._url,
      decoration: const InputDecoration(labelText: 'Document address', hintText: 'https://api.example.com/openapi.json', prefixIcon: Icon(Icons.link, size: 18)),
      onSubmitted: (_) => dialog._download(),
    );
    final download = OutlinedButton(onPressed: fetching ? null : dialog._download, child: BusyLabel(busy: fetching, label: 'Download', busyLabel: 'Downloading…'));
    final openFile = OutlinedButton.icon(onPressed: dialog._openFile, icon: const Icon(Icons.folder_open, size: 16), label: const Text('Open file…'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                picker,
                const SizedBox(height: 8),
                urlField,
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [download, openFile]),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [SizedBox(width: 240, child: picker), const SizedBox(width: 10), Expanded(child: urlField), const SizedBox(width: 8), download, const SizedBox(width: 8), openFile],
          );
        }),
        const SizedBox(height: 8),
        TextField(
          controller: dialog._spec,
          minLines: 6,
          maxLines: 9,
          style: context.textStyles.mono,
          decoration: const InputDecoration(hintText: 'Or paste an OpenAPI 3 / Swagger 2 document here (JSON or YAML)'),
          onChanged: vm.setSpec,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: vm.canPreview ? vm.preview : null,
            child: BusyLabel(busy: vm.busy && vm.suite == null, icon: Icons.visibility_outlined, label: 'Preview', busyLabel: 'Reading…'),
          ),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  final OpenApiTestsViewModel vm;
  final GeneratedSelection selection;
  final TextEditingController capField;
  const _Preview({required this.vm, required this.selection, required this.capField});

  static const _shown = 60;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final suite = vm.suite!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          kind: BannerKind.info,
          title: '${suite.name}: ${suite.cases.length} requests from ${suite.operationCount} ${suite.operationCount == 1 ? 'operation' : 'operations'}',
          message: 'Tick what to generate. Path parameters stay as {{variables}}: set them to ids that exist where the tests run.',
        ),
        const SizedBox(height: 8),
        for (final category in TestCategory.values)
          CheckboxListTile(
            key: ValueKey('category-${category.name}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: vm.categories.contains(category),
            onChanged: suite.count(category) == 0 ? null : (_) => vm.toggleCategory(category),
            title: Text('${category.label} · ${suite.count(category)}', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(category.description, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: capField,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Write at most', isDense: true, errorText: vm.capError),
                onChanged: vm.setCap,
              ),
            ),
            Text(
              selection.skipped > 0
                  ? '${selection.cases.length} will be written; ${selection.skipped} more are left out by the limit (contracts first, then auth, negative, boundary).'
                  : '${selection.cases.length} will be written.',
              style: context.textStyles.caption.copyWith(color: colors.secondaryText),
            ),
          ],
        ),
        if (selection.changesDataCount > 0) ...[
          const SizedBox(height: 8),
          InfoBanner(
            kind: BannerKind.warning,
            title: '${selection.changesDataCount} of them change data (POST, PUT, PATCH, DELETE)',
            message: 'They are written to run only while the variable ${GenerateOpenApiTestsUseCase.gateVariable} is "true", so running the collection '
                'does not change a real server by accident. The variable is added as "false"; set it to "true" in the collection or an environment to run them.',
          ),
        ],
        for (final note in suite.notes) ...[const SizedBox(height: 8), InfoBanner(kind: BannerKind.info, message: note)],
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
          child: Column(
            children: [
              for (final c in selection.cases.take(_shown))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MethodBadge(method: c.method.label, width: 44),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: context.textStyles.body),
                            Text(c.expectation, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                          ],
                        ),
                      ),
                      if (c.changesData) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.edit_note, size: 16, color: colors.statusWarning)),
                    ],
                  ),
                ),
              if (selection.cases.length > _shown)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text('…and ${selection.cases.length - _shown} more', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DoneBanner extends StatelessWidget {
  final GeneratedTestsResult result;
  const _DoneBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final added = result.variablesAdded;
    return InfoBanner(
      kind: BannerKind.success,
      title: 'Created ${result.created} ${result.created == 1 ? 'request' : 'requests'} in "${result.folderName}"',
      message: [
        if (result.gated > 0)
          '${result.gated} of them change data and are skipped in runs until ${GenerateOpenApiTestsUseCase.gateVariable} is "true".',
        if (added.isNotEmpty) 'Added the collection variable${added.length == 1 ? '' : 's'} ${added.join(' and ')}.',
        'Run the collection, or just the folder, to see how the API does.',
      ].join(' '),
    );
  }
}
