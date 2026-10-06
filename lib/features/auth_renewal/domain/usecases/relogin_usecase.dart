import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../entities/relogin_config.dart';
import '../services/relogin_coordinator.dart';
import '../services/relogin_policy.dart';

/// Sends the login request through the normal send path, with its own re-login switched off so a login
/// that fails with 401 cannot start another one.
typedef LoginSender = Future<ApiResponseEntity> Function(ApiRequestEntity login);

/// What the Auth tab's "Test" button reports.
final class ReloginTestResult {
  final bool ok;

  /// What happened, in words for a person: the status and the variables the login saved, or why it failed.
  final String message;
  const ReloginTestResult(this.ok, this.message);
}

/// "On 401/403 run the login request first, then send the request again, once."
///
/// [SendRequestUseCase] calls [afterFailure] with the response of a request that came back rejected. It
/// finds the config in force (the nearest folder's, else the collection's), runs the login request the way
/// the collection runner would (sent, then its extractors run, so the token variable is filled), and if
/// that worked sends the original request again. Exactly once per original request: the retry is not
/// passed through here again, the login request is sent without re-login of its own, and a login that
/// fails (or whose extractors fail to save) means no retry. What happened is written into the response
/// ([ApiResponseEntity.authNotes]), so nothing happens silently.
final class ReloginUseCase {
  final RequestRepository _requests;
  final CollectionRepository? _collections;
  final CollectionAuthRepository _collectionAuth;
  final ResolveRequestDefaultsUseCase? _defaults;
  final RunRequestScriptsUseCase _scripts;
  final ReloginCoordinator _coordinator;

  ReloginUseCase(
    this._requests,
    this._collectionAuth,
    this._scripts, {
    this._collections,
    this._defaults,
    ReloginCoordinator? coordinator,
  }) : _coordinator = coordinator ?? ReloginCoordinator();

  /// [failed] is the answer to [request], sent at [sentAt]. Returns [failed] untouched when no re-login
  /// applies; otherwise the response of the retry (or [failed] with a note saying why there was none).
  /// Throws what [retry] throws.
  Future<ApiResponseEntity> afterFailure(
    ApiRequestEntity request,
    ApiResponseEntity failed, {
    required DateTime sentAt,
    required Map<String, String> dataVariables,
    required LoginSender login,
    required Future<ApiResponseEntity> Function() retry,
    ApiCancelToken? cancelToken,
  }) async {
    final ReloginConfig? config;
    try {
      config = await _configFor(request);
    } catch (_) {
      return failed; // a config that cannot be read must not change what the send returns
    }
    if (config == null || !config.triggersOn(failed.statusCode)) return failed;

    final candidates = await _candidates(request.collectionId);
    final lookup = ReloginPolicy.find(config.request, candidates);
    final ReloginCandidate<RequestSummaryEntity> target;
    switch (lookup) {
      case ReloginNotFound():
        return failed.withAuthNotes([ReloginPolicy.notFoundNote(config.request)]);
      case ReloginAmbiguous(:final count):
        return failed.withAuthNotes([ReloginPolicy.ambiguousNote(config.request, count)]);
      case ReloginFound(:final candidate):
        target = candidate;
    }
    // The login request itself answered 401: logging in to log in would be the loop this must never be.
    if (target.value.id == request.id) return failed;
    final problem = ReloginPolicy.methodProblem(target.method);
    if (problem != null) return failed.withAuthNotes([ReloginPolicy.methodNote(config.request, problem)]);

    final key = '${request.collectionId}|${config.request}';
    final outcome = await _coordinator.run(key, sentAt, () => _runLogin(target, dataVariables, login));
    _throwIfCancelled(cancelToken);
    if (!outcome.ok) {
      final why = outcome.failure ?? 'it failed';
      return failed.withAuthNotes([
        outcome.skipped
            ? ReloginPolicy.skippedNote(config.request, why)
            : ReloginPolicy.failedNote(config.request, why),
      ]);
    }

    final retried = await retry();
    if (config.triggersOn(retried.statusCode)) {
      // The new login did not help this request (a 403 for a user who may not do that, a token it does
      // not accept): another login for the next one would not either.
      _coordinator.markIneffective(key, 'the request was rejected again (HTTP ${retried.statusCode}) after the last re-login');
    }
    return retried.withAuthNotes([ReloginPolicy.retriedNote(config.request, failed.statusCode)]);
  }

  /// The "Test" button: runs the login request of [config] once, outside any request, and says how it went.
  Future<ReloginTestResult> test(int collectionId, ReloginConfig config, {required LoginSender login}) async {
    final lookup = ReloginPolicy.find(config.request, await _candidates(collectionId));
    final ReloginCandidate<RequestSummaryEntity> target;
    switch (lookup) {
      case ReloginNotFound():
        return ReloginTestResult(false, 'No request of this collection is called "${config.request}".');
      case ReloginAmbiguous(:final count):
        return ReloginTestResult(
          false,
          '"${config.request}" names $count requests. Rename one of them, or pick the login request again.',
        );
      case ReloginFound(:final candidate):
        target = candidate;
    }
    final problem = ReloginPolicy.methodProblem(target.method);
    if (problem != null) return ReloginTestResult(false, 'Not run: $problem.');

    final saved = <String>[];
    final result = await _runLogin(target, const {}, login, saved: saved);
    if (!result.ok) return ReloginTestResult(false, 'The login failed: ${result.failure}.');
    _coordinator.reset('$collectionId|${config.request}');
    final saves = saved.isEmpty
        ? 'It saves no variable, so only cookies carry the session.'
        : 'Saved ${saved.map((k) => '{{$k}}').join(', ')}.';
    return ReloginTestResult(true, 'Logged in via "${config.request}". $saves');
  }

  /// Every request of [collectionId] that could be picked as the login request, for the Auth tab's list.
  Future<List<ReloginCandidate<RequestSummaryEntity>>> candidates(int collectionId) => _candidates(collectionId);

  // --------------------------------------------------------------------------------------------

  Future<ReloginConfig?> _configFor(ApiRequestEntity request) async {
    final defaults = _defaults;
    if (defaults != null) return ReloginPolicy.configIn((await defaults.call(request)).chain);
    final auth = RequestAuth.fromJsonString(await _collectionAuth.getAuthJson(request.collectionId));
    final config = auth?.relogin;
    return config != null && config.isActive ? config : null;
  }

  Future<List<ReloginCandidate<RequestSummaryEntity>>> _candidates(int collectionId) async {
    final summaries = await _requests.watchByCollection(collectionId).first;
    final folders = await _collections?.watchFolders(collectionId).first ?? const <FolderEntity>[];
    final byId = {for (final f in folders) f.id: f};

    String pathOf(int? folderId) {
      final names = <String>[];
      var current = folderId == null ? null : byId[folderId];
      var guard = 0;
      while (current != null && guard++ < 64) {
        names.insert(0, current.name);
        current = current.parentFolderId == null ? null : byId[current.parentFolderId];
      }
      return names.join('/');
    }

    return [
      for (final s in summaries)
        ReloginCandidate(folderPath: pathOf(s.folderId), name: s.name, method: s.method, value: s),
    ];
  }

  /// Sends the login request and runs its extractors; never throws. Succeeds on a 2xx answer whose
  /// extractors all saved their variable: a login that returns 200 but saves no token would only repeat the
  /// stale one.
  Future<ReloginLogin> _runLogin(
    ReloginCandidate<RequestSummaryEntity> target,
    Map<String, String> dataVariables,
    LoginSender login, {
    List<String>? saved,
  }) async {
    try {
      final full = await _requests.findById(target.value.id);
      if (full == null) return const ReloginLogin.failed('the login request no longer exists');
      final response = await login(full);
      if (!response.isSuccess) return ReloginLogin.failed('it answered HTTP ${response.statusCode}');
      final scripts = await _scripts(RunRequestScriptsParams(
        requestId: full.id,
        collectionId: full.collectionId,
        response: response,
        dataVariables: dataVariables,
        folderId: full.folderId,
      ));
      final unsaved = scripts.extracted.where((e) => !e.ok).firstOrNull;
      if (unsaved != null) {
        return ReloginLogin.failed('it did not save {{${unsaved.key}}}: ${SecretMasker.maskMessage('${unsaved.error}')}');
      }
      saved?.addAll([for (final e in scripts.extracted) e.key]);
      return const ReloginLogin.ok();
    } catch (e) {
      return ReloginLogin.failed(_why(e));
    }
  }

  /// A person who stops a send must not see the answer of a request that was meant to be abandoned.
  static void _throwIfCancelled(ApiCancelToken? token) {
    if (token != null && token.isCancelled) {
      throw const NetworkException('Request cancelled', kind: NetworkErrorKind.cancelled);
    }
  }

  static String _why(Object e) {
    final text = e is NetworkException ? e.summary ?? e.message : e.toString();
    final line = SecretMasker.maskMessage(text).split(RegExp(r'[\r\n]+')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'it failed');
    final trimmed = line.trim();
    return trimmed.length <= 160 ? trimmed : '${trimmed.substring(0, 160)}…';
  }
}
