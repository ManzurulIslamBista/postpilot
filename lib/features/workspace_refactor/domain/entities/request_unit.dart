import '../../../../core/enums/body_type.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
import 'field_builders.dart';
import 'refactor_scope.dart';
import 'unit_field.dart';

/// A request with everything that is saved beside it: its tests, its description, its tags and its saved examples.
/// The five are written by five repository calls, each only when a text in it changed.
final class RequestUnit extends RefactorUnit {
  final ApiRequestEntity request;
  final List<AssertionEntity> assertions;
  final List<ExtractorEntity> extractors;

  /// Whether the request has a row of tests saved, so a restore knows it may write one back.
  final bool hasScripts;
  final String description;
  final List<String> tags;
  final List<ResponseExampleEntity> examples;

  /// The collection and the folders above the request, outermost first.
  final List<String> parentTrail;

  const RequestUnit({
    required this.request,
    required this.parentTrail,
    this.assertions = const [],
    this.extractors = const [],
    this.hasScripts = false,
    this.description = '',
    this.tags = const [],
    this.examples = const [],
  });

  @override
  UnitKind get kind => UnitKind.request;

  @override
  int get id => request.id;

  @override
  List<String> get trail => [...parentTrail, request.name];

  RequestUnit copyWith({
    ApiRequestEntity? request,
    List<AssertionEntity>? assertions,
    List<ExtractorEntity>? extractors,
    String? description,
    List<String>? tags,
    List<ResponseExampleEntity>? examples,
  }) => RequestUnit(
    request: request ?? this.request,
    parentTrail: parentTrail,
    assertions: assertions ?? this.assertions,
    extractors: extractors ?? this.extractors,
    hasScripts: hasScripts,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    examples: examples ?? this.examples,
  );

  /// This request with the example at [index] standing for a copy that was saved again (it has a new id).
  RequestUnit withExampleId(int index, int id) {
    final old = examples[index];
    return copyWith(examples: replacedAt(examples, index, _example(old, id: id)));
  }

  @override
  Iterable<UnitField> fields() sync* {
    final r = request;
    UnitField text(String path, String group, RefactorScope scope, String label, String value, RequestUnit Function(String) change, {bool active = true}) =>
        UnitField(path: path, group: group, scope: scope, label: label, value: value, write: change, active: active);
    RequestUnit withRequest(ApiRequestEntity changed) => copyWith(request: changed);

    if (r.name.isNotEmpty) yield text('name', 'request', RefactorScope.names, 'Request name', r.name, (v) => withRequest(r.copyWith(name: v)));
    if (r.url.isNotEmpty) yield text('url', 'request', RefactorScope.urls, 'URL', r.url, (v) => withRequest(r.copyWith(url: v)));
    yield* keyValueFields(
      rows: r.queryParams,
      pathPrefix: 'query',
      group: 'request',
      scope: RefactorScope.queryParams,
      what: 'Query param',
      rebuild: (rows) => withRequest(r.copyWith(queryParams: rows)),
    );
    yield* keyValueFields(
      rows: r.headers,
      pathPrefix: 'header',
      group: 'request',
      scope: RefactorScope.headers,
      what: 'Header',
      rebuild: (rows) => withRequest(r.copyWith(headers: rows)),
    );

    final b = r.body;
    final raw = b.type == BodyType.raw;
    if (b.rawText.isNotEmpty) {
      yield text('body.raw', 'request', RefactorScope.bodies, raw ? 'Raw body' : 'Raw body (unused)', b.rawText, (v) => withRequest(r.copyWith(body: b.copyWith(rawText: v))), active: raw);
    }
    yield* keyValueFields(
      rows: b.formFields,
      pathPrefix: 'body.form',
      group: 'request',
      scope: RefactorScope.bodies,
      what: 'Form field',
      unused: b.type != BodyType.formData && b.type != BodyType.binary,
      rebuild: (rows) => withRequest(r.copyWith(body: b.copyWith(formFields: rows))),
    );
    yield* keyValueFields(
      rows: b.urlEncodedFields,
      pathPrefix: 'body.urlencoded',
      group: 'request',
      scope: RefactorScope.bodies,
      what: 'URL-encoded field',
      unused: b.type != BodyType.urlEncoded,
      rebuild: (rows) => withRequest(r.copyWith(body: b.copyWith(urlEncodedFields: rows))),
    );
    final graphql = b.type == BodyType.graphql;
    if (b.graphqlQuery.isNotEmpty) {
      yield text('body.graphqlQuery', 'request', RefactorScope.bodies, graphql ? 'GraphQL query' : 'GraphQL query (unused)', b.graphqlQuery, (v) => withRequest(r.copyWith(body: b.copyWith(graphqlQuery: v))), active: graphql);
    }
    // A new body holds "{}" here: that is not something anyone searches for.
    if (b.graphqlVariables.isNotEmpty && (graphql || b.graphqlVariables != '{}')) {
      yield text('body.graphqlVariables', 'request', RefactorScope.bodies, graphql ? 'GraphQL variables' : 'GraphQL variables (unused)', b.graphqlVariables, (v) => withRequest(r.copyWith(body: b.copyWith(graphqlVariables: v))), active: graphql);
    }

    yield* authFields(
      auth: r.auth,
      pathPrefix: 'auth',
      group: 'request',
      scope: RefactorScope.auth,
      what: 'Auth',
      rebuild: (auth) => withRequest(r.copyWith(auth: auth)),
    );

    yield* testFields(
      assertions: assertions,
      extractors: extractors,
      pathPrefix: 'scripts',
      group: 'scripts',
      scope: RefactorScope.scripts,
      ownerKey: key,
      ownerLabel: 'request "${shorten(r.name)}"',
      rebuild: (a, x) => copyWith(assertions: a, extractors: x),
    );

    if (description.isNotEmpty) yield text('doc', 'doc', RefactorScope.docs, 'Notes', description, (v) => copyWith(description: v));
    for (var i = 0; i < tags.length; i++) {
      if (tags[i].isNotEmpty) yield text('tag.$i', 'tags', RefactorScope.tags, 'Tag', tags[i], (v) => copyWith(tags: replacedAt(tags, i, v)));
    }

    for (var i = 0; i < examples.length; i++) {
      final e = examples[i];
      final group = 'example.$i';
      final label = 'Example "${shorten(e.name)}"';
      if (e.name.isNotEmpty) yield text('example.$i.name', group, RefactorScope.examples, 'Example name', e.name, (v) => copyWith(examples: replacedAt(examples, i, _example(e, name: v))));
      if (e.body.isNotEmpty) yield text('example.$i.body', group, RefactorScope.examples, '$label body', e.body, (v) => copyWith(examples: replacedAt(examples, i, _example(e, body: v))));
      var j = 0;
      for (final header in e.headers.entries) {
        final position = j++;
        // The marker the examples table has no column for is not text anyone edits.
        if (header.key.toLowerCase() == ResponseExampleEntity.truncatedHeader || header.value.isEmpty) continue;
        yield text(
          'example.$i.header.$position',
          group,
          RefactorScope.examples,
          '$label header "${shorten(header.key)}"',
          header.value,
          (v) => copyWith(examples: replacedAt(examples, i, _example(e, headers: _withHeaderValue(e.headers, position, v)))),
        );
      }
    }
  }

  static Map<String, String> _withHeaderValue(Map<String, String> headers, int position, String value) {
    var i = 0;
    return {for (final entry in headers.entries) entry.key: i++ == position ? value : entry.value};
  }

  static ResponseExampleEntity _example(ResponseExampleEntity e, {int? id, String? name, String? body, Map<String, String>? headers}) =>
      ResponseExampleEntity(
        id: id ?? e.id,
        requestId: e.requestId,
        name: name ?? e.name,
        statusCode: e.statusCode,
        headers: headers ?? e.headers,
        body: body ?? e.body,
        savedAt: e.savedAt,
      );
}
