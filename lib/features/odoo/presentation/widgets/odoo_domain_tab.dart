import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/code_block.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/services/odoo_domain.dart';
import '../view_models/odoo_studio_view_model.dart';

/// Editable form of a domain. Values stay as the text the user typed until the
/// domain is written out, so `1, 2` is not rewritten to `[1, 2]` while typing.
class _Row {
  String field;
  String op;
  String raw;
  bool negate;
  _Row({this.field = '', this.op = '=', this.raw = '', this.negate = false});
}

class _Group {
  bool any;

  /// `['!', ...]` over the whole group.
  bool negate;
  final List<Object> children;
  _Group({this.any = false, this.negate = false, List<Object>? children}) : children = children ?? [];
}

/// Build an Odoo domain without writing prefix notation by hand: pick fields
/// and operators, combine with AND/OR, and copy the result as JSON (for
/// JSON-2 bodies) or Python (for models and views).
class OdooDomainTab extends StatefulWidget {
  final OdooStudioViewModel viewModel;
  const OdooDomainTab({super.key, required this.viewModel});

  @override
  State<OdooDomainTab> createState() => _OdooDomainTabState();
}

class _OdooDomainTabState extends State<OdooDomainTab> {
  _Group _root = _Group(children: [_Row()]);
  final _import = TextEditingController();

  OdooModelInfo? get _info => widget.viewModel.info;

  @override
  void initState() {
    super.initState();
    if (widget.viewModel.domainText.trim().isNotEmpty) _load(widget.viewModel.domainText);
  }

  @override
  void dispose() {
    _import.dispose();
    super.dispose();
  }

  // --- conversion ----------------------------------------------------------------

  /// The tree for [g], or null when it holds no condition yet (an empty group, or
  /// a negated one, would otherwise write a dangling `'!'`).
  DomainNode? _toNode(_Group g) {
    final kids = <DomainNode>[];
    for (final c in g.children) {
      if (c is _Group) {
        final n = _toNode(c);
        if (n != null) kids.add(n);
      } else if (c is _Row && c.field.trim().isNotEmpty) {
        final leaf = DomainLeaf(c.field.trim(), c.op, OdooDomain.parseValue(c.raw, operator: c.op, field: _info?.field(c.field.trim())));
        kids.add(c.negate ? DomainNot(leaf) : leaf);
      }
    }
    if (kids.isEmpty) return null;
    final group = DomainGroup(any: g.any, children: kids);
    return g.negate ? DomainNot(group) : group;
  }

  _Group _fromNode(DomainNode node) => node is DomainGroup ? _groupOf(node) : _Group(children: [_childOf(node)]);

  _Group _groupOf(DomainGroup g, {bool negate = false}) =>
      _Group(any: g.any, negate: negate, children: [for (final c in g.children) _childOf(c)]);

  /// A row for a condition, a group for a (possibly negated) group.
  Object _childOf(DomainNode n) {
    if (n is DomainGroup) return _groupOf(n);
    if (n is DomainLeaf) return _rowOf(n);
    final inner = (n as DomainNot).child;
    if (inner is DomainGroup) return _groupOf(inner, negate: true);
    if (inner is DomainLeaf) return _rowOf(inner, negate: true);
    // NOT NOT x: a group keeps both negations visible.
    return _Group(negate: true, children: [_childOf(inner)]);
  }

  _Row _rowOf(DomainLeaf leaf, {bool negate = false}) => _Row(
        field: leaf.field,
        op: leaf.operator,
        raw: OdooDomain.formatValue(leaf.value, operator: leaf.operator, field: _info?.field(leaf.field)),
        negate: negate,
      );

  void _load(String text) {
    final tree = OdooDomain.parseText(text);
    if (tree == null) return;
    final g = _fromNode(tree);
    _root = g.children.isEmpty ? _Group(children: [_Row()]) : g;
  }

  // --- editing ---------------------------------------------------------------------

  Widget _groupEditor(_Group g, {int depth = 0, VoidCallback? onRemove}) {
    final colors = context.colors;
    return Container(
      margin: EdgeInsets.only(left: depth == 0 ? 0 : 8, bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: depth == 0 ? Colors.transparent : colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: depth == 0 ? null : Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Match', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [ButtonSegment(value: false, label: Text('ALL')), ButtonSegment(value: true, label: Text('ANY'))],
                selected: {g.any},
                onSelectionChanged: (s) => setState(() => g.any = s.first),
              ),
              Text('  of these', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
              if (depth > 0) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Match records that do NOT satisfy this group',
                  child: FilterChip(
                    label: const Text('NOT'),
                    visualDensity: VisualDensity.compact,
                    selected: g.negate,
                    onSelected: (v) => setState(() => g.negate = v),
                  ),
                ),
              ],
              const Spacer(),
              if (onRemove != null) IconButton(icon: const Icon(Icons.close, size: 16), tooltip: 'Remove group', onPressed: onRemove),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < g.children.length; i++)
            if (g.children[i] is _Group)
              _groupEditor(g.children[i] as _Group, depth: depth + 1, onRemove: () => setState(() => g.children.removeAt(i)))
            else
              _rowEditor(g, g.children[i] as _Row, i),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(onPressed: () => setState(() => g.children.add(_Row())), icon: const Icon(Icons.add, size: 16), label: const Text('Condition')),
              if (depth < 2) TextButton.icon(onPressed: () => setState(() => g.children.add(_Group(any: !g.any, children: [_Row()]))), icon: const Icon(Icons.account_tree_outlined, size: 16), label: const Text('Group')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowEditor(_Group g, _Row r, int index) {
    final field = _info?.field(r.field.trim());
    final ops = field == null ? OdooOperators.all.keys.toList() : OdooOperators.forType(field.type);
    if (!ops.contains(r.op)) ops.insert(0, r.op);
    return Padding(
      key: ObjectKey(r),
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(
            message: 'NOT',
            child: FilterChip(
              label: const Text('NOT'),
              visualDensity: VisualDensity.compact,
              selected: r.negate,
              onSelected: (v) => setState(() => r.negate = v),
            ),
          ),
          SizedBox(
            width: 200,
            child: Autocomplete<String>(
              initialValue: TextEditingValue(text: r.field),
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                final all = _info?.fields.map((f) => f.name) ?? const <String>[];
                return q.isEmpty ? all.take(30) : all.where((n) => n.contains(q)).take(30);
              },
              onSelected: (v) => setState(() => r.field = v),
              fieldViewBuilder: (context, controller, focus, submit) => TextField(
                controller: controller,
                focusNode: focus,
                style: context.textStyles.mono,
                decoration: InputDecoration(labelText: 'Field', helperText: field?.type),
                onChanged: (v) => r.field = v,
                onEditingComplete: () => setState(() {}),
              ),
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              key: ValueKey('${r.field}|${r.op}'),
              initialValue: r.op,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Operator'),
              items: [for (final o in ops) DropdownMenuItem(value: o, child: Text('$o  ${OdooOperators.all[o] ?? ''}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))],
              onChanged: (v) => setState(() => r.op = v ?? r.op),
            ),
          ),
          SizedBox(
            width: 210,
            child: TextFormField(
              initialValue: r.raw,
              decoration: InputDecoration(labelText: 'Value', helperText: r.op == 'in' || r.op == 'not in' ? 'comma separated' : null),
              onChanged: (v) => setState(() => r.raw = v),
            ),
          ),
          IconButton(icon: const Icon(Icons.close, size: 16), tooltip: 'Remove', onPressed: () => setState(() => g.children.remove(r))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final node = _toNode(_root) ?? const DomainGroup();
    final list = OdooDomain.toList(node);
    final json = const JsonEncoder.withIndent('  ').convert(list);
    final python = OdooDomain.toPython(node);
    final body = const JsonEncoder.withIndent('  ').convert({
      'domain': list,
      'fields': widget.viewModel.chosenFields.isEmpty ? ['display_name'] : widget.viewModel.chosenFields.toList(),
      'limit': 20,
    });
    final editor = ListView(
      children: [
        if (_info == null)
          const Padding(padding: EdgeInsets.only(bottom: 10), child: InfoBanner(message: 'Read a model in the Explorer tab to get field suggestions and the right operators for each field type.')),
        _groupEditor(_root),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Value: text or a number. True, False and None are those values (parent_id = False means "has no parent"), '
            '[1, 2] is a list, and quotes keep text exactly as typed ("False" in quotes is the word).',
            style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
          ),
        ),
        ToolSection(
          title: 'Import a domain',
          hint: 'Paste JSON or Python: [("state", "=", "sale")]',
          child: Row(
            children: [
              Expanded(child: TextField(controller: _import, style: context.textStyles.mono, decoration: const InputDecoration(hintText: '[["state","=","sale"]]'))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  final ok = OdooDomain.parseText(_import.text) != null;
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That isn't a valid domain")));
                    return;
                  }
                  setState(() => _load(_import.text));
                },
                child: const Text('Load'),
              ),
            ],
          ),
        ),
      ],
    );
    final output = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: CodeBlock(text: list.isEmpty ? '[]' : json, label: 'Domain · JSON')),
        const SizedBox(height: 8),
        SizedBox(height: 86, child: CodeBlock(text: python, label: 'Python', wrap: true)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  widget.viewModel.setDomainText(json);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Domain sent to the Explorer')));
                },
                icon: const Icon(Icons.send_outlined, size: 16),
                label: const Text('Use in Explorer'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('search_read body'),
                    content: SizedBox(width: 460, height: 280, child: CodeBlock(text: body, label: 'JSON body')),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                  ),
                ),
                icon: const Icon(Icons.data_object, size: 16),
                label: const Text('As request body'),
              ),
            ),
          ],
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 760
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 6, child: editor), const SizedBox(width: 14), Expanded(flex: 4, child: output)])
            : Column(children: [Expanded(flex: 3, child: editor), const SizedBox(height: 10), Expanded(flex: 2, child: output)]),
      ),
    );
  }
}
