import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/code_block.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../domain/entities/odoo_connection.dart';
import '../view_models/odoo_payload_view_model.dart';
import '../view_models/odoo_studio_view_model.dart';
import 'odoo_field_editors.dart';
import 'odoo_problems_view.dart';

/// Build the body of a `create`, `write` or `copy` without writing JSON: the form is generated from the model's
/// `fields_get`, with the right editor per field type, required fields marked, read-only and computed fields left
/// out, defaults filled in from `default_get`, many2one fields picked by a name search on the live server and x2many
/// fields built from commands. The output is the exact body, ready to be saved as a request, and an existing record
/// can be loaded into it.
class OdooPayloadTab extends StatefulWidget {
  final OdooStudioViewModel viewModel;

  /// A payload view model to use (tests); one is made for the tab otherwise.
  final OdooPayloadViewModel? payload;
  const OdooPayloadTab({super.key, required this.viewModel, this.payload});

  @override
  State<OdooPayloadTab> createState() => _OdooPayloadTabState();
}

class _OdooPayloadTabState extends State<OdooPayloadTab> {
  late final OdooPayloadViewModel _vm = widget.payload ?? OdooPayloadViewModel(widget.viewModel);
  final _modelField = TextEditingController();
  final _filter = TextEditingController();
  bool _onlySet = false;
  int? _collectionId;

  /// On a narrow screen the form and the body do not fit together: one at a time, switched by a control.
  bool _showBody = false;

  OdooStudioViewModel get _studio => widget.viewModel;

  @override
  void initState() {
    super.initState();
    // The Explorer's model is the natural starting point.
    if (_vm.model.isEmpty && _studio.model.isNotEmpty && _studio.info != null) {
      _modelField.text = _studio.model;
      _vm.loadModel(_studio.model);
    } else {
      _modelField.text = _vm.model;
    }
  }

  @override
  void dispose() {
    if (widget.payload == null) _vm.dispose();
    _modelField.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _loadRecord() async {
    final controller = TextEditingController();
    final id = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Load a record of ${_vm.model}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Record id', hintText: '42'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) => int.tryParse(v.trim()) == null ? null : Navigator.pop(context, int.parse(v.trim())),
                ),
                const SizedBox(height: 10),
                Text(
                  'The record is read and becomes the values of the payload: read-only, computed and Odoo-managed fields are dropped, '
                  'a many2one pair [id, name] becomes its id, and a list of ids becomes [6, 0, ids].',
                  style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: int.tryParse(controller.text.trim()) == null ? null : () => Navigator.pop(context, int.parse(controller.text.trim())),
              child: const Text('Load'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (id != null) await _vm.loadRecord(id);
  }

  Future<void> _saveRequest() async {
    final collections = context.read<CollectionsViewModel>().collections;
    final id = collections.any((c) => c.id == _collectionId) ? _collectionId : collections.firstOrNull?.id;
    if (id == null) return;
    final created = await _vm.saveAsRequest(id);
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_vm.notice ?? 'Request added')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_vm, _studio]),
      builder: (context, _) {
        final header = _header(context);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (_vm.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(kind: BannerKind.error, message: _vm.error!)),
              if (_vm.notice != null) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(kind: BannerKind.success, message: _vm.notice!)),
              const SizedBox(height: 10),
              Expanded(
                child: _vm.info == null
                    ? const EmptyHint(
                        icon: Icons.dynamic_form_outlined,
                        title: 'Build a create or write payload',
                        message: 'Choose a model such as res.partner and press "Read fields". The form is made from the real fields of the model: '
                            'type the values, pick records by name, add x2many commands, and copy or save the exact body.',
                      )
                    : LayoutBuilder(
                        builder: (context, c) {
                          final form = _form(context);
                          final output = _output(context);
                          if (c.maxWidth >= 760) {
                            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 6, child: form), const SizedBox(width: 14), Expanded(flex: 4, child: output)]);
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SegmentedButton<bool>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(value: false, label: Text('Fields'), icon: Icon(Icons.edit_note, size: 16)),
                                  ButtonSegment(value: true, label: Text('Body'), icon: Icon(Icons.data_object, size: 16)),
                                ],
                                selected: {_showBody},
                                onSelectionChanged: (s) => setState(() => _showBody = s.first),
                              ),
                              const SizedBox(height: 10),
                              // Both stay built, so what was typed and where the list was scrolled to survive a switch.
                              Expanded(child: IndexedStack(index: _showBody ? 1 : 0, children: [form, output])),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final modelField = Autocomplete<String>(
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return _studio.modelNames.where((m) => m.contains(q) || (_studio.modelLabels[m] ?? '').toLowerCase().contains(q)).take(30);
      },
      onSelected: (v) {
        _modelField.text = v;
        _vm.loadModel(v);
      },
      fieldViewBuilder: (context, controller, focus, submit) {
        if (controller.text.isEmpty && _modelField.text.isNotEmpty) controller.text = _modelField.text;
        return TextField(
          controller: controller,
          focusNode: focus,
          decoration: InputDecoration(
            labelText: 'Model',
            hintText: 'res.partner',
            helperText: _studio.modelNames.isEmpty ? 'Press "Load models" for suggestions' : '${_studio.modelNames.length} models available',
            prefixIcon: const Icon(Icons.table_chart_outlined, size: 18),
          ),
          onChanged: (v) => _modelField.text = v,
          onSubmitted: (v) => _vm.loadModel(v),
        );
      },
    );
    final method = SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [for (final m in OdooPayloadViewModel.methods) ButtonSegment(value: m, label: Text(m))],
      selected: {_vm.method},
      onSelectionChanged: (s) {
        _vm.setMethod(s.first);
      },
    );
    final actions = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton(onPressed: _studio.isBusy ? null : _studio.loadModels, child: const Text('Load models')),
        FilledButton(
          onPressed: _vm.isBusy ? null : () => _vm.loadModel(_modelField.text),
          child: BusyLabel(busy: _vm.isBusy && (_vm.busyLabel?.startsWith('Reading fields') ?? false), label: 'Read fields', busyLabel: 'Reading…'),
        ),
        if (_vm.info != null) ...[
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Read the fields of ${_vm.model} again from the server',
            onPressed: _vm.isBusy ? null : () => _vm.loadModel(_vm.model, refresh: true),
          ),
          OutlinedButton.icon(onPressed: _vm.isBusy ? null : _loadRecord, icon: const Icon(Icons.download_outlined, size: 16), label: const Text('Load from record')),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 640) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [modelField, const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: method), const SizedBox(height: 8), actions]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: modelField), const SizedBox(width: 10), Padding(padding: const EdgeInsets.only(top: 6), child: method)]),
            const SizedBox(height: 8),
            actions,
          ],
        );
      },
    );
  }

  Widget _form(BuildContext context) {
    final colors = context.colors;
    final all = _vm.fields;
    final q = _filter.text.trim().toLowerCase();
    final shown = [
      for (final f in all)
        if ((q.isEmpty || f.name.contains(q) || f.label.toLowerCase().contains(q)) && (!_onlySet || _vm.isSet(f.name) || f.required)) f,
    ];
    return Container(
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _filter,
                    decoration: InputDecoration(isDense: true, hintText: 'Filter ${all.length} fields', prefixIcon: const Icon(Icons.search, size: 16)),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                FilterChip(label: const Text('Only fields I send'), visualDensity: VisualDensity.compact, selected: _onlySet, onSelected: (v) => setState(() => _onlySet = v)),
                FilterChip(label: const Text('Show read-only'), visualDensity: VisualDensity.compact, selected: _vm.showReadonly, onSelected: _vm.setShowReadonly),
                if (_vm.method == 'create')
                  TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: _vm.isBusy ? null : _vm.fillDefaults, child: const Text('Fill defaults')),
                TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: _vm.isBusy ? null : _vm.clear, child: const Text('Clear')),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          if (_vm.method != 'create') _idsBar(context),
          Expanded(
            child: shown.isEmpty
                ? const EmptyHint(icon: Icons.search_off, title: 'No field matches')
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => OdooFieldRow(key: ValueKey('${_vm.model}|${shown[i].name}'), field: shown[i], vm: _vm),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _idsBar(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: TextFormField(
        key: ValueKey('ids-${_vm.model}-${_vm.method}-${_vm.idsText}'),
        initialValue: _vm.idsText,
        style: context.textStyles.mono,
        decoration: InputDecoration(
          isDense: true,
          labelText: _vm.method == 'write' ? 'Records to write (ids)' : 'Record to copy (id)',
          helperText: 'Leave empty to use {{recordId}}, a variable that stays undefined until you set it',
          helperStyle: TextStyle(color: colors.secondaryText),
          errorText: _vm.idsError,
        ),
        onChanged: _vm.setIds,
      ),
    );
  }

  Widget _output(BuildContext context) {
    final colors = context.colors;
    final vm = _vm;
    final collections = context.watch<CollectionsViewModel>().collections;
    final missing = vm.missingRequired;
    final problems = vm.problems;
    final jsonRpc = vm.connection.protocol == OdooProtocol.jsonRpc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('POST {{odooUrl}}${vm.path}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textStyles.mono.copyWith(color: colors.mainAccent, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Expanded(child: CodeBlock(text: vm.bodyText, label: jsonRpc ? 'call_kw body · Odoo 18 and older' : 'JSON-2 body')),
        if (missing.isNotEmpty || vm.hasErrors)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InfoBanner(
              kind: vm.hasErrors ? BannerKind.error : BannerKind.warning,
              message: vm.hasErrors
                  ? 'Fix the fields marked in red: what they hold is not a valid value, so they are left out of the body.'
                  : 'Required and not set: ${missing.map((f) => f.name).join(', ')}.',
            ),
          ),
        if (problems != null)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SingleChildScrollView(child: OdooProblemsView(problems: problems)),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(onPressed: vm.check, icon: const Icon(Icons.fact_check_outlined, size: 16), label: const Text('Check')),
            if (collections.isNotEmpty) ...[
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  key: ValueKey(_collectionId),
                  initialValue: collections.any((c) => c.id == _collectionId) ? _collectionId : collections.first.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Collection', isDense: true),
                  items: [for (final c in collections) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _collectionId = v),
                ),
              ),
              FilledButton.icon(onPressed: vm.isBusy ? null : _saveRequest, icon: const Icon(Icons.add_task, size: 16), label: const Text('Create request from this')),
            ] else
              Text('Create a collection to save this as a request.', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
          ],
        ),
      ],
    );
  }
}
