import 'package:flutter/foundation.dart';
import '../../data/odoo_client.dart';
import '../../data/odoo_schema_service.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/services/odoo_error_parser.dart';
import '../../domain/services/odoo_json2.dart';
import '../../domain/usecases/create_odoo_workspace_usecase.dart';
import '../../../environments/domain/repositories/environment_repository.dart';

/// State behind Odoo Studio: the connection, the model being explored, its
/// fields and the rows of a test search. Everything that talks to Odoo goes
/// through [OdooClient] and reports failures as [error] (with Odoo's own
/// explanation in [errorInfo]) instead of throwing into the UI. The connection
/// is either Odoo 19's JSON-2 API (an API key) or the JSON-RPC session of Odoo 18
/// and older (a login and a password or API key): every tool works through both.
final class OdooStudioViewModel with ChangeNotifier {
  final OdooClient _client;
  final EnvironmentRepository _environments;
  final CreateOdooWorkspaceUseCase _workspace;

  OdooStudioViewModel(this._client, this._environments, this._workspace);

  String url = '';
  String database = '';

  /// The API key with JSON-2; the password (or an API key used as one) with JSON-RPC.
  String apiKey = '';
  OdooProtocol protocol = OdooProtocol.json2;

  /// The login of a JSON-RPC connection.
  String login = '';

  bool isBusy = false;
  String? busyLabel;
  String? error;
  OdooErrorInfo? errorInfo;
  String? connectionOk;

  /// The databases the server lists (`/web/database/list`), and why there is no list when it is switched off.
  List<String> databases = const [];
  String? databaseNote;

  List<String> modelNames = const [];
  Map<String, String> modelLabels = const {};

  String model = '';
  OdooModelInfo? info;
  final Set<String> chosenFields = {};

  /// The domain being built; shared by the Domain tab and the Explorer's search.
  String domainText = '';

  List<Map<String, Object?>> rows = const [];
  Duration? lastDuration;

  OdooConnection get connection =>
      OdooConnection(baseUrl: url, database: database, apiKey: apiKey, protocol: protocol, login: login);

  /// The client, for the tabs that talk to the server themselves (the payload builder, the checker).
  OdooClient get client => _client;

  /// What was read from the server so far (fields, models), shared by every tool and kept for the session.
  OdooSchemaService get schema => _client.schema;

  /// Picks up the URL, database and key of the active environment when it has
  /// them, so the connection does not have to be typed again.
  Future<void> loadFromActiveEnvironment() async {
    final vars = await _environments.getActiveVariables();
    url = vars[OdooVars.url] ?? url;
    database = vars[OdooVars.database] ?? database;
    if (vars.containsKey(OdooVars.protocol)) protocol = OdooProtocol.fromId(vars[OdooVars.protocol]);
    login = vars[OdooVars.login] ?? login;
    apiKey = (protocol == OdooProtocol.jsonRpc ? vars[OdooVars.password] : null) ?? vars[OdooVars.apiKey] ?? apiKey;
    notifyListeners();
  }

  void setConnection({String? url, String? database, String? apiKey, String? login, OdooProtocol? protocol}) {
    this.url = url ?? this.url;
    this.database = database ?? this.database;
    this.apiKey = apiKey ?? this.apiKey;
    this.login = login ?? this.login;
    final changed = protocol != null && protocol != this.protocol;
    this.protocol = protocol ?? this.protocol;
    connectionOk = null;
    if (changed) notifyListeners();
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
    final missing = connection.missing;
    if (missing != null) {
      error = missing;
      return null;
    }
    final result = await _client.call(connection, call);
    if (!result.ok) {
      errorInfo = result.error;
      error = result.failureText(jsonRpc: protocol == OdooProtocol.jsonRpc);
      return null;
    }
    lastDuration = result.duration;
    return result;
  }

  Future<void> testConnection() => _run('Testing connection', () async {
        final missing = connection.missing;
        if (missing != null) {
          error = missing;
          return;
        }
        final r = await _client.connect(connection);
        if (!r.ok) {
          errorInfo = r.error;
          error = r.failureText(jsonRpc: protocol == OdooProtocol.jsonRpc);
          return;
        }
        lastDuration = r.duration;
        final ctx = r.json is Map ? r.json as Map : const {};
        final user = ctx['username'] ?? ctx['name'];
        final context = ctx['user_context'] is Map ? ctx['user_context'] as Map : ctx;
        final version = ctx['server_version'];
        connectionOk = 'Connected'
            '${user != null ? ' as $user' : ''}'
            '${version != null ? ' · Odoo $version' : ''}'
            '${context['lang'] != null ? ' · language ${context['lang']}' : ''}'
            '${context['tz'] != null ? ' · ${context['tz']}' : ''} · ${r.duration.inMilliseconds} ms';
      });

  /// Asks the server which databases it has, so one can be picked instead of typed. Many servers switch the list off;
  /// [databaseNote] then says so.
  Future<void> findDatabases() => _run('Finding databases', () async {
        if (url.trim().isEmpty) {
          error = 'Enter the server URL first.';
          return;
        }
        final found = await _client.databases(connection);
        databases = found.names;
        databaseNote = found.problem;
        if (found.names.length == 1 && database.trim().isEmpty) database = found.names.single;
      });

  Future<void> loadModels() => _run('Loading models', () async {
        final missing = connection.missing;
        if (missing != null) {
          error = missing;
          return;
        }
        final found = await schema.models(connection, refresh: true);
        if (!found.ok) {
          error = found.error;
          errorInfo = found.info;
          return;
        }
        final models = found.value!;
        modelNames = [for (final m in models) m.model];
        modelLabels = {for (final m in models) m.model: m.label};
      });

  Future<void> loadFields(String modelName, {bool refresh = false}) => _run('Reading fields of $modelName', () async {
        model = modelName.trim();
        final missing = connection.missing;
        if (missing != null) {
          error = missing;
          return;
        }
        final found = await schema.fields(connection, model, refresh: refresh);
        if (!found.ok) {
          error = found.error;
          errorInfo = found.info;
          return;
        }
        final parsed = found.value!;
        info = parsed;
        chosenFields
          ..clear()
          ..addAll(parsed.fields.where((f) => f.stored && (f.name == 'id' || f.name == 'name' || f.name == 'display_name' || f.required)).map((f) => f.name).take(8));
        rows = const [];
      });

  /// Reads the fields of the model being explored again, bypassing what was remembered.
  Future<void> refreshFields() => loadFields(model, refresh: true);

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
        protocol: protocol,
        login: login.trim(),
      ));

  Future<OdooWorkspaceResult?> createCollection(String name, List<String> models) => _run(
        'Creating requests',
        () => _workspace.createCollection(
          name: name,
          models: models,
          fieldsByModel: {if (info != null) info!.model: chosenFields.toList()},
          protocol: protocol,
        ),
      );

  Future<int?> addRequest(int collectionId, OdooRequestDraft draft) =>
      _run('Saving request', () => _workspace.addRequest(collectionId: collectionId, draft: draft));
}
