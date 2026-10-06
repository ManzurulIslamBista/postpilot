import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/enums/body_type.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../../../request_builder/domain/usecases/prepare_request_usecase.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
import '../../domain/services/resolved_secrets.dart';
import '../../domain/services/response_history.dart';

/// One response, decoded once for all the tools.
final class ResponseToolsData {
  final int requestId;
  final String requestName;
  final ApiResponseEntity response;
  final String bodyText;

  /// The decoded body; only meaningful when [isJson].
  final Object? json;
  final bool isJson;

  const ResponseToolsData({
    required this.requestId,
    required this.requestName,
    required this.response,
    required this.bodyText,
    required this.json,
    required this.isJson,
  });

  factory ResponseToolsData.from({required int requestId, required String requestName, required ApiResponseEntity response}) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? json;
    var isJson = false;
    try {
      json = jsonDecode(text);
      isJson = true;
    } on FormatException {
      // Not JSON: the tools that need it say so.
    }
    return ResponseToolsData(
      requestId: requestId,
      requestName: requestName,
      response: response,
      bodyText: text,
      json: json,
      isJson: isJson,
    );
  }
}

/// A body to compare the current response with.
final class CompareSource {
  final String label;
  final String body;
  const CompareSource(this.label, this.body);
}

/// Backs the Response tools dialog: loads what the tools need beside the
/// response (the request, earlier responses, saved examples) and writes
/// extractors and assertions back to the request's Tests tab.
final class ResponseToolsViewModel with ChangeNotifier {
  final RequestRepository _requests;
  final RequestScriptsRepository _scripts;
  final ResponseExampleRepository _examples;
  final ResponseHistory _history;
  final ResponseToolsData data;

  /// Builds the request the way the sender does. Without it the tools fall back to the saved request.
  final PrepareRequestUseCase? _prepareRequest;

  /// Which variables the user marked secret: the active environment's and the globals.
  final EnvironmentRepository? _environments;
  final GlobalVariableRepository? _globals;

  ResponseToolsViewModel(
    this._requests,
    this._scripts,
    this._examples,
    this._history,
    this.data, {
    this._prepareRequest,
    this._environments,
    this._globals,
  });

  ApiRequestEntity? request;
  List<ResponseExampleEntity> examples = const [];
  bool loaded = false;

  /// The request as it was sent: variables resolved, auth applied, query parameters in the URL. Null
  /// when it could not be built (see [prepareError]) or no builder was given.
  PreparedRequest? prepared;
  String? prepareError;

  /// Values of the secret variables behind [prepared], to hide wherever they show up in text built from it.
  List<String> secretValues = const [];

  Future<void> load() async {
    request = await _requests.findById(data.requestId);
    examples = await _examples.watchByRequest(data.requestId).first;
    await _prepare();
    loaded = true;
    notifyListeners();
  }

  Future<void> _prepare() async {
    final saved = request;
    final prepare = _prepareRequest;
    if (saved == null || prepare == null) return;
    try {
      final built = await prepare(saved);
      prepared = built;
      secretValues = ResolvedSecrets.valuesOf(built.resolver, flaggedKeys: await _flaggedSecretKeys());
    } catch (e) {
      prepared = null;
      prepareError = e.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
    }
  }

  Future<Set<String>> _flaggedSecretKeys() async {
    final keys = <String>{};
    try {
      final environments = _environments;
      if (environments != null) {
        final active = await environments.watchActive().first;
        if (active != null) {
          for (final v in await environments.watchVariables(active.id).first) {
            if (v.isSecret && v.enabled) keys.add(v.key);
          }
        }
      }
      for (final g in await _globals?.watchAll().first ?? const []) {
        if (g.isSecret && g.enabled) keys.add(g.key);
      }
    } catch (_) {
      // The names that look secret are still hidden.
    }
    return keys;
  }

  // What the tools show of the request. The saved request holds `{{baseUrl}}` and no query parameters or
  // auth header, so everything below prefers the request as it was built to be sent.

  String get requestMethod => prepared?.spec.method ?? request?.method.label ?? 'GET';

  String get requestUrl => prepared?.spec.url ?? request?.url ?? data.requestName;

  Map<String, String> get requestHeaders =>
      prepared?.spec.headers ??
      {for (final h in request?.headers ?? const <KeyValueItem>[]) if (h.enabled && h.key.isNotEmpty) h.key: h.value};

  /// The body as text; a GraphQL request shows the JSON that is posted.
  String? get requestBodyText {
    final built = prepared;
    if (built != null) {
      final bytes = built.spec.bodyBytes;
      return bytes == null || bytes.isEmpty ? null : utf8.decode(bytes, allowMalformed: true);
    }
    final saved = request;
    if (saved == null) return null;
    return saved.body.type == BodyType.graphql ? saved.body.graphqlQuery : saved.body.rawText;
  }

  /// Earlier responses of this request, newest first, without the current one.
  List<CompareSource> get compareSources {
    final out = <CompareSource>[];
    var n = 0;
    for (final r in _history.of(data.requestId)) {
      if (identical(r, data.response)) continue;
      n++;
      final at = _history.receivedAt(r);
      out.add(CompareSource(
        '${n == 1 ? 'Previous response' : 'Earlier response ($n)'} · ${r.statusCode}'
        '${at == null ? '' : ' · ${_ago(at)}'}',
        utf8.decode(r.bodyBytes, allowMalformed: true),
      ));
    }
    for (final e in examples) {
      out.add(CompareSource('Example "${e.name}" · ${e.statusCode}', e.body));
    }
    return out;
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  /// Adds "copy [path] into variable [key]" to the request's extractors.
  Future<void> addExtractor({required String path, required String key, required ExtractorScope scope}) async {
    final current = await _scripts.get(data.requestId) ?? RequestScriptsEntity(requestId: data.requestId);
    final extractors = ScriptsJsonCodec.decodeExtractors(current.extractorsJson)
      ..removeWhere((e) => e.path == path && e.variableKey == key && e.scope == scope)
      ..add(ExtractorEntity(path: path, scope: scope, variableKey: key));
    await _scripts.save(current.copyWith(extractorsJson: ScriptsJsonCodec.encodeExtractors(extractors)));
  }

  /// Adds a check to the request's Tests tab.
  Future<void> addAssertion(AssertionEntity assertion) async {
    final current = await _scripts.get(data.requestId) ?? RequestScriptsEntity(requestId: data.requestId);
    final assertions = ScriptsJsonCodec.decodeAssertions(current.assertionsJson)..add(assertion);
    await _scripts.save(current.copyWith(assertionsJson: ScriptsJsonCodec.encodeAssertions(assertions)));
  }
}
