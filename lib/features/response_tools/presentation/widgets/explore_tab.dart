import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
import '../../domain/services/json_tree.dart';
import '../view_models/response_tools_view_model.dart';

/// The response as an expandable tree. Selecting a node shows its JSON path,
/// and from there it can be copied, turned into a variable for the next
/// request ("click to extract") or into a test.
class ExploreTab extends StatefulWidget {
  final ResponseToolsViewModel viewModel;
  const ExploreTab({super.key, required this.viewModel});

  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  static const _pageSize = 100;

  final _search = TextEditingController();
  final _expanded = <String>{''};
  final _shown = <String, int>{};
  String? _selected;
  Object? _selectedValue;

  ResponseToolsData get _data => widget.viewModel.data;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(JsonNode node) {
    setState(() {
      _selected = node.path;
      _selectedValue = node.value;
      if (node.isContainer && !_expanded.remove(node.path)) _expanded.add(node.path);
    });
  }

  /// Opens every branch that holds a match so the matches are visible.
  void _runSearch(String query) {
    setState(() {
      _expanded
        ..clear()
        ..add('');
      if (query.trim().isEmpty) return;
      final q = query.trim().toLowerCase();
      var hits = 0;
      bool walk(JsonNode node) {
        var found = false;
        final own = !node.isContainer
            ? '${node.value}'.toLowerCase().contains(q)
            : (node.path.isNotEmpty && node.label.toLowerCase().contains(q));
        if (own) {
          found = true;
          hits++;
        }
        if (node.isContainer && hits < 300) {
          for (final child in node.children) {
            if (walk(child)) found = true;
            if (hits >= 300) break;
          }
        }
        if (found && node.isContainer) _expanded.add(node.path);
        return found;
      }

      walk(JsonNode.root(_data.json));
    });
  }

  List<(JsonNode, int)> _visible() {
    final rows = <(JsonNode, int)>[];
    void walk(JsonNode node, int depth) {
      rows.add((node, depth));
      if (!node.isContainer || !_expanded.contains(node.path)) return;
      final children = node.children;
      final limit = _shown[node.path] ?? _pageSize;
      for (var i = 0; i < children.length && i < limit; i++) {
        walk(children[i], depth + 1);
      }
      if (children.length > limit) {
        rows.add((JsonNode(label: '… ${children.length - limit} more', path: '\u0000more:${node.path}', value: null), depth + 1));
      }
    }

    walk(JsonNode.root(_data.json), 0);
    return rows;
  }

  Color _valueColor(JsonNode n) {
    final c = context.colors;
    return switch (n.kind) {
      JsonNodeKind.string => c.syntaxString,
      JsonNodeKind.number => c.syntaxNumber,
      JsonNodeKind.boolean || JsonNodeKind.nullValue => c.syntaxKeyword,
      _ => c.secondaryText,
    };
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _extract() async {
    final path = _selected;
    if (path == null || path.isEmpty) return;
    final last = path.split(RegExp(r'[.\[\]"\x27]')).where((s) => s.isNotEmpty).lastOrNull ?? 'value';
    final result = await showDialog<({String key, ExtractorScope scope})>(
      context: context,
      builder: (_) => _ExtractDialog(path: path, suggested: last.replaceAll(RegExp(r'[^\w$.-]'), '_')),
    );
    if (result == null) return;
    await widget.viewModel.addExtractor(path: path, key: result.key, scope: result.scope);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved: {{${result.key}}} will hold $path after each send (see the Tests tab)'),
      ));
    }
  }

  Future<void> _assert() async {
    final path = _selected;
    if (path == null || path.isEmpty) return;
    final value = _selectedValue;
    final scalar = value is String || value is num || value is bool;
    await widget.viewModel.addAssertion(AssertionEntity(
      type: scalar ? AssertionType.jsonPathEquals : AssertionType.jsonPathExists,
      path: path,
      expected: scalar ? '$value' : '',
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test added: $path ${scalar ? 'equals $value' : 'exists'}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_data.isJson) {
      return const EmptyHint(
        icon: Icons.account_tree_outlined,
        title: 'This response is not JSON',
        message: 'The tree view opens JSON responses. Use Decode or Share for other bodies.',
      );
    }
    final colors = context.colors;
    final rows = _visible();
    final canPick = _selected != null && _selected!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search keys and values',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _search.clear();
                        _runSearch('');
                      },
                    ),
            ),
            onChanged: _runSearch,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.appBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final (node, depth) = rows[i];
                  if (node.path.startsWith('\u0000more:')) {
                    final parent = node.path.substring('\u0000more:'.length);
                    return InkWell(
                      onTap: () => setState(() => _shown[parent] = (_shown[parent] ?? _pageSize) + _pageSize),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(12.0 + depth * 16, 6, 8, 6),
                        child: Text('${node.label} (show more)', style: context.textStyles.caption.copyWith(color: colors.mainAccent)),
                      ),
                    );
                  }
                  final selected = node.path == _selected;
                  return InkWell(
                    onTap: () => _toggle(node),
                    child: Container(
                      color: selected ? colors.mainAccent.withValues(alpha: 0.12) : null,
                      padding: EdgeInsets.fromLTRB(8.0 + depth * 16, 4, 8, 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            child: node.isContainer
                                ? Icon(_expanded.contains(node.path) ? Icons.expand_more : Icons.chevron_right, size: 16, color: colors.secondaryText)
                                : null,
                          ),
                          // One ellipsized line for key and value, so a long key (a UUID, a URL) is cut instead of overflowing a narrow row.
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: node.label, style: TextStyle(color: colors.syntaxKey, fontWeight: FontWeight.w600)),
                                TextSpan(text: ': ', style: TextStyle(color: colors.secondaryText)),
                                TextSpan(text: node.preview, style: TextStyle(color: _valueColor(node))),
                              ]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.mono,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Path', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    _selected == null ? 'Select a value' : (_selected!.isEmpty ? r'$ (root)' : _selected!),
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.mono.copyWith(color: colors.mainAccent),
                  ),
                ),
                TextButton.icon(
                  onPressed: canPick ? () => _copy(_selected!, 'Path copied') : null,
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy path'),
                ),
                TextButton.icon(
                  onPressed: _selected == null
                      ? null
                      : () => _copy(
                            _selectedValue is String ? _selectedValue as String : _prettyValue(_selectedValue),
                            'Value copied',
                          ),
                  icon: const Icon(Icons.content_copy, size: 14),
                  label: const Text('Copy value'),
                ),
                FilledButton.icon(
                  onPressed: canPick ? _extract : null,
                  icon: const Icon(Icons.output, size: 14),
                  label: const Text('Use as variable'),
                ),
                OutlinedButton.icon(
                  onPressed: canPick ? _assert : null,
                  icon: const Icon(Icons.rule, size: 14),
                  label: const Text('Add test'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _prettyValue(Object? v) => v == null ? 'null' : '$v';
}

class _ExtractDialog extends StatefulWidget {
  final String path;
  final String suggested;
  const _ExtractDialog({required this.path, required this.suggested});

  @override
  State<_ExtractDialog> createState() => _ExtractDialogState();
}

class _ExtractDialogState extends State<_ExtractDialog> {
  late final _name = TextEditingController(text: widget.suggested);
  ExtractorScope _scope = ExtractorScope.environment;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _error => ExtractorEntity(variableKey: _name.text).keyError;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Use as variable'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('After every send, ${widget.path} is copied into a variable you can use as {{name}} in other requests.'),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Variable name', errorText: _error),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            SegmentedButton<ExtractorScope>(
              showSelectedIcon: false,
              segments: [for (final s in ExtractorScope.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _error == null ? () => Navigator.pop(context, (key: _name.text.trim(), scope: _scope)) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
