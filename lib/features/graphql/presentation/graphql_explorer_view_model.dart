import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_http_response.dart';
import '../../../core/utils/variable_resolver.dart';
import '../../realtime/domain/services/realtime_url.dart';
import '../../settings/domain/repositories/settings_repository.dart';
import '../../settings/domain/services/tool_request_options.dart';
import '../domain/services/graphql_schema.dart';

/// Fetches and holds a GraphQL schema for the explorer, and what is selected in it.
final class GraphqlExplorerViewModel with ChangeNotifier {
  final ApiClient _api;
  final Future<VariableResolver> Function() _resolver;

  /// The app's timeout, proxy and certificate settings; without them the defaults are used.
  final SettingsRepository? _settings;

  GraphqlExplorerViewModel(this._api, this._resolver, {this._settings});

  String url = '';
  String headersText = '';

  GqlSchema? schema;
  bool isBusy = false;
  String? error;

  /// `query`, `mutation`, `subscription` or `types`: which list is open.
  String section = 'query';

  /// A type being read; `back` walks the types visited.
  String? selectedType;
  GqlField? selectedField;
  final List<String> _trail = [];

  bool get canGoBack => _trail.isNotEmpty;

  Future<void> fetch() async {
    if (isBusy) return;
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      final resolver = await _resolver();
      final resolvedUrl = resolver.resolve(url).trim();
      if (resolvedUrl.isEmpty) {
        error = 'Enter the GraphQL endpoint URL.';
        return;
      }
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...resolver.resolveMap(RealtimeUrl.parseHeaders(headersText)),
      };
      final response = await _api.send(ApiRequestSpec(
        method: 'POST',
        url: resolvedUrl,
        headers: headers,
        body: utf8.encode(jsonEncode({'query': graphqlIntrospectionQuery, 'operationName': 'IntrospectionQuery'})),
        options: ToolRequestOptions.resolve(_settings, maxResponseBytes: 32 * 1024 * 1024),
      ));
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      final parsed = GqlSchema.parse(text);
      if (parsed == null) {
        error = _explain(response.statusCode, text);
        return;
      }
      _use(parsed);
    } catch (e) {
      error = "Couldn't reach the endpoint: $e";
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  String _explain(int status, String body) {
    try {
      final j = jsonDecode(body);
      final errors = j is Map ? j['errors'] : null;
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        return 'The server refused the introspection query: ${first is Map ? first['message'] : first}. '
            'Many production servers disable introspection; paste a schema JSON instead.';
      }
    } on FormatException {
      // Not JSON: fall through to the generic message.
    }
    return 'The server answered $status but not with a GraphQL schema. Check the URL and the headers.';
  }

  /// Uses a pasted introspection result. Returns false when [text] is not one.
  bool loadFromText(String text) {
    final parsed = GqlSchema.parse(text);
    if (parsed == null) return false;
    error = null;
    _use(parsed);
    notifyListeners();
    return true;
  }

  void _use(GqlSchema value) {
    schema = value;
    selectedField = null;
    selectedType = null;
    _trail.clear();
    section = value.queryType != null ? 'query' : 'types';
  }

  void setSection(String value) {
    section = value;
    selectedField = null;
    selectedType = null;
    _trail.clear();
    notifyListeners();
  }

  void selectField(GqlField field) {
    selectedField = field;
    selectedType = null;
    _trail.clear();
    notifyListeners();
  }

  void openType(String name) {
    if (schema?.type(name) == null) return;
    if (selectedType != null) _trail.add(selectedType!);
    selectedType = name;
    selectedField = null;
    notifyListeners();
  }

  void back() {
    if (_trail.isEmpty) return;
    selectedType = _trail.removeLast();
    notifyListeners();
  }
}
