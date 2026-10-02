import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/code_block.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../domain/services/graphql_query_builder.dart';
import '../domain/services/graphql_schema.dart';
import 'graphql_explorer_view_model.dart';

/// Browse a GraphQL API: its queries, mutations and types, with arguments and
/// return types, and turn any field into a ready-to-run operation.
class GraphqlExplorerDialog extends StatefulWidget {
  final String initialUrl;
  final String initialHeaders;

  /// When opened from a request, "Use in request" hands the operation back.
  final void Function(String query, String variables)? onUse;

  const GraphqlExplorerDialog({super.key, this.initialUrl = '', this.initialHeaders = '', this.onUse});

  static Future<void> show(BuildContext context, {String initialUrl = '', String initialHeaders = '', void Function(String query, String variables)? onUse}) =>
      ToolDialog.show(context, (_) => GraphqlExplorerDialog(initialUrl: initialUrl, initialHeaders: initialHeaders, onUse: onUse));

  @override
  State<GraphqlExplorerDialog> createState() => _GraphqlExplorerDialogState();
}

class _GraphqlExplorerDialogState extends State<GraphqlExplorerDialog> {
  late final GraphqlExplorerViewModel _vm = locator<GraphqlExplorerViewModel>()
    ..url = widget.initialUrl
    ..headersText = widget.initialHeaders;
  late final _url = TextEditingController(text: widget.initialUrl);
  late final _headers = TextEditingController(text: widget.initialHeaders);
  final _filter = TextEditingController();

  @override
  void dispose() {
    _vm.dispose();
    _url.dispose();
    _headers.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste an introspection result'),
        content: SizedBox(width: 520, child: TextField(controller: controller, autofocus: true, minLines: 8, maxLines: 14, style: context.textStyles.mono, decoration: const InputDecoration(hintText: '{"data": {"__schema": {…}}}'))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Use'))],
      ),
    );
    controller.dispose();
    if (text != null && !_vm.loadFromText(text) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That doesn't look like an introspection result")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final schema = _vm.schema;
        return ToolDialog(
          icon: Icons.hexagon_outlined,
          title: 'GraphQL explorer',
          subtitle: schema == null ? 'Fetch a schema to browse it' : '${schema.userTypes.length} types · ${schema.rootFields('query').length} queries · ${schema.rootFields('mutation').length} mutations',
          width: 1040,
          height: 700,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(builder: (context, c) {
                  final urlField = TextField(
                    controller: _url,
                    style: context.textStyles.mono,
                    decoration: const InputDecoration(hintText: 'https://api.example.com/graphql', prefixIcon: Icon(Icons.link, size: 18)),
                    onChanged: (v) => _vm.url = v,
                    onSubmitted: (_) => _vm.fetch(),
                  );
                  final fetch = FilledButton(onPressed: _vm.isBusy ? null : _vm.fetch, child: BusyLabel(busy: _vm.isBusy, icon: Icons.cloud_download_outlined, label: 'Fetch schema', busyLabel: 'Fetching…'));
                  final paste = OutlinedButton(onPressed: _paste, child: const Text('Paste JSON'));
                  // On a phone the URL gets its own line and the buttons wrap beneath it.
                  return c.maxWidth >= 560
                      ? Row(children: [Expanded(child: urlField), const SizedBox(width: 8), fetch, const SizedBox(width: 6), paste])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [urlField, const SizedBox(height: 8), Wrap(spacing: 6, runSpacing: 6, children: [fetch, paste])]);
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: _headers,
                  minLines: 1,
                  maxLines: 3,
                  style: context.textStyles.mono,
                  decoration: const InputDecoration(labelText: 'Headers (one per line)', hintText: 'Authorization: Bearer {{token}}'),
                  onChanged: (v) => _vm.headersText = v,
                ),
                if (_vm.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(kind: BannerKind.error, message: _vm.error!)),
                const SizedBox(height: 10),
                Expanded(
                  child: schema == null
                      ? const EmptyHint(icon: Icons.hexagon_outlined, title: 'No schema yet', message: 'Enter the endpoint and press "Fetch schema". If introspection is disabled, paste the schema JSON instead.')
                      : LayoutBuilder(builder: (context, c) {
                          final list = _list(context, schema);
                          final detail = _detail(context, schema);
                          return c.maxWidth >= 760
                              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SizedBox(width: 300, child: list), const SizedBox(width: 12), Expanded(child: detail)])
                              : Column(children: [Expanded(flex: 2, child: list), const SizedBox(height: 10), Expanded(flex: 3, child: detail)]);
                        }),
                ),
                if (schema == null) SizedBox(height: 0, child: Divider(color: colors.border)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, GqlSchema schema) {
    final colors = context.colors;
    final q = _filter.text.trim().toLowerCase();
    final isTypes = _vm.section == 'types';
    final fields = isTypes ? const <GqlField>[] : [for (final f in schema.rootFields(_vm.section)) if (q.isEmpty || f.name.toLowerCase().contains(q)) f];
    final types = isTypes ? [for (final t in schema.userTypes) if (q.isEmpty || t.name.toLowerCase().contains(q)) t] : const <GqlType>[];
    return Container(
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact, padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6))),
                  segments: [
                    ButtonSegment(value: 'query', label: Text('Queries', style: const TextStyle(fontSize: 11.5)), enabled: schema.queryType != null),
                    ButtonSegment(value: 'mutation', label: Text('Mutations', style: const TextStyle(fontSize: 11.5)), enabled: schema.mutationType != null),
                    const ButtonSegment(value: 'types', label: Text('Types', style: TextStyle(fontSize: 11.5))),
                  ],
                  selected: {_vm.section == 'subscription' ? 'query' : _vm.section},
                  onSelectionChanged: (s) => _vm.setSection(s.first),
                ),
                const SizedBox(height: 8),
                TextField(controller: _filter, decoration: const InputDecoration(hintText: 'Filter', prefixIcon: Icon(Icons.search, size: 16)), onChanged: (_) => setState(() {})),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: ListView(
              children: [
                for (final f in fields)
                  ListTile(
                    dense: true,
                    selected: identical(_vm.selectedField, f),
                    title: Text(f.name, style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w600, decoration: f.isDeprecated ? TextDecoration.lineThrough : null)),
                    subtitle: Text('${f.args.isEmpty ? '' : '(${f.args.length} args) '}→ ${f.type}', style: context.textStyles.caption.copyWith(color: colors.secondaryText), overflow: TextOverflow.ellipsis),
                    onTap: () => _vm.selectField(f),
                  ),
                for (final t in types)
                  ListTile(
                    dense: true,
                    selected: _vm.selectedType == t.name,
                    leading: _KindBadge(t.kind),
                    title: Text(t.name, style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w600)),
                    onTap: () => _vm.openType(t.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(BuildContext context, GqlSchema schema) {
    final colors = context.colors;
    final field = _vm.selectedField;
    final type = _vm.selectedType == null ? null : schema.type(_vm.selectedType!);
    Widget body;
    if (field != null) {
      final op = GqlQueryBuilder.forField(schema, _vm.section == 'mutation' ? 'mutation' : 'query', field);
      body = ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(field.name, style: context.textStyles.heading),
          if (field.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(field.description, style: context.textStyles.body.copyWith(color: colors.secondaryText))),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('returns ', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
              _TypeLink(field.type, onOpen: _vm.openType),
            ],
          ),
          if (field.args.isNotEmpty) ...[
            const SizedBox(height: 12),
            ToolSection(title: 'Arguments', child: Column(children: [for (final a in field.args) _ArgRow(a, onOpen: _vm.openType)])),
          ],
          const SizedBox(height: 8),
          ToolSection(
            title: 'Generated operation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 190, child: CodeBlock(text: op.query, label: 'GraphQL')),
                if (field.args.isNotEmpty) ...[const SizedBox(height: 8), SizedBox(height: 120, child: CodeBlock(text: op.variables, label: 'Variables'))],
                if (widget.onUse != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () {
                          widget.onUse!(op.query, field.args.isEmpty ? '{}' : op.variables);
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.input, size: 16),
                        label: const Text('Use in request'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    } else if (type != null) {
      body = ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            if (_vm.canGoBack) IconButton(icon: const Icon(Icons.arrow_back, size: 18), tooltip: 'Back', onPressed: _vm.back),
            _KindBadge(type.kind),
            const SizedBox(width: 8),
            Flexible(child: Text(type.name, style: context.textStyles.heading, overflow: TextOverflow.ellipsis)),
          ]),
          if (type.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(type.description, style: context.textStyles.body.copyWith(color: colors.secondaryText))),
          if (type.interfaces.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, children: [const Text('implements'), for (final i in type.interfaces) ActionChip(label: Text(i), onPressed: () => _vm.openType(i))])),
          if (type.possibleTypes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 4, children: [const Text('one of'), for (final i in type.possibleTypes) ActionChip(label: Text(i), onPressed: () => _vm.openType(i))])),
          if (type.fields.isNotEmpty) ToolSection(title: 'Fields', padding: const EdgeInsets.only(top: 12), child: Column(children: [for (final f in type.fields) _FieldRow(f, onOpen: _vm.openType)])),
          if (type.inputFields.isNotEmpty) ToolSection(title: 'Input fields', padding: const EdgeInsets.only(top: 12), child: Column(children: [for (final a in type.inputFields) _ArgRow(a, onOpen: _vm.openType)])),
          if (type.enumValues.isNotEmpty)
            ToolSection(
              title: 'Values',
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: [for (final e in type.enumValues) Tooltip(message: e.description, child: Chip(label: Text(e.name, style: context.textStyles.mono.copyWith(decoration: e.isDeprecated ? TextDecoration.lineThrough : null))))]),
            ),
        ],
      );
    } else {
      body = const EmptyHint(icon: Icons.touch_app_outlined, title: 'Select a field or a type', message: 'A query or mutation shows its arguments and a ready-to-run operation.');
    }
    return Container(
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;
  const _KindBadge(this.kind);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, color) = switch (kind) {
      'OBJECT' => ('type', colors.methodPut),
      'INPUT_OBJECT' => ('input', colors.methodPost),
      'ENUM' => ('enum', colors.methodPatch),
      'INTERFACE' => ('interface', colors.methodGet),
      'UNION' => ('union', colors.methodDelete),
      'SCALAR' => ('scalar', colors.secondaryText),
      _ => (kind.toLowerCase(), colors.secondaryText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _TypeLink extends StatelessWidget {
  final GqlTypeRef type;
  final void Function(String name) onOpen;
  const _TypeLink(this.type, {required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => onOpen(type.namedType),
      child: Text('$type', style: context.textStyles.mono.copyWith(color: colors.mainAccent, decoration: TextDecoration.underline)),
    );
  }
}

class _ArgRow extends StatelessWidget {
  final GqlArgument arg;
  final void Function(String name) onOpen;
  const _ArgRow(this.arg, {required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(builder: (context, c) {
        final name = Text(arg.name, style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w600));
        final defaultValue = arg.defaultValue == null ? null : Text('  = ${arg.defaultValue}', style: context.textStyles.mono.copyWith(color: colors.secondaryText));
        // Narrow: name, type and default wrap together and the description drops below them.
        if (c.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [name, _TypeLink(arg.type, onOpen: onOpen), ?defaultValue]),
              if (arg.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(arg.description, style: context.textStyles.caption.copyWith(color: colors.secondaryText))),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: name),
            _TypeLink(arg.type, onOpen: onOpen),
            ?defaultValue,
            if (arg.description.isNotEmpty) Expanded(child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(arg.description, style: context.textStyles.caption.copyWith(color: colors.secondaryText)))),
          ],
        );
      }),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final GqlField field;
  final void Function(String name) onOpen;
  const _FieldRow(this.field, {required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(builder: (context, c) {
        final name = Text(
          '${field.name}${field.args.isEmpty ? '' : '(…)'}',
          style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w600, decoration: field.isDeprecated ? TextDecoration.lineThrough : null),
        );
        // Narrow: name and type wrap together and the description drops below them.
        if (c.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [name, _TypeLink(field.type, onOpen: onOpen)]),
              if (field.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(field.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.textStyles.caption.copyWith(color: colors.secondaryText))),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 170, child: name),
            _TypeLink(field.type, onOpen: onOpen),
            if (field.description.isNotEmpty) Expanded(child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(field.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.textStyles.caption.copyWith(color: colors.secondaryText)))),
          ],
        );
      }),
    );
  }
}
