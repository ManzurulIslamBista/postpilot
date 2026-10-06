import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/info_banner.dart';
import '../domain/services/mock_pagination.dart';
import '../domain/services/mock_resources.dart';
import 'mock_server_view_model.dart';

/// Load an OpenAPI 3 or Swagger 2 document and serve it with no saved example: answers are made up from the schemas,
/// requests are checked against them, and `/users` and `/users/{id}` keep their data in memory.
class MockOpenApiTab extends StatefulWidget {
  final MockServerViewModel vm;

  /// Opens the file dialog and returns the file's text; null when it was closed without a choice.
  final Future<String?> Function() pickFile;

  const MockOpenApiTab({super.key, required this.vm, required this.pickFile});

  @override
  State<MockOpenApiTab> createState() => _MockOpenApiTabState();
}

class _MockOpenApiTabState extends State<MockOpenApiTab> {
  MockServerViewModel get _vm => widget.vm;
  late final _text = TextEditingController(text: _vm.specText);
  late final _seed = TextEditingController(text: '${_vm.seed}');
  late final _items = TextEditingController(text: '${_vm.seedCount}');
  bool _picking = false;
  String? _fileError;

  @override
  void dispose() {
    _text.dispose();
    _seed.dispose();
    _items.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _picking = true;
      _fileError = null;
    });
    try {
      final text = await widget.pickFile();
      if (text != null) {
        _text.text = text;
        _load();
      }
    } catch (e) {
      _fileError = "Couldn't read the file: $e";
    }
    if (mounted) setState(() => _picking = false);
  }

  void _load() {
    _vm.loadSpec(_text.text);
    // A document that was understood is what the server should now serve.
    if (_vm.specError == null && _vm.spec != null) _vm.useSource(MockSourceKind.openApi);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    _text.text = text;
    _load();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final handler = _vm.specHandler;
    final store = handler?.store;
    return ListView(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      children: [
        Text(
          'Serve an OpenAPI 3 or Swagger 2 document (JSON or YAML) without saving a single example. Answers are made up from the '
          'schemas (examples, defaults and enums first, then fake data that follows the field names), requests are checked against the '
          'operation, and a resource such as /users and /users/{id} keeps its data: a POST shows up in the next list.',
          style: context.textStyles.caption.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: TextField(
            key: const ValueKey('openapi-text'),
            controller: _text,
            expands: true,
            maxLines: null,
            minLines: null,
            autocorrect: false,
            textAlignVertical: TextAlignVertical.top,
            style: context.textStyles.mono,
            decoration: const InputDecoration(hintText: 'Paste an OpenAPI or Swagger document here, or open a file.\n\nopenapi: 3.0.3\ninfo:\n  title: Shop\npaths:\n  /users: ...'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _text.text.trim().isEmpty ? null : _load,
              child: const Text('Load document'),
            ),
            OutlinedButton(
              onPressed: _picking ? null : _open,
              child: BusyLabel(busy: _picking, label: 'Open file…', busyLabel: 'Reading…', icon: Icons.folder_open, iconSize: 16),
            ),
            OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste, size: 16), label: const Text('Paste from clipboard')),
          ],
        ),
        const SizedBox(height: 8),
        // The app does not keep the spec a collection was imported from, so a document is always loaded here.
        const InfoBanner(
          message: 'PostPilot does not keep the document a collection was imported from, so load it again here (the file you imported, or the '
              'one your backend team publishes).',
        ),
        if (_fileError != null) InfoBanner(kind: BannerKind.error, message: _fileError!, margin: const EdgeInsets.only(top: 8)),
        if (_vm.specError != null) InfoBanner(kind: BannerKind.error, message: _vm.specError!, margin: const EdgeInsets.only(top: 8)),
        if (_vm.spec != null && handler != null) ...[
          InfoBanner(
            kind: BannerKind.success,
            title: _vm.spec!.title,
            message: '${handler.summary}. '
                '${_vm.spec!.basePath.isEmpty ? '' : 'Served under ${_vm.spec!.basePath}. '}'
                '${_vm.source == MockSourceKind.openApi ? 'This is what the server serves.' : 'Switch the source to "OpenAPI document" to serve it.'}',
            margin: const EdgeInsets.only(top: 8),
          ),
          const SizedBox(height: 12),
          ToolSection(
            title: 'How it is served',
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _seed,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Seed', helperText: 'Same seed, same data'),
                    onChanged: (v) => _vm.updateSpecOptions(seed: int.tryParse(v) ?? 1),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _items,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Items per resource', helperText: 'Fake items to start with'),
                    onChanged: (v) => _vm.updateSpecOptions(seedCount: int.tryParse(v) ?? 10),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<MockPaginationStrategy>(
                    key: ValueKey(_vm.pagination),
                    initialValue: _vm.pagination,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Paging', helperText: 'How lists are cut into pages'),
                    items: [
                      for (final s in MockPaginationStrategy.values) DropdownMenuItem(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (s) => _vm.updateSpecOptions(pagination: s),
                  ),
                ),
                FilterChip(
                  label: const Text('Check requests against the spec'),
                  selected: _vm.validateRequests,
                  onSelected: (v) => _vm.updateSpecOptions(validate: v),
                ),
                OutlinedButton.icon(
                  onPressed: _vm.resetData,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Reset data'),
                ),
              ],
            ),
          ),
          Text(
            store == null || store.itemCount == 0
                ? 'No data in memory yet: it is made on the first request.'
                : '${store.itemCount} items in memory across ${store.collectionCount} collection${store.collectionCount == 1 ? '' : 's'}. Reset puts them back to the starting data.',
            style: context.textStyles.caption.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: 12),
          ToolSection(
            title: 'Resources with data in memory (${handler.families.length})',
            hint: handler.families.isEmpty ? 'No path pair like /things and /things/{id} was found: every operation answers a fake of its response.' : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in handler.families)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.storage_outlined, size: 16, color: colors.mainAccent),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${f.collectionTemplate}${f.itemTemplate == null ? '' : '  and  ${f.itemTemplate}'}', style: context.textStyles.mono)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(_roles(f), style: context.textStyles.caption.copyWith(color: colors.secondaryText), textAlign: TextAlign.end),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _roles(MockResourceFamily f) => [
        if (f.list != null) 'list',
        if (f.create != null) 'create',
        if (f.read != null) 'read',
        if (f.replace != null) 'replace',
        if (f.update != null) 'update',
        if (f.remove != null) 'delete',
      ].join(' · ');
}
