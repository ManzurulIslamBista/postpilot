import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../response_tools/domain/services/json_table.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/services/odoo_domain.dart';
import '../view_models/odoo_studio_view_model.dart';

/// Browse a model: its fields (type, required, relation), pick the ones you
/// need, and run a real search to see the rows. The chosen fields feed the
/// ready-made requests and the Dart model.
class OdooExplorerTab extends StatefulWidget {
  final OdooStudioViewModel viewModel;
  const OdooExplorerTab({super.key, required this.viewModel});

  @override
  State<OdooExplorerTab> createState() => _OdooExplorerTabState();
}

class _OdooExplorerTabState extends State<OdooExplorerTab> {
  final _modelField = TextEditingController();
  final _filter = TextEditingController();
  final _domain = TextEditingController();
  int _limit = 20;
  String? _domainError;

  OdooStudioViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _modelField.text = _vm.model;
    _domain.text = _vm.domainText;
  }

  @override
  void dispose() {
    _modelField.dispose();
    _filter.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _pasteFields() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste a fields_get response'),
        content: SizedBox(
          width: 520,
          child: TextField(controller: controller, autofocus: true, minLines: 8, maxLines: 14, style: context.textStyles.mono, decoration: const InputDecoration(hintText: '{"id": {"type": "integer", …}, …}')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Use')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    if (_modelField.text.trim().isEmpty) _modelField.text = 'x.model';
    if (!_vm.useFieldsJson(_modelField.text, text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That doesn't look like a fields_get response")));
    }
  }

  void _search() {
    final tree = OdooDomain.parseText(_domain.text);
    if (tree == null) {
      setState(() => _domainError = 'Not a valid domain. Use JSON like [["name","ilike","a"]] or Python tuples.');
      return;
    }
    setState(() => _domainError = null);
    _vm.setDomainText(_domain.text);
    _vm.runSearch(domain: OdooDomain.toList(tree), limit: _limit);
  }

  String _cell(Object? v) {
    if (v is List && v.length == 2 && v.first is num && v[1] is String) return '${v[1]}';
    if (v == false) return '';
    return JsonTable.cell(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final info = _vm.info;
        final modelField = Autocomplete<String>(
                      optionsBuilder: (v) {
                        final q = v.text.trim().toLowerCase();
                        if (q.isEmpty) return const Iterable<String>.empty();
                        return _vm.modelNames.where((m) => m.contains(q) || (_vm.modelLabels[m] ?? '').toLowerCase().contains(q)).take(30);
                      },
                      displayStringForOption: (o) => o,
                      onSelected: (v) {
                        _modelField.text = v;
                        _vm.loadFields(v);
                      },
                      fieldViewBuilder: (context, controller, focus, onSubmit) {
                        if (controller.text.isEmpty && _modelField.text.isNotEmpty) controller.text = _modelField.text;
                        return TextField(
                          controller: controller,
                          focusNode: focus,
                          decoration: InputDecoration(
                            labelText: 'Model',
                            hintText: 'res.partner',
                            helperText: _vm.modelNames.isEmpty ? 'Press "Load models" to get suggestions from the server' : '${_vm.modelNames.length} models available',
                            prefixIcon: const Icon(Icons.table_chart_outlined, size: 18),
                          ),
                          onChanged: (v) => _modelField.text = v,
                          onSubmitted: (v) => _vm.loadFields(v),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(10),
                          color: context.colors.surfaceElevated,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final o in options)
                                  ListTile(dense: true, title: Text(o, style: context.textStyles.mono), subtitle: Text(_vm.modelLabels[o] ?? ''), onTap: () => onSelected(o)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
        final modelActions = Wrap(
                      spacing: 6,
                      children: [
                        OutlinedButton(onPressed: _vm.isBusy ? null : _vm.loadModels, child: const Text('Load models')),
                        FilledButton(
                          onPressed: _vm.isBusy ? null : () => _vm.loadFields(_modelField.text),
                          child: BusyLabel(busy: _vm.busyLabel?.startsWith('Reading') ?? false, label: 'Read fields', busyLabel: 'Reading…'),
                        ),
                        TextButton(onPressed: _pasteFields, child: const Text('Paste fields_get')),
                      ],
                    );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final narrow = box.maxWidth < 640;
                  if (narrow) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [modelField, const SizedBox(height: 8), modelActions]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: modelField), const SizedBox(width: 8), Padding(padding: const EdgeInsets.only(top: 2), child: modelActions)],
                  );
                },
              ),
              if (_vm.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(kind: BannerKind.error, title: _vm.errorInfo?.title, message: _vm.errorInfo?.hint ?? _vm.error!)),
              const SizedBox(height: 10),
              Expanded(
                child: info == null
                    ? const EmptyHint(
                        icon: Icons.travel_explore,
                        title: 'Explore an Odoo model',
                        message: 'Type a model such as res.partner and press "Read fields". Tick the fields you need, then run a search to see real records.',
                      )
                    : _body(info),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(OdooModelInfo info) {
    final colors = context.colors;
    final q = _filter.text.trim().toLowerCase();
    final fields = [for (final f in info.fields) if (q.isEmpty || f.name.contains(q) || f.label.toLowerCase().contains(q)) f];
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760;
        final list = Container(
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(child: TextField(controller: _filter, decoration: InputDecoration(hintText: 'Filter ${info.fields.length} fields', prefixIcon: const Icon(Icons.search, size: 16)), onChanged: (_) => setState(() {}))),
                    PopupMenuButton<bool>(
                      tooltip: 'Select fields',
                      icon: const Icon(Icons.checklist, size: 18),
                      onSelected: _vm.setAllFields,
                      itemBuilder: (_) => const [PopupMenuItem(value: true, child: Text('Select all stored fields')), PopupMenuItem(value: false, child: Text('Clear selection'))],
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border),
              Expanded(
                child: ListView.builder(
                  itemCount: fields.length,
                  itemBuilder: (context, i) {
                    final f = fields[i];
                    return CheckboxListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _vm.chosenFields.contains(f.name),
                      onChanged: (v) => _vm.toggleField(f.name, v ?? false),
                      title: Row(
                        children: [
                          Flexible(child: Text(f.name, overflow: TextOverflow.ellipsis, style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w600))),
                          if (f.required) Text(' *', style: TextStyle(color: colors.statusError, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      subtitle: Text(
                        '${f.type}${f.relation != null ? ' → ${f.relation}' : ''} · ${f.label}${f.stored ? '' : ' · computed'}${f.readonly ? ' · read-only' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
        final results = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _domain,
                    style: context.textStyles.mono,
                    decoration: InputDecoration(labelText: 'Domain', hintText: '[["is_company","=",true]]', errorText: _domainError),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                DropdownButton<int>(
                  value: _limit,
                  isDense: true,
                  items: [for (final n in const [5, 20, 50, 100]) DropdownMenuItem(value: n, child: Text('limit $n'))],
                  onChanged: (v) => setState(() => _limit = v ?? 20),
                ),
                FilledButton.icon(
                  onPressed: _vm.isBusy ? null : _search,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text('Search (${_vm.chosenFields.length} fields)'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _vm.rows.isEmpty
                  ? EmptyHint(icon: Icons.dataset_outlined, title: 'No rows yet', message: 'Search ${info.model} to see records. ${_vm.lastDuration == null ? '' : 'Last call took ${_vm.lastDuration!.inMilliseconds} ms.'}')
                  : Container(
                      decoration: BoxDecoration(color: colors.appBackground, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
                      clipBehavior: Clip.antiAlias,
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowHeight: 36,
                              dataRowMinHeight: 32,
                              dataRowMaxHeight: 32,
                              columnSpacing: 20,
                              headingTextStyle: context.textStyles.caption.copyWith(fontWeight: FontWeight.w700, color: colors.syntaxKey),
                              columns: [for (final k in _vm.rows.first.keys) DataColumn(label: Text(k))],
                              rows: [
                                for (final row in _vm.rows)
                                  DataRow(cells: [
                                    for (final k in _vm.rows.first.keys)
                                      DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: Text(_cell(row[k]), overflow: TextOverflow.ellipsis, style: context.textStyles.mono.copyWith(fontSize: 12)))),
                                  ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        );
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SizedBox(width: 320, child: list), const SizedBox(width: 12), Expanded(child: results)])
            : Column(children: [Expanded(flex: 2, child: list), const SizedBox(height: 10), Expanded(flex: 3, child: results)]);
      },
    );
  }
}
