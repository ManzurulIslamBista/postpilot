import 'dart:convert';

/// The environment variables an Odoo workspace is built on, so one request set
/// works for every database: switch environment, change nothing else.
abstract final class OdooVars {
  static const url = 'odooUrl';
  static const database = 'odooDb';
  static const apiKey = 'odooApiKey';
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

  const OdooCall({
    required this.model,
    required this.method,
    this.ids = const [],
    this.params = const {},
    this.context = const {},
  });

  /// The body exactly as it is sent: `ids`, `context`, then the named arguments.
  Map<String, Object?> get body => {
        if (ids.isNotEmpty) 'ids': ids,
        if (context.isNotEmpty) 'context': context,
        ...params,
      };

  String get bodyText => const JsonEncoder.withIndent('  ').convert(body);

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
  static List<OdooRequestDraft> templatesFor(String model, {List<String> sampleFields = const ['display_name']}) {
    final fields = sampleFields.isEmpty ? const ['display_name'] : sampleFields;
    OdooRequestDraft d(String name, String method,
            {List<int> ids = const [], Map<String, Object?> params = const {}, String? note}) =>
        draft(OdooCall(model: model, method: method, ids: ids, params: params), name: name, note: note);
    return [
      d('List $model', 'search_read', params: {'domain': <Object?>[], 'fields': fields, 'limit': 20, 'order': 'id desc'},
          note: 'Records matching the domain, newest first. Use the Domain builder to write the domain.'),
      d('Count $model', 'search_count', params: {'domain': <Object?>[]}),
      d('Search ids of $model', 'search', params: {'domain': <Object?>[], 'limit': 20}),
      d('Read $model by id', 'read', ids: [1], params: {'fields': fields}),
      d('Search by name', 'name_search', params: {'name': '', 'operator': 'ilike', 'limit': 8}),
      d('Create $model', 'create', params: {'vals_list': [{'name': 'New record'}]},
          note: 'Returns the ids of the created records. `vals_list` is a list so several records can be created at once.'),
      d('Update $model', 'write', ids: [1], params: {'vals': {'name': 'Updated'}}, note: 'Returns true on success.'),
      d('Delete $model', 'unlink', ids: [1], note: 'Deletes the records in `ids`. This cannot be undone.'),
      d('Fields of $model', 'fields_get', params: {'attributes': ['string', 'type', 'required', 'relation', 'selection', 'readonly', 'store']},
          note: 'Describes every field. Paste the response into Odoo Studio to generate Dart models.'),
      d('Defaults of $model', 'default_get', params: {'fields_list': fields}),
    ];
  }
}
