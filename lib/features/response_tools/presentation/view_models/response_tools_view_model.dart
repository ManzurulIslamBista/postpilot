import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
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

  ResponseToolsViewModel(this._requests, this._scripts, this._examples, this._history, this.data);

  ApiRequestEntity? request;
  List<ResponseExampleEntity> examples = const [];
  bool loaded = false;

  Future<void> load() async {
    request = await _requests.findById(data.requestId);
    examples = await _examples.watchByRequest(data.requestId).first;
    loaded = true;
    notifyListeners();
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
