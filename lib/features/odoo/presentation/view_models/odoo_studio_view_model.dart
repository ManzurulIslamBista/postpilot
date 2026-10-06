import 'package:flutter/foundation.dart';
import '../../data/odoo_client.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/services/odoo_error_parser.dart';
import '../../domain/services/odoo_json2.dart';
import '../../domain/usecases/create_odoo_workspace_usecase.dart';
import '../../../environments/domain/repositories/environment_repository.dart';

/// State behind Odoo Studio: the connection, the model being explored, its
/// fields and the rows of a test search. Everything that talks to Odoo goes
/// through [OdooClient] and reports failures as [error] (with Odoo's own
/// explanation in [errorInfo]) instead of throwing into the UI.
final class OdooStudioViewModel with ChangeNotifier {
  final OdooClient _client;
  final EnvironmentRepository _environments;
  final CreateOdooWorkspaceUseCase _workspace;

  OdooStudioViewModel(this._client, this._environments, this._workspace);

  String url = '';
  String database = '';
  String apiKey = '';

  bool isBusy = false;
  String? busyLabel;
  String? error;
  OdooErrorInfo? errorInfo;
  String? connectionOk;

  List<String> modelNames = const [];
  Map<String, String> modelLabels = const {};

  String model = '';
  OdooModelInfo? info;
  final Set<String> chosenFields = {};

  /// The domain being built; shared by the Domain tab and the Explorer's search.
  String domainText = '';

  List<Map<String, Object?>> rows = const [];
  Duration? lastDuration;

  OdooConnection get connection => OdooConnection(baseUrl: url, database: database, apiKey: apiKey);

  /// Picks up the URL, database and key of the active environment when it has
  /// them, so the connection does not have to be typed again.
  Future<void> loadFromActiveEnvironment() async {
    final vars = await _environments.getActiveVariables();
    url = vars[OdooVars.url] ?? url;
    database = vars[OdooVars.database] ?? database;
    apiKey = vars[OdooVars.apiKey] ?? apiKey;
    notifyListeners();
  }

  void setConnection({String? url, String? database, String? apiKey}) {
    this.url = url ?? this.url;
    this.database = database ?? this.database;
    this.apiKey = apiKey ?? this.apiKey;
    connectionOk = null;
  }

  Future<T?> _run<T>(String label, Future<T> Function() body) async {
    if (isBusy) return null;
    isBusy = true;
    busyLabel = label;
    error = null;
    errorInfo = null;
    notifyListeners();
    try {
      return await body();
    } catch (e) {
      error = _describe(e);
      return null;
    } finally {
      isBusy = false;
      busyLabel = null;
      notifyListeners();
    }
  }

  String _describe(Object e) {
    final text = e.toString();
    if (text.contains('SocketException') || text.contains('connection') || text.contains('Failed host lookup')) {
      return "Can't reach the server. Check the URL and your network. (On the web build, Odoo must allow cross-origin requests; use the desktop app otherwise.)";
    }
    return text;
  }

  /// A call that succeeded, or null after recording why it did not.
  Future<OdooResult?> _call(OdooCall call) async {
    if (!connection.isComplete) {
      error = 'Enter the server URL and an API key first.';
      return null;
    }
    final result = await _client.call(connection, call);
    if (!result.ok) {
      errorInfo = result.error;
      error = result.error?.message.isNotEmpty == true
          ? result.error!.message
          : 'The server answered ${result.status}. ${result.json == null ? 'The body is not JSON: is this an Odoo 19+ server with the JSON-2 API?' : ''}';
      return null;
    }
    lastDuration = result.duration;
    return result;
  }

  Future<void> testConnection() => _run('Testing connection', () async {
        final r = await _call(const OdooCall(model: 'res.users', method: 'context_get'));
        if (r == null) return;
        final ctx = r.json is Map ? r.json as Map : const {};
        connectionOk = 'Connected${ctx['lang'] != null ? ' · language ${ctx['lang']}' : ''}'
            '${ctx['tz'] != null ? ' · ${ctx['tz']}' : ''} · ${r.duration.inMilliseconds} ms';
      });

  Future<void> loadModels() => _run('Loading models', () async {
        final r = await _call(const OdooCall(
          model: 'ir.model',
          method: 'search_read',
          params: {'domain': <Object?>[], 'fields': ['model', 'name'], 'order': 'model'},
        ));
        if (r == null || r.json is! List) return;
        final names = <String>[];
        final labels = <String, String>{};
        for (final m in r.json as List) {
          if (m is Map && m['model'] is String) {
            names.add(m['model'] as String);
            labels[m['model'] as String] = '${m['name'] ?? ''}';
          }
        }
        modelNames = names;
        modelLabels = labels;
      });

  Future<void> loadFields(String modelName) => _run('Reading fields of $modelName', () async {
        model = modelName.trim();
        final r = await _call(OdooCall(
          model: model,
          method: 'fields_get',
          params: const {
            'attributes': ['string', 'type', 'required', 'relation', 'selection', 'readonly', 'store', 'help'],
          },
        ));
        if (r == null) return;
        final parsed = OdooModelInfo.parse(model, r.body);
        if (parsed == null) {
          error = 'The server did not return a field list for $model.';
          return;
        }
        info = parsed;
        chosenFields
          ..clear()
          ..addAll(parsed.fields.where((f) => f.stored && (f.name == 'id' || f.name == 'name' || f.name == 'display_name' || f.required)).map((f) => f.name).take(8));
        rows = const [];
      });

  /// Pastes a `fields_get` response instead of asking the server (offline use).
  bool useFieldsJson(String modelName, String json) {
    final parsed = OdooModelInfo.parse(modelName.trim(), json);
    if (parsed == null) return false;
    model = modelName.trim();
    info = parsed;
    chosenFields
      ..clear()
      ..addAll(parsed.fields.where((f) => f.stored).map((f) => f.name));
    notifyListeners();
    return true;
  }

  void setDomainText(String text) {
    domainText = text;
    notifyListeners();
  }

  void toggleField(String name, bool on) {
    on ? chosenFields.add(name) : chosenFields.remove(name);
    notifyListeners();
  }

  void setAllFields(bool on) {
    chosenFields.clear();
    if (on) chosenFields.addAll(info?.fields.where((f) => f.stored).map((f) => f.name) ?? const []);
    notifyListeners();
  }

  Future<void> runSearch({List<Object?> domain = const [], int limit = 20}) => _run('Running search_read', () async {
        if (model.isEmpty) {
          error = 'Choose a model first.';
          return;
        }
        final fields = chosenFields.isEmpty ? const ['display_name'] : chosenFields.toList();
        final r = await _call(OdooCall(model: model, method: 'search_read', params: {'domain': domain, 'fields': fields, 'limit': limit}));
        if (r == null) return;
        rows = r.json is List ? [for (final e in r.json as List) if (e is Map) Map<String, Object?>.from(e)] : const [];
      });

  /// Saves the connection as an environment. The URL is stored the way Studio
  /// itself tests it (with `https://` when no scheme was typed, no trailing `/`),
  /// because the saved requests are sent by the normal sender, which would treat
  /// a bare host as `http://` and put the API key on the wire unencrypted.
  Future<int?> saveEnvironment(String name) => _run('Saving environment', () => _workspace.createEnvironment(
        name: name,
        url: connection.normalizedUrl,
        database: database.trim(),
        apiKey: apiKey.trim(),
      ));

  Future<OdooWorkspaceResult?> createCollection(String name, List<String> models) => _run(
        'Creating requests',
        () => _workspace.createCollection(
          name: name,
          models: models,
          fieldsByModel: {if (info != null) info!.model: chosenFields.toList()},
        ),
      );

  Future<int?> addRequest(int collectionId, OdooRequestDraft draft) =>
      _run('Saving request', () => _workspace.addRequest(collectionId: collectionId, draft: draft));
}
