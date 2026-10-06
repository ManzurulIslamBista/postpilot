import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../data/odoo_schema_service.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/services/odoo_payload.dart';
import '../view_models/odoo_payload_view_model.dart';

/// One field of the payload form: a checkbox that says whether the field is sent, the field's name with its type and
/// label, and the editor that fits the type (text, number, date with a picker, a switch, the allowed values of a
/// selection, a record search for a many2one, a command list for an x2many). A required field is marked.
class OdooFieldRow extends StatefulWidget {
  final OdooField field;
  final OdooPayloadViewModel vm;
  const OdooFieldRow({super.key, required this.field, required this.vm});

  @override
  State<OdooFieldRow> createState() => _OdooFieldRowState();
}

class _OdooFieldRowState extends State<OdooFieldRow> {
  late final TextEditingController _c = TextEditingController(text: widget.vm.raw[widget.field.name] ?? '');
  final FocusNode _focus = FocusNode();
  int _search = 0;

  /// The id of the record picked for a many2one, kept when the box shows a `{{token}}` instead, so the portable forms
  /// of the same record stay on offer.
  int? _pickedId;

  OdooField get f => widget.field;
  OdooPayloadViewModel get vm => widget.vm;

  @override
  void didUpdateWidget(covariant OdooFieldRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Values can change from outside (a loaded record, the defaults): the box follows the form's state. What the
    // person types is stored as typed, so this never rewrites it while typing.
    final raw = vm.raw[f.name] ?? '';
    if (_c.text != raw) {
      _c.value = TextEditingValue(text: raw, selection: TextSelection.collapsed(offset: raw.length));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _textual => const {'char', 'text', 'html'}.contains(f.type);

  /// Ticking the box sends the field with the value its type starts from; unticking takes it out of the payload.
  void _toggle(bool on) {
    if (!on) {
      _c.clear();
      vm.unset(f.name);
      return;
    }
    switch (f.type) {
      case 'boolean':
        vm.setValue(f.name, false);
      case 'selection' when f.selection.isNotEmpty:
        vm.setValue(f.name, f.selection.first.$1);
      case 'char' || 'text' || 'html':
        vm.setRaw(f.name, _c.text);
      case 'integer' || 'float' || 'monetary':
        _c.text = _c.text.trim().isEmpty ? '0' : _c.text;
        vm.setRaw(f.name, _c.text);
      default:
        // A record, a command list, a date: there is nothing to start from, so the person is taken to the box.
        _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSet = vm.isSet(f.name);
    final error = vm.errors[f.name];
    final missing = f.required && !isSet && vm.method == 'create' && !(vm.defaults?.contains(f.name) ?? false);
    final typeLine = '${f.type}${f.relation == null ? '' : ' → ${f.relation}'} · ${f.label}${f.readonly ? ' · read-only' : ''}';
    final label = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          visualDensity: VisualDensity.compact,
          value: isSet,
          onChanged: (v) => _toggle(v ?? false),
        ),
        Expanded(
          child: Tooltip(
            message: f.help ?? typeLine,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(f.name, overflow: TextOverflow.ellipsis, style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w700))),
                      if (f.required) Text(' *', style: TextStyle(color: colors.statusError, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Text(typeLine, overflow: TextOverflow.ellipsis, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: missing ? colors.statusError.withValues(alpha: 0.05) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: missing ? colors.statusError.withValues(alpha: 0.35) : colors.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final editor = _editor(context, error);
          if (box.maxWidth >= 560) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 230, child: label), const SizedBox(width: 8), Expanded(child: editor)]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label, Padding(padding: const EdgeInsets.fromLTRB(8, 0, 4, 4), child: editor)]);
        },
      ),
    );
  }

  Widget _editor(BuildContext context, String? error) {
    switch (f.type) {
      case 'boolean':
        return Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: vm.values[f.name] == true, onChanged: (v) => vm.setValue(f.name, v)),
              Text(!vm.isSet(f.name) ? 'not sent' : (vm.values[f.name] == true ? 'true' : 'false'), style: context.textStyles.caption),
            ],
          ),
        );
      case 'selection' when f.selection.isNotEmpty:
        final current = vm.values[f.name];
        return DropdownButtonFormField<String>(
          key: ValueKey('${f.name}|$current'),
          initialValue: f.selection.any((s) => s.$1 == current) ? '$current' : null,
          isExpanded: true,
          isDense: true,
          decoration: InputDecoration(isDense: true, hintText: 'Not sent', errorText: error),
          items: [for (final s in f.selection) DropdownMenuItem(value: s.$1, child: Text('${s.$1} — ${s.$2}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => v == null ? vm.unset(f.name) : vm.setValue(f.name, v),
        );
      case 'many2one':
        return _many2one(context, error);
      case 'one2many' || 'many2many':
        return OdooCommandsEditor(field: f, vm: vm);
      case 'date' || 'datetime':
        final withTime = f.type == 'datetime';
        return TextField(
          controller: _c,
          focusNode: _focus,
          style: context.textStyles.mono,
          decoration: InputDecoration(
            isDense: true,
            hintText: withTime ? 'YYYY-MM-DD HH:MM:SS (UTC)' : 'YYYY-MM-DD',
            errorText: error,
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              tooltip: withTime ? 'Pick a date and time' : 'Pick a date',
              onPressed: () => _pickDate(withTime: withTime),
            ),
          ),
          onChanged: (t) => vm.setRaw(f.name, t),
        );
      default:
        final numeric = f.isNumeric;
        return TextField(
          controller: _c,
          focusNode: _focus,
          style: numeric ? context.textStyles.mono : context.textStyles.body,
          minLines: f.type == 'text' || f.type == 'html' ? 2 : 1,
          maxLines: f.type == 'text' || f.type == 'html' ? 6 : 1,
          keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
          decoration: InputDecoration(
            isDense: true,
            hintText: _textual ? (f.required ? 'Required' : 'Not sent') : (numeric ? '0' : (f.type == 'json' ? '{"key": "value"}' : 'Not sent')),
            errorText: error,
          ),
          onChanged: (t) => vm.setRaw(f.name, t),
        );
    }
  }

  Future<void> _pickDate({required bool withTime}) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final current = DateTime.tryParse(_c.text.trim().replaceFirst(' ', 'T'));
    final date = await showDatePicker(context: context, initialDate: current ?? now, firstDate: DateTime(1900), lastDate: DateTime(2200));
    if (date == null || !mounted) return;
    var text = '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
    if (withTime) {
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current ?? now));
      if (time == null || !mounted) return;
      text += ' ${two(time.hour)}:${two(time.minute)}:00';
    }
    _c.text = text;
    vm.setRaw(f.name, text);
  }

  // --- many2one --------------------------------------------------------------------------------------------------

  Widget _many2one(BuildContext context, String? error) {
    final colors = context.colors;
    final relation = f.relation;
    final picked = vm.pickedNames[f.name];
    final value = vm.values[f.name];
    final id = value is int ? value : _pickedId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RawAutocomplete<OdooRecordRef>(
          textEditingController: _c,
          focusNode: _focus,
          displayStringForOption: (o) => '${o.id}',
          optionsBuilder: (value) async {
            final text = value.text.trim();
            if (relation == null || text.length < 2 || int.tryParse(text) != null || text.startsWith('{{')) return const <OdooRecordRef>[];
            final mine = ++_search;
            // Wait for a pause in typing before asking the server.
            await Future<void>.delayed(const Duration(milliseconds: 300));
            if (mine != _search) return const <OdooRecordRef>[];
            return vm.searchRecords(relation, text);
          },
          onSelected: (o) {
            _pickedId = o.id;
            vm.setValue(f.name, o.id, text: '${o.id}', pickedName: o.name);
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
            controller: controller,
            focusNode: focusNode,
            style: context.textStyles.mono,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Type a name to search${relation == null ? '' : ' $relation'}, or an id, or {{xmlid:module.name}}',
              errorText: error,
              suffixIcon: picked == null || (id == null && value is! OdooToken) ? null : _portableMenu(relation, id, picked),
            ),
            onChanged: (t) {
              final text = t.trim();
              if (text.isEmpty) {
                _pickedId = null;
                vm.unset(f.name);
              } else if (int.tryParse(text) != null || OdooToken.tryParse(text) != null) {
                if (int.tryParse(text) != null && int.parse(text) != _pickedId) _pickedId = null;
                vm.setRaw(f.name, t);
              } else {
                vm.setTyping(f.name, t);
              }
            },
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              color: colors.surfaceElevated,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(dense: true, title: Text(o.name, overflow: TextOverflow.ellipsis), subtitle: Text('id ${o.id}', style: context.textStyles.mono), onTap: () => onSelected(o)),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (picked != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${id == null ? '' : '#$id · '}$picked', overflow: TextOverflow.ellipsis, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
          ),
      ],
    );
  }

  /// The same record written so that it works on every database: its XML-ID, or its name, looked up when sent.
  Widget _portableMenu(String? relation, int? id, String name) => PopupMenuButton<String>(
        icon: const Icon(Icons.link, size: 18),
        tooltip: 'Write this reference so it works on every database',
        onSelected: (choice) async {
          final messenger = ScaffoldMessenger.of(context);
          if (choice == 'id' && id != null) {
            vm.setValue(f.name, id, text: '$id', pickedName: name);
          } else if (choice == 'name' && relation != null) {
            final token = '{{ref:$relation:$name}}';
            vm.setValue(f.name, OdooToken(token), text: token, pickedName: name);
          } else if (choice == 'xmlid' && relation != null && id != null) {
            final xmlId = await vm.xmlIdOf(relation, id);
            if (xmlId == null) {
              messenger.showSnackBar(const SnackBar(content: Text('This record has no XML-ID (or this user may not read ir.model.data): use its name instead.')));
              return;
            }
            final token = '{{xmlid:$xmlId}}';
            if (mounted) vm.setValue(f.name, OdooToken(token), text: token, pickedName: name);
          }
        },
        itemBuilder: (_) => [
          if (id != null) PopupMenuItem(value: 'id', child: Text('Use the id ($id)')),
          const PopupMenuItem(value: 'xmlid', child: Text('Use its XML-ID, resolved when sent')),
          const PopupMenuItem(value: 'name', child: Text('Use its name, resolved when sent')),
        ],
      );
}

/// The command list of a one2many / many2many field as readable rows ("Link record 14", "Create a new record: {...}"),
/// with the commands Odoo knows: create, update, delete, unlink, link, clear and set.
class OdooCommandsEditor extends StatelessWidget {
  final OdooField field;
  final OdooPayloadViewModel vm;
  const OdooCommandsEditor({super.key, required this.field, required this.vm});

  List<X2ManyCommand> get _commands => [for (final c in (vm.values[field.name] as List? ?? const [])) c as X2ManyCommand];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final commands = _commands;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (commands.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('Not sent', style: context.textStyles.caption.copyWith(color: colors.secondaryText))),
        for (var i = 0; i < commands.length; i++)
          Container(
            key: ValueKey('${field.name}-command-$i-${commands[i].summary}'),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(color: colors.appBackground, borderRadius: BorderRadius.circular(8), border: Border.all(color: colors.borderSubtle)),
            child: Row(
              children: [
                Expanded(child: Text(commands[i].summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.textStyles.mono.copyWith(fontSize: 12))),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Edit',
                  onPressed: () async {
                    final edited = await showOdooCommandDialog(context, field: field, vm: vm, existing: commands[i]);
                    if (edited != null) vm.setCommands(field.name, [...commands]..[i] = edited);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Remove',
                  onPressed: () => vm.setCommands(field.name, [...commands]..removeAt(i)),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                final added = await showOdooCommandDialog(context, field: field, vm: vm);
                if (added != null) vm.setCommands(field.name, [...commands, added]);
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add command'),
            ),
            if (commands.isNotEmpty)
              TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => vm.setCommands(field.name, const []), child: const Text('Clear')),
          ],
        ),
      ],
    );
  }
}

const _commandKinds = <int, String>{
  0: 'Create a new record',
  1: 'Update a linked record',
  2: 'Delete a record',
  3: 'Unlink a record (it stays)',
  4: 'Link an existing record',
  5: 'Unlink all records',
  6: 'Replace all with these records',
};

/// Builds or edits one x2many command. The record ids can be searched by name; `{{xmlid:...}}` and `{{ref:...}}` are
/// accepted wherever an id goes.
Future<X2ManyCommand?> showOdooCommandDialog(
  BuildContext context, {
  required OdooField field,
  required OdooPayloadViewModel vm,
  X2ManyCommand? existing,
}) =>
    showDialog<X2ManyCommand>(context: context, builder: (_) => _CommandDialog(field: field, vm: vm, existing: existing));

class _CommandDialog extends StatefulWidget {
  final OdooField field;
  final OdooPayloadViewModel vm;
  final X2ManyCommand? existing;
  const _CommandDialog({required this.field, required this.vm, this.existing});

  @override
  State<_CommandDialog> createState() => _CommandDialogState();
}

class _CommandDialogState extends State<_CommandDialog> {
  late int _code = widget.existing?.code ?? (widget.field.type == 'many2many' ? 4 : 0);
  late final TextEditingController _id = TextEditingController(text: _initialId());
  late final TextEditingController _ids = TextEditingController(text: _initialIds());
  late final TextEditingController _vals = TextEditingController(text: _initialVals());
  final FocusNode _idFocus = FocusNode();
  int _search = 0;
  String? _error;

  String _initialId() {
    final c = widget.existing;
    final id = switch (c) {
      UpdateCommand() => c.id,
      DeleteCommand() => c.id,
      UnlinkCommand() => c.id,
      LinkCommand() => c.id,
      _ => null,
    };
    return id == null ? '' : '$id';
  }

  String _initialIds() {
    final c = widget.existing;
    return c is SetCommand ? c.ids.join(', ') : '';
  }

  String _initialVals() {
    final c = widget.existing;
    final vals = switch (c) {
      CreateCommand() => c.vals,
      UpdateCommand() => c.vals,
      _ => const <String, Object?>{},
    };
    return vals.isEmpty ? '{}' : OdooPayload.encodeValue(vals);
  }

  @override
  void dispose() {
    _id.dispose();
    _ids.dispose();
    _vals.dispose();
    _idFocus.dispose();
    super.dispose();
  }

  Object? _readId() {
    final text = _id.text.trim();
    return int.tryParse(text) ?? OdooToken.tryParse(text);
  }

  void _save() {
    X2ManyCommand? command;
    String? error;
    Map<String, Object?>? vals() {
      final read = OdooPayload.decodeValue(_vals.text.trim().isEmpty ? '{}' : _vals.text);
      if (read.error != null) {
        error = 'The values are not valid JSON: ${read.error}';
        return null;
      }
      if (read.value is! Map) {
        error = 'The values must be a JSON object such as {"name": "Bob"}.';
        return null;
      }
      return Map<String, Object?>.from(read.value as Map);
    }

    final id = _readId();
    switch (_code) {
      case 0:
        final v = vals();
        if (v != null) command = CreateCommand(v);
      case 1:
        final v = vals();
        if (id == null) {
          error = 'Enter the id of the record to update.';
        } else if (v != null) {
          command = UpdateCommand(id, v);
        }
      case 2:
        id == null ? error = 'Enter the id of the record to delete.' : command = DeleteCommand(id);
      case 3:
        id == null ? error = 'Enter the id of the record to unlink.' : command = UnlinkCommand(id);
      case 4:
        id == null ? error = 'Enter the id of the record to link.' : command = LinkCommand(id);
      case 5:
        command = const ClearCommand();
      case 6:
        final parsed = OdooPayload.parseIds(_ids.text);
        if (parsed.error != null) {
          error = parsed.error;
        } else {
          command = SetCommand(parsed.ids);
        }
    }
    if (command == null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, command);
  }

  /// Search by name for the id fields.
  Future<Iterable<OdooRecordRef>> _options(String text) async {
    final relation = widget.field.relation;
    final t = text.trim();
    if (relation == null || t.length < 2 || int.tryParse(t) != null || t.startsWith('{{')) return const [];
    final mine = ++_search;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mine != _search) return const [];
    return widget.vm.searchRecords(relation, t);
  }

  Widget _idField(TextEditingController controller, String label, {required void Function(OdooRecordRef) onPick}) => RawAutocomplete<OdooRecordRef>(
        textEditingController: controller,
        focusNode: _idFocus,
        optionsBuilder: (v) => _options(v.text),
        displayStringForOption: (o) => '${o.id}',
        onSelected: onPick,
        fieldViewBuilder: (context, c, focus, submit) => TextField(
          controller: c,
          focusNode: focus,
          style: context.textStyles.mono,
          decoration: InputDecoration(labelText: label, helperText: 'An id, a name to search, or {{xmlid:module.name}}'),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            color: context.colors.surfaceElevated,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [for (final o in options) ListTile(dense: true, title: Text(o.name, overflow: TextOverflow.ellipsis), subtitle: Text('id ${o.id}'), onTap: () => onSelected(o))],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final needsId = const {1, 2, 3, 4}.contains(_code);
    final needsVals = _code == 0 || _code == 1;
    return AlertDialog(
      title: Text('${widget.existing == null ? 'Add' : 'Edit'} a command for ${widget.field.name}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _code,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Command'),
                items: [for (final e in _commandKinds.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() {
                  _code = v ?? _code;
                  _error = null;
                }),
              ),
              if (needsId) ...[
                const SizedBox(height: 10),
                _idField(_id, 'Record id', onPick: (o) => _id.text = '${o.id}'),
              ],
              if (_code == 6) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _ids,
                  style: context.textStyles.mono,
                  decoration: const InputDecoration(labelText: 'Record ids', helperText: 'Numbers separated by commas, or {{xmlid:module.name}} tokens'),
                ),
              ],
              if (needsVals) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _vals,
                  minLines: 4,
                  maxLines: 10,
                  style: context.textStyles.mono,
                  decoration: InputDecoration(
                    labelText: 'Values (JSON)',
                    helperText: 'The fields of the ${widget.field.relation ?? 'related'} record, for example {"name": "Bob"}',
                  ),
                ),
              ],
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.colors.statusError))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: Text(widget.existing == null ? 'Add' : 'Save')),
      ],
    );
  }
}
