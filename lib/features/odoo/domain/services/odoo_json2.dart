import 'dart:convert';

/// The environment variables an Odoo workspace is built on, so one request set
/// works for every database: switch environment, change nothing else.
abstract final class OdooVars {
  static const url = 'odooUrl';
  static const database = 'odooDb';
  static const apiKey = 'odooApiKey';

  /// `json2` (the default) or `jsonrpc` for an Odoo 18 or older server (see `OdooProtocol`).
  static const protocol = 'odooProtocol';

  /// The login and the password (or API key) of an Odoo 18 or older server, which opens a session instead of
  /// sending a bearer token.
  static const login = 'odooLogin';
  static const password = 'odooPassword';

  /// The record a ready-made write or delete request acts on. It is deliberately
  /// not defined anywhere: the request fails until someone sets it, instead of
  /// changing or deleting record 1 of whatever server the environment points at.
  static const recordId = 'recordId';
}

/// A request in Odoo's External JSON-2 API: `POST /json/2/<model>/<method>`,
/// `Authorization: bearer <API key>`, and a JSON body in which `ids` selects
/// records and every method parameter is passed by name.
final class OdooCall {
  final String model;
  final String method;

  /// Record ids for a recordset method (`read`, `write`, `unlink`); empty for model methods.
  final List<int> ids;

  /// Method arguments by name: `domain`, `fields`, `limit`, `vals`...
  final Map<String, Object?> params;
  final Map<String, Object?> context;

  /// Name of a `{{variable}}` that stands in for the record id in [bodyText], for
  /// requests saved ready-made. [body] (what is sent for a call run directly)
  /// is not affected; give it real [ids].
  final String? idsVariable;

  const OdooCall({
    required this.model,
    required this.method,
    this.ids = const [],
    this.params = const {},
    this.context = const {},
    this.idsVariable,
  });

  /// The body exactly as it is sent: `ids`, `context`, then the named arguments.
  Map<String, Object?> get body => {
        if (ids.isNotEmpty) 'ids': ids,
        if (context.isNotEmpty) 'context': context,
        ...params,
      };

  /// The body as text for a saved request. With [idsVariable] the id is the bare
  /// `{{variable}}` (`"ids": [{{recordId}}]`), which is valid JSON only once the
  /// variable has a value; unquoted, it can only ever be sent as a number.
  String get bodyText {
    const pretty = JsonEncoder.withIndent('  ');
    final variable = idsVariable;
    if (variable == null) return pretty.convert(body);
    const marker = '__postpilot_record_id__';
    final withMarker = {
      'ids': [marker],
      for (final e in body.entries)
        if (e.key != 'ids') e.key: e.value,
    };
    // The pretty printer puts the one id on a line of its own; `[{{recordId}}]` reads better in one piece.
    return pretty.convert(withMarker).replaceFirst(RegExp('\\[\\s*"$marker"\\s*\\]'), '[{{$variable}}]');
  }

  String get path => '/json/2/$model/$method';
}

/// A request ready to be saved into a collection.
final class OdooRequestDraft {
  final String name;
  final String url;
  final Map<String, String> headers;
  final String bodyText;
  final String? note;

  const OdooRequestDraft({required this.name, required this.url, required this.headers, required this.bodyText, this.note});
}

abstract final class OdooJson2 {
  /// Headers for every call. `X-Odoo-Database` is only needed on multi-database
  /// servers, but sending it is harmless on single-database ones.
  static Map<String, String> headers({
    String apiKey = '{{${OdooVars.apiKey}}}',
    String database = '{{${OdooVars.database}}}',
  }) =>
      {
        'Authorization': 'bearer $apiKey',
        'X-Odoo-Database': database,
        'Content-Type': 'application/json; charset=utf-8',
      };

  static OdooRequestDraft draft(OdooCall call, {String? name, String? note, String baseUrl = '{{${OdooVars.url}}}'}) =>
      OdooRequestDraft(
        name: name ?? '${call.model} · ${call.method}',
        url: '$baseUrl${call.path}',
        headers: headers(),
        bodyText: call.bodyText,
        note: note,
      );

  /// The request set offered for [model]: every common operation with a
  /// sensible example body to edit.
  static List<OdooRequestDraft> templatesFor(String model, {List<String> sampleFields = const ['display_name']}) => [
        for (final t in templateCalls(model, sampleFields: sampleFields)) draft(t.call, name: t.name, note: t.note),
      ];

  /// The calls behind [templatesFor], independent of the API they are written for: an Odoo 18 or older
  /// collection draws the same set in `call_kw` form (see `OdooJsonRpc.templatesFor`).
  static List<OdooTemplate> templateCalls(String model, {List<String> sampleFields = const ['display_name']}) {
    final fields = sampleFields.isEmpty ? const ['display_name'] : sampleFields;
    OdooTemplate d(String name, String method,
            {List<int> ids = const [], String? idsVariable, Map<String, Object?> params = const {}, String? note}) =>
        OdooTemplate(name, OdooCall(model: model, method: method, ids: ids, idsVariable: idsVariable, params: params), note);
    // Ready-made requests that change data must not run against an id picked by us.
    const needsId = ' Set the variable {{${OdooVars.recordId}}} to the id of the record first: it is deliberately left undefined, '
        'so this request fails until you do, instead of touching a record you did not choose.';
    return [
      d('List $model', 'search_read', params: {'domain': <Object?>[], 'fields': fields, 'limit': 20, 'order': 'id desc'},
          note: 'Records matching the domain, newest first. Use the Domain builder to write the domain.'),
      d('Count $model', 'search_count', params: {'domain': <Object?>[]}),
      d('Search ids of $model', 'search', params: {'domain': <Object?>[], 'limit': 20}),
      d('Read $model by id', 'read', ids: [1], params: {'fields': fields}),
      d('Search by name', 'name_search', params: {'name': '', 'operator': 'ilike', 'limit': 8}),
      d('Create $model', 'create', params: {'vals_list': [{'name': 'New record'}]},
          note: 'Returns the ids of the created records. `vals_list` is a list so several records can be created at once.'),
      d('Update $model', 'write', idsVariable: OdooVars.recordId, params: {'vals': {'name': 'Updated'}},
          note: 'Returns true on success.$needsId'),
      d('Delete $model', 'unlink', idsVariable: OdooVars.recordId,
          note: 'Deletes the records in `ids`. This cannot be undone.$needsId'),
      d('Fields of $model', 'fields_get', params: {'attributes': ['string', 'type', 'required', 'relation', 'selection', 'readonly', 'store']},
          note: 'Describes every field. Paste the response into Odoo Studio to generate Dart models.'),
      d('Defaults of $model', 'default_get', params: {'fields_list': fields}),
    ];
  }
}

/// One ready-made request as a call: its name, the call and the note saved as its description.
final class OdooTemplate {
  final String name;
  final OdooCall call;
  final String? note;
  const OdooTemplate(this.name, this.call, this.note);
}
