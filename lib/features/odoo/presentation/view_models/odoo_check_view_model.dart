import 'package:flutter/foundation.dart';
import '../../domain/entities/odoo_connection.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/entities/odoo_request_shape.dart';
import '../../domain/services/odoo_request_checker.dart';
import 'odoo_studio_view_model.dart';

/// State behind the request checker: reads the model's fields from the live server (remembered per server and
/// database, with a refresh), checks a request body against them, and applies the fixes the checker offers.
///
/// The request is either typed here (a model, a method, a body) or comes from a request tab, where its own URL is
/// given and kept.
final class OdooCheckViewModel with ChangeNotifier {
  final OdooStudioViewModel _studio;

  /// The request's own URL (from a request tab); null when the model and method are typed.
  final String? url;

  OdooCheckViewModel(this._studio, {this.url, String body = ''}) : bodyText = body {
    final target = url == null ? null : OdooRequestShape.ofUrl(url!);
    if (target != null) {
      model = target.model;
      method = target.method;
      protocol = target.protocol;
    } else {
      protocol = _studio.protocol;
    }
  }

  String model = '';
  String method = 'create';
  late OdooProtocol protocol;
  String bodyText;

  /// What the last check found; null until one ran.
  List<OdooProblem>? problems;
  OdooRequestShape? _shape;

  OdooModelInfo? info;
  bool isBusy = false;
  String? error;

  /// True once a fix changed [bodyText]: the request tab offers to take the new body over.
  bool bodyChanged = false;

  OdooConnection get connection => _studio.connection;

  void setTarget({String? model, String? method, OdooProtocol? protocol}) {
    this.model = model ?? this.model;
    this.method = method ?? this.method;
    this.protocol = protocol ?? this.protocol;
    problems = null;
    notifyListeners();
  }

  void setBody(String text) {
    bodyText = text;
    problems = null;
    notifyListeners();
  }

  /// The URL the body is read against: the request's own, or one made from the typed model and method.
  String get _effectiveUrl =>
      url ?? '${protocol == OdooProtocol.json2 ? '/json/2/' : '/web/dataset/call_kw/'}${model.trim()}/${method.trim()}';

  /// Forgets what was read from the server about [model] and reads it again, then checks.
  Future<void> refresh() => run(refresh: true);

  Future<void> run({bool refresh = false}) async {
    if (isBusy) return;
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      await _check(refresh);
    } catch (e) {
      error = '$e';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _check(bool refresh) async {
    final read = OdooRequestShape.read(_effectiveUrl, bodyText);
    final shape = read.shape;
    _shape = shape;
    if (shape == null) {
      problems = [OdooProblem('body', OdooProblemSeverity.error, read.error ?? 'The request could not be read.', 'body')];
      return;
    }
    model = shape.model.isEmpty ? model : shape.model;
    final missing = connection.missing;
    if (missing != null) {
      // Without a server only the structure can be judged.
      info = null;
      problems = OdooRequestChecker.check(shape, const OdooCheckContext());
      error = missing;
      return;
    }
    final schema = _studio.schema;
    final c = connection;
    if (refresh) schema.clear(connection: c);

    OdooModelInfo? modelInfo;
    bool? exists;
    var known = const <String>[];
    if (shape.model.isNotEmpty) {
      exists = await schema.modelExists(c, shape.model);
      if (exists != false) {
        final fields = await schema.fields(c, shape.model, refresh: refresh);
        modelInfo = fields.value;
        final text = (fields.error ?? '').toLowerCase();
        if (modelInfo == null && (text.contains("doesn't exist") || text.contains('does not exist') || text.contains('keyerror') || text.contains('not found'))) {
          exists = false;
        }
      }
      if (exists == false) known = (await schema.models(c)).value?.map((m) => m.model).toList() ?? const [];
    }
    info = modelInfo;

    Set<String>? defaults;
    if (modelInfo != null && shape.method == 'create') {
      final required = [for (final f in modelInfo.fields) if (f.required && f.stored && !f.isMagic) f.name];
      if (required.isNotEmpty) {
        final found = await schema.defaultGet(c, shape.model, required);
        defaults = found.ok ? found.value!.keys.toSet() : null;
      } else {
        defaults = const {};
      }
    }

    // The models the body points into (x2many commands, `partner_id.country_id`) are read on demand, a few at most.
    final wanted = <String>{};
    List<OdooProblem> runCheck() => OdooRequestChecker.check(
          shape,
          OdooCheckContext(
            info: modelInfo,
            modelExists: exists,
            knownModels: known,
            defaults: defaults,
            related: (m) {
              wanted.add(m);
              return schema.cachedFields(c, m);
            },
          ),
        );
    var found = runCheck();
    final toRead = [for (final m in wanted) if (schema.cachedFields(c, m) == null && m != shape.model) m].take(6).toList();
    if (toRead.isNotEmpty) {
      for (final m in toRead) {
        await schema.fields(c, m);
      }
      wanted.clear();
      found = runCheck();
    }
    problems = found;
  }

  /// Applies the fix of [problem]: a change to the body, or another model; then checks again.
  Future<void> applyFix(OdooProblem problem) async {
    final fix = problem.fix;
    final shape = _shape;
    if (fix == null) return;
    if (fix.model != null) {
      model = fix.model!;
      problems = null;
      notifyListeners();
      if (url == null) await run();
      return;
    }
    if (shape == null) return;
    bodyText = OdooRequestChecker.applyFixes(shape, [fix]);
    bodyChanged = true;
    notifyListeners();
    await run();
  }

  /// Applies every fix that changes the body at once, then checks again.
  Future<void> applyAll() async {
    final shape = _shape;
    final fixes = [for (final p in problems ?? const <OdooProblem>[]) if (p.fix != null && p.fix!.changesBody) p.fix!];
    if (shape == null || fixes.isEmpty) return;
    bodyText = OdooRequestChecker.applyFixes(shape, fixes);
    bodyChanged = true;
    notifyListeners();
    await run();
  }
}
