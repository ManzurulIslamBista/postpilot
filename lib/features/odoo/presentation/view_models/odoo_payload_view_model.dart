import 'package:flutter/foundation.dart';
import '../../data/odoo_schema_service.dart';
import '../../domain/entities/odoo_connection.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/entities/odoo_request_shape.dart';
import '../../domain/services/odoo_json2.dart';
import '../../domain/services/odoo_jsonrpc.dart';
import '../../domain/services/odoo_payload.dart';
import '../../domain/services/odoo_request_checker.dart';
import 'odoo_studio_view_model.dart';

/// State behind the Payload tab: the form of a model's writable fields, the typed values, and the body of the
/// `create` / `write` / `copy` request they make. The form is generated from `fields_get`; defaults come from
/// `default_get`; a many2one is picked by a name search on the live server; an existing record can be loaded into it.
final class OdooPayloadViewModel with ChangeNotifier {
  final OdooStudioViewModel _studio;
  OdooPayloadViewModel(this._studio);

  static const methods = ['create', 'write', 'copy'];

  String model = '';
  OdooModelInfo? info;
  String method = 'create';
  bool showReadonly = false;

  /// The typed value of each field that is part of the payload; a field with no entry is not sent.
  final Map<String, Object?> values = {};

  /// What was typed for each field, kept as typed so a half-written number is not rewritten while typing.
  final Map<String, String> raw = {};

  /// Why what was typed for a field is not a valid value.
  final Map<String, String> errors = {};

  /// The name of the record picked for a many2one field, to show beside its id.
  final Map<String, String> pickedNames = {};

  /// The ids of a `write` or `copy`, as typed.
  String idsText = '';
  String? idsError;

  /// The fields Odoo fills in by itself (`default_get`), so the checker does not call them missing.
  Set<String>? defaults;

  bool isBusy = false;
  String? busyLabel;
  String? error;

  /// Something worth saying that is not a failure ("Loaded record 7").
  String? notice;

  /// What the last check found; null until [check] ran.
  List<OdooProblem>? problems;

  OdooConnection get connection => _studio.connection;

  /// The fields the form offers: required first.
  List<OdooField> get fields => info == null ? const [] : OdooPayload.editableFields(info!, includeReadonly: showReadonly);

  bool isSet(String field) => values.containsKey(field);

  Future<T?> _run<T>(String label, Future<T> Function() body) async {
    if (isBusy) return null;
    isBusy = true;
    busyLabel = label;
    error = null;
    notice = null;
    notifyListeners();
    try {
      return await body();
    } catch (e) {
      error = '$e';
      return null;
    } finally {
      isBusy = false;
      busyLabel = null;
      notifyListeners();
    }
  }

  /// Reads the fields of [name] (from the memory unless [refresh]) and starts a new payload for it. For `create` the
  /// defaults Odoo would give are filled in.
  Future<void> loadModel(String name, {bool refresh = false}) => _run('Reading fields of $name', () async {
        final missing = connection.missing;
        if (missing != null) {
          error = missing;
          return;
        }
        final found = await _studio.schema.fields(connection, name, refresh: refresh);
        if (!found.ok) {
          error = found.error;
          return;
        }
        model = name.trim();
        info = found.value;
        _clearValues();
        problems = null;
        await _loadDefaults();
      });

  void _clearValues() {
    values.clear();
    raw.clear();
    errors.clear();
    pickedNames.clear();
    defaults = null;
  }

  Future<void> _loadDefaults() async {
    final model = info;
    if (model == null) return;
    final names = [for (final f in OdooPayload.editableFields(model, includeReadonly: true)) f.name];
    final found = await _studio.schema.defaultGet(connection, model.model, names);
    if (!found.ok) {
      defaults = null; // not read: the checker then says "unless Odoo has a default"
      return;
    }
    defaults = found.value!.keys.toSet();
    if (method != 'create') return;
    for (final entry in OdooPayload.fromDefaults(model, found.value!).entries) {
      final f = model.field(entry.key);
      if (f == null || !OdooPayload.isEditable(f, includeReadonly: showReadonly)) continue;
      values[entry.key] = entry.value;
      raw[entry.key] = entry.value is List ? '' : OdooPayload.format(f, entry.value);
    }
  }

  /// Fills in the defaults again (after a clear).
  Future<void> fillDefaults() => _run('Reading defaults', _loadDefaults);

  void setMethod(String value) {
    if (value == method || !methods.contains(value)) return;
    method = value;
    problems = null;
    notifyListeners();
  }

  void setShowReadonly(bool value) {
    showReadonly = value;
    if (!value && info != null) {
      // A read-only field that was filled in (a loaded record) leaves with the switch.
      for (final name in [for (final f in info!.fields) if (f.readonly) f.name]) {
        values.remove(name);
        raw.remove(name);
        errors.remove(name);
      }
    }
    notifyListeners();
  }

  void setIds(String text) {
    idsText = text;
    idsError = OdooPayload.parseIds(text).error;
    notifyListeners();
  }

  /// A field's text changed. An empty text takes the field out of the payload (except for text fields, where empty is
  /// a value), a valid one sets it, an invalid one is reported and leaves the field out.
  void setRaw(String name, String text) {
    final f = info?.field(name);
    if (f == null) return;
    raw[name] = text;
    problems = null;
    if (text.trim().isEmpty && f.type != 'char' && f.type != 'text' && f.type != 'html' && f.type != 'boolean') {
      values.remove(name);
      errors.remove(name);
      pickedNames.remove(name);
    } else {
      final parsed = OdooPayload.parse(f, text);
      if (parsed.error != null) {
        values.remove(name);
        errors[name] = parsed.error!;
      } else {
        values[name] = parsed.value;
        errors.remove(name);
        pickedNames.remove(name);
      }
    }
    notifyListeners();
  }

  /// A name is being typed into a many2one box to search for a record: the field has no value until one is picked,
  /// and that is not an error yet.
  void setTyping(String name, String text) {
    raw[name] = text;
    values.remove(name);
    errors.remove(name);
    pickedNames.remove(name);
    problems = null;
    notifyListeners();
  }

  /// Sets a field to [value] picked rather than typed (a record, a switch); [text] is what its box shows.
  void setValue(String name, Object? value, {String? text, String? pickedName}) {
    final f = info?.field(name);
    values[name] = value;
    raw[name] = text ?? (f == null ? '$value' : OdooPayload.format(f, value));
    errors.remove(name);
    problems = null;
    if (pickedName != null) {
      pickedNames[name] = pickedName;
    } else {
      pickedNames.remove(name);
    }
    notifyListeners();
  }

  /// Takes a field out of the payload.
  void unset(String name) {
    values.remove(name);
    raw.remove(name);
    errors.remove(name);
    pickedNames.remove(name);
    problems = null;
    notifyListeners();
  }

  void setCommands(String name, List<X2ManyCommand> commands) {
    if (commands.isEmpty) {
      unset(name);
      return;
    }
    values[name] = commands;
    problems = null;
    notifyListeners();
  }

  /// A new, empty payload for the same model.
  Future<void> clear() async {
    _clearValues();
    idsText = '';
    idsError = null;
    problems = null;
    notifyListeners();
    if (info != null) await fillDefaults();
  }

  // --- lookups the form makes ------------------------------------------------------------------------------------

  /// The records of [relation] whose name matches [text], for a many2one box. Empty when the server refuses.
  Future<List<OdooRecordRef>> searchRecords(String relation, String text) async {
    if (text.trim().isEmpty) return const [];
    final found = await _studio.schema.nameSearch(connection, relation, text.trim());
    return found.value ?? const [];
  }

  /// The XML-ID of record [id] of [relation], when it has one: the portable way to point at it.
  Future<String?> xmlIdOf(String relation, int id) => _studio.schema.xmlIdOf(connection, relation, id);

  /// Reads record [id] and turns it into the values of the payload: the editable fields with their current values,
  /// many2one as ids, x2many as `[6, 0, ids]`. For `write` the id becomes the ids of the request.
  Future<void> loadRecord(int id) => _run('Reading record $id', () async {
        final model = info;
        if (model == null) {
          error = 'Choose a model first.';
          return;
        }
        final record = await _studio.schema.readRecord(connection, model.model, id, OdooPayload.readFields(model, includeReadonly: showReadonly));
        if (!record.ok) {
          error = record.error;
          return;
        }
        values.clear();
        raw.clear();
        errors.clear();
        pickedNames.clear();
        final loaded = OdooPayload.fromRecord(model, record.value!, includeReadonly: showReadonly);
        for (final entry in loaded.entries) {
          final f = model.field(entry.key)!;
          values[entry.key] = entry.value;
          raw[entry.key] = entry.value is List ? '' : OdooPayload.format(f, entry.value);
          // The name of a many2one, from the record that was just read, so the box shows more than a number.
          final original = record.value![entry.key];
          if (f.type == 'many2one' && original is List && original.length >= 2) pickedNames[entry.key] = '${original[1]}';
        }
        if (method == 'create') {
          idsText = '';
        } else {
          idsText = '$id';
          idsError = null;
        }
        problems = null;
        notice = 'Loaded record $id of ${model.model}: ${loaded.length} fields. Read-only, computed and Odoo-managed fields were left out.';
      });

  // --- the output -----------------------------------------------------------------------------------------------

  List<Object> get ids => OdooPayload.parseIds(idsText).ids;

  /// Required fields of the model that the payload does not set (create only), so the output can say what is missing.
  List<OdooField> get missingRequired {
    final model = info;
    if (model == null || method != 'create') return const [];
    return [
      for (final f in model.fields)
        if (f.required && f.stored && !f.isMagic && !values.containsKey(f.name) && !(defaults?.contains(f.name) ?? false)) f,
    ];
  }

  bool get hasErrors => errors.isNotEmpty || idsError != null;

  String get bodyText => model.isEmpty
      ? ''
      : OdooPayload.bodyText(protocol: connection.protocol, model: model, method: method, values: values, ids: ids);

  String get path => connection.protocol == OdooProtocol.json2 ? '/json/2/$model/$method' : OdooJsonRpc.callPath(model, method);

  /// The request the payload makes, ready to be saved into a collection.
  OdooRequestDraft? get draft {
    if (model.isEmpty) return null;
    final writes = method != 'create';
    return OdooRequestDraft(
      name: '${const {'create': 'Create', 'write': 'Update', 'copy': 'Copy'}[method]} $model (payload)',
      url: '{{${OdooVars.url}}}$path',
      headers: connection.protocol == OdooProtocol.json2 ? OdooJson2.headers() : OdooJsonRpc.headers(),
      bodyText: bodyText,
      note: 'Built in the payload builder of Odoo Studio from the fields of $model.'
          '${writes && ids.isEmpty ? ' Set the variable {{${OdooVars.recordId}}} to the id of the record first: it is deliberately left undefined, so this request fails until you do, instead of touching a record you did not choose.' : ''}'
          '${connection.protocol == OdooProtocol.jsonRpc ? ' Run the "Log in to Odoo" request of the collection first: it opens the session this request uses.' : ''}',
    );
  }

  /// Saves the payload as a request of [collectionId]; the new request's id, or null.
  Future<int?> saveAsRequest(int collectionId) async {
    final d = draft;
    if (d == null) return null;
    final id = await _studio.addRequest(collectionId, d);
    if (id != null) {
      notice = 'Added "${d.name}" to the collection.';
      notifyListeners();
    }
    return id;
  }

  /// Checks the payload against the live schema with the same rules as the Check tab.
  void check() {
    final model = info;
    if (model == null) return;
    final shape = OdooRequestShape.read('${connection.protocol == OdooProtocol.json2 ? '/json/2/' : '/web/dataset/call_kw/'}${model.model}/$method', bodyText);
    final read = shape.shape;
    if (read == null) {
      problems = [OdooProblem('shape', OdooProblemSeverity.error, shape.error ?? 'The payload could not be read.', 'body')];
    } else {
      problems = OdooRequestChecker.check(
        read,
        OdooCheckContext(
          info: model,
          modelExists: true,
          defaults: defaults,
          related: (m) => _studio.schema.cachedFields(connection, m),
        ),
      );
    }
    notifyListeners();
  }
}
