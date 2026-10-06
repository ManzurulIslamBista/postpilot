import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../data/safety_prefs.dart';
import 'production_detector.dart';

/// Why a send needs confirming.
final class ProductionWarning {
  /// The production environment, or the production host when that is what gave
  /// the target away; also the key "don't ask again" is remembered under.
  final String environmentName;
  final String description;

  /// The request deletes data. "Don't ask again" never covers it, so the dialog
  /// does not offer the choice and the guard ignores an earlier one.
  final bool destructive;

  /// Why the target counts as production, when the environment's name is not the reason.
  final String? reason;

  const ProductionWarning(this.environmentName, this.description, {this.destructive = false, this.reason});
}

/// Checks a request about to leave the app: when the active environment looks
/// like production (or the request goes to a production host from Settings >
/// Safety) and the request changes data, the person is asked first.
///
/// "Changes data" is judged by what the request does, not by its verb: an Odoo
/// `search_read` or a GraphQL `query` over POST is a read and never asks, while
/// an Odoo `unlink` or a GraphQL `deleteUser` mutation is a deletion and always
/// asks, even after "don't ask again".
final class ProductionGuard {
  final EnvironmentRepository _environments;
  final SafetyPrefs _prefs;

  /// Resolves the `{{variables}}` of a request's URL the way a send does, so a
  /// host built from `{{baseUrl}}` can be matched against the production hosts.
  /// Without it the URL is matched as written.
  final Future<String> Function(ApiRequestEntity request)? _resolveUrl;

  const ProductionGuard(this._environments, this._prefs, [this._resolveUrl]);

  /// The name of the active environment when it looks like production.
  Future<String?> _productionEnvironment() async {
    final active = await _environments.watchActive().first;
    if (active == null) return null;
    return ProductionDetector.isProduction(active.name, extraWords: _prefs.extraWords) ? active.name : null;
  }

  /// What makes a send to [url] a production send: the production environment
  /// ([environment]), else a production host. `null` when neither.
  ({String target, String? reason})? _hit(String? environment, String url) {
    if (environment != null) return (target: environment, reason: null);
    if (!ProductionDetector.isProductionHost(url, _prefs.productionHosts)) return null;
    final host = ProductionDetector.hostOf(url)!;
    return (
      target: host,
      reason: '$host is one of your production hosts (Settings > Safety), so this will change real data although the active environment is not production.',
    );
  }

  Future<String> _urlOf(ApiRequestEntity request) async {
    final resolve = _resolveUrl;
    if (resolve == null) return request.url;
    try {
      return await resolve(request);
    } catch (_) {
      return request.url; // an unreadable variable store must not stop the check
    }
  }

  static String? _rawBody(ApiRequestEntity r) => r.body.type == BodyType.raw ? r.body.rawText : null;
  static String? _graphql(ApiRequestEntity r) => r.body.type == BodyType.graphql ? r.body.graphqlQuery : null;

  /// `null` when the send may go ahead without asking. [url], [body] (raw text)
  /// and [graphqlQuery] let the guard tell a read over POST from a write; without
  /// them the HTTP method alone decides, as it always did.
  Future<ProductionWarning?> checkSend(
    HttpMethod method,
    String requestName, {
    String url = '',
    String? body,
    String? graphqlQuery,
  }) async {
    if (!_prefs.confirmProductionWrites) return null;
    final effect = ProductionDetector.classify(method, url: url, body: body, graphqlQuery: graphqlQuery);
    if (!effect.changesData) return null;
    final hit = _hit(await _productionEnvironment(), url);
    if (hit == null) return null;
    final destructive = effect == RequestEffect.destructive;
    if (!destructive && _prefs.isSilenced(hit.target)) return null;
    return ProductionWarning(
      hit.target,
      '${method.label} "$requestName" ${destructive ? 'deletes data' : 'changes data'}',
      destructive: destructive,
      reason: hit.reason,
    );
  }

  /// [checkSend] for a saved request: judged by its intent and by where it goes,
  /// with `{{variables}}` in the URL resolved when the guard was given a resolver.
  Future<ProductionWarning?> checkRequest(ApiRequestEntity request) async {
    if (!_prefs.confirmProductionWrites) return null;
    return checkSend(request.method, request.name, url: await _urlOf(request), body: _rawBody(request), graphqlQuery: _graphql(request));
  }

  /// A collection run sends many requests; [writeCount] of them change data and
  /// [destructiveCount] of those delete it. By environment name only: use
  /// [checkRunRequests] to judge the requests themselves.
  Future<ProductionWarning?> checkRun(int writeCount, String collectionName, {int destructiveCount = 0}) async {
    if (writeCount == 0 || !_prefs.confirmProductionWrites) return null;
    final env = await _productionEnvironment();
    if (env == null) return null;
    if (destructiveCount == 0 && _prefs.isSilenced(env)) return null;
    return ProductionWarning(env, _runDescription(collectionName, writeCount, destructiveCount), destructive: destructiveCount > 0);
  }

  /// [checkRun] for the requests a run is about to send: each is judged by its
  /// intent and its destination, and the person is asked once for the lot.
  Future<ProductionWarning?> checkRunRequests(Iterable<ApiRequestEntity> requests, String collectionName) async {
    if (!_prefs.confirmProductionWrites) return null;
    final env = await _productionEnvironment();
    var writes = 0;
    var deletes = 0;
    ({String target, String? reason})? first;
    for (final request in requests) {
      final url = await _urlOf(request);
      final effect = ProductionDetector.classify(request.method, url: url, body: _rawBody(request), graphqlQuery: _graphql(request));
      if (!effect.changesData) continue;
      final hit = _hit(env, url);
      if (hit == null) continue;
      first ??= hit;
      writes++;
      if (effect == RequestEffect.destructive) deletes++;
    }
    if (first == null) return null;
    if (deletes == 0 && _prefs.isSilenced(first.target)) return null;
    return ProductionWarning(first.target, _runDescription(collectionName, writes, deletes), destructive: deletes > 0, reason: first.reason);
  }

  String _runDescription(String collectionName, int writes, int deletes) =>
      'Running "$collectionName" sends $writes data-changing request${writes == 1 ? '' : 's'}'
      '${deletes == 0 ? '' : ', $deletes of them ${deletes == 1 ? 'deletes' : 'delete'} data'}';

  void silenceForSession(String environmentName) => _prefs.silenceForSession(environmentName);
}
