import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/unreachable_message.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../domain/entities/api_request_entity.dart';
import '../../domain/entities/api_response_entity.dart';
import '../../domain/entities/key_value_item.dart';
import '../../domain/entities/request_auth.dart';
import '../../domain/entities/request_body.dart';
import '../../domain/repositories/request_repository.dart';
import '../../domain/services/code_generators/code_generator.dart';
import '../../domain/services/importers/curl_parser.dart';
import '../../../../core/enums/body_type.dart';
import '../../domain/usecases/generate_code_snippet_usecase.dart';
import '../../domain/usecases/send_request_usecase.dart';
import '../../../request_flow/domain/entities/flow_report.dart';
import '../../../request_flow/domain/usecases/request_flow_service.dart';
import '../../../scripting/domain/entities/script_run_result.dart';
import '../../../scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../../../settings/domain/entities/request_settings.dart';

final class RequestBuilderViewModel with ChangeNotifier {
  final RequestRepository _requestRepository;
  final SendRequestUseCase _sendRequestUseCase;
  final GenerateCodeSnippetUseCase _generateCodeSnippetUseCase;
  final RunRequestScriptsUseCase _runRequestScriptsUseCase;

  /// Retry, poll until and fetch all pages for the requests that have them. Without it every send is a single send.
  final RequestFlowService? _flow;

  RequestBuilderViewModel(
    this._requestRepository,
    this._sendRequestUseCase,
    this._generateCodeSnippetUseCase,
    this._runRequestScriptsUseCase, [
    this._flow,
  ]);

  ApiRequestEntity? request;

  /// What the flow around the last send did (retries, polls, pages); null when it had nothing to report.
  FlowReport? lastFlow;

  /// While a send is in flight, what its flow is doing right now (`attempt 2/3 after 1.2 s`); null otherwise.
  String? flowStatus;

  /// Fetch all pages is on for this request, so Send says so: it will send more than one request.
  bool fetchAllPages = false;

  String get sendLabel => fetchAllPages ? 'Send (all pages)' : 'Send';

  StreamSubscription<RequestSettings>? _settingsSubscription;

  /// Bumped when the URL was replaced from outside the URL field (a pasted cURL
  /// command), so the field can show the new text.
  int urlRevision = 0;
  ApiResponseEntity? response;
  ScriptRunResult? lastScriptResult;
  bool isLoading = false;
  bool isSending = false;
  String? errorMessage;
  String? errorDetail;

  /// Asked before a send leaves the app; returning false cancels it. The page
  /// sets this (the production lock lives there) so the view model stays free of dialogs.
  Future<bool> Function(ApiRequestEntity request)? confirmSend;

  StreamSubscription<ApiRequestEntity?>? _requestSubscription;
  ApiCancelToken? _cancelToken;
  bool _disposed = false;

  Future<void> load(int requestId) async {
    isLoading = true;
    response = null;
    lastScriptResult = null;
    lastFlow = null;
    flowStatus = null;
    fetchAllPages = false;
    errorMessage = null;
    errorDetail = null;
    notifyListeners();
    _requestSubscription?.cancel();
    _requestSubscription = _requestRepository.watchById(requestId).listen(_mergeExternalName);
    _settingsSubscription?.cancel();
    _settingsSubscription = _flow?.watch(requestId).listen((settings) {
      if (settings.pagination.enabled == fetchAllPages || _disposed) return;
      fetchAllPages = settings.pagination.enabled;
      notifyListeners();
    });
    request = await _requestRepository.findById(requestId);
    // Known before the first frame, so Send does not flash its plain label before it says "(all pages)".
    final flow = _flow;
    if (flow != null) fetchAllPages = (await flow.settingsOf(requestId)).pagination.enabled;
    isLoading = false;
    notifyListeners();
  }

  Future<void> send() async {
    final current = request;
    if (current == null || isSending) return;
    final confirm = confirmSend;
    if (confirm != null && !await confirm(current)) return;
    if (_disposed || isSending) return;

    final cancelToken = _cancelToken = ApiCancelToken();
    isSending = true;
    errorMessage = null;
    errorDetail = null;
    lastScriptResult = null;
    lastFlow = null;
    flowStatus = null;
    notifyListeners();

    ApiResponseEntity? sent;
    String? flowFailure;
    try {
      final flow = _flow;
      if (flow == null) {
        sent = await _sendRequestUseCase(current, cancelToken: cancelToken);
      } else {
        final outcome = await flow.send(current, cancelToken: cancelToken, onNote: _onFlowNote);
        lastFlow = outcome.report.isNoteworthy ? outcome.report : null;
        // The last try failed with nothing to show: the same error, told the same way, as a plain send.
        if (outcome.error != null) throw outcome.error!;
        sent = outcome.response;
        flowFailure = outcome.report.failure;
      }
      response = sent;
    } catch (e) {
      if (!cancelToken.isCancelled) {
        // A failed send has no response of its own; keeping the previous one
        // would show (and let the user save) a result this send never produced.
        response = null;
        errorMessage = _describeError(e);
        errorDetail = _detailOf(e, errorMessage!);
      }
    }
    // A poll that never held, a page that failed: the response (the last, or what was merged so far) stays on screen.
    if (flowFailure != null && !cancelToken.isCancelled) errorMessage = _masked(flowFailure);
    if (sent != null) {
      // Apart from the send: a failing script is not a server that could not be reached.
      try {
        lastScriptResult = await _runRequestScriptsUseCase(
          RunRequestScriptsParams(
            requestId: current.id,
            collectionId: current.collectionId,
            response: sent,
            folderId: current.folderId,
          ),
        );
      } catch (e) {
        if (!cancelToken.isCancelled) {
          errorMessage = 'The response arrived, but the tests and variable saves could not run: '
              '${_firstLine(_masked(e.toString()))}';
          errorDetail = _detailOf(e, errorMessage!);
        }
      }
    }

    _cancelToken = null;
    isSending = false;
    flowStatus = null;
    if (!_disposed) notifyListeners();
  }

  void _onFlowNote(String message) {
    flowStatus = message;
    if (!_disposed) notifyListeners();
  }

  /// Abandons the send in flight; [send] then finishes without an error.
  void cancelSend() => _cancelToken?.cancel();

  /// The one line shown for what [SendRequestUseCase] threw, saying what went
  /// wrong and what to do. [DioApiClient] wraps every network failure in a
  /// [NetworkException] that carries its own `summary` (DNS, refused
  /// connection, TLS, timeout with its limit, ...); an unsendable URL is an
  /// [InvalidUrlException], an undefined `{{variable}}` or bad JSON an
  /// [InvalidRequestException], and a URL `Uri.parse` can't read surfaces as a
  /// [FormatException] before the request ever reaches Dio. The text can
  /// quote the URL or a proxy, so it is masked.
  String _describeError(Object error) {
    switch (error) {
      case NetworkException(kind: NetworkErrorKind.cancelled):
        return 'Request cancelled';
      case NetworkException(:final summary?):
        return _masked(summary);
      case NetworkException(:final kind, :final message):
        return switch (kind) {
          NetworkErrorKind.timeout =>
            'The request timed out — raise the "Request timeout" in Settings if the server is just slow.',
          NetworkErrorKind.connectionError => unreachableServerMessage(),
          NetworkErrorKind.badResponse => 'The server returned a response that could not be read.',
          _ => 'The request failed: ${_firstLine(_masked(message))}',
        };
      case InvalidUrlException():
        return "That URL isn't valid — it needs an http(s) scheme and a host, e.g. https://api.example.com/users";
      case InvalidRequestException(:final message):
        return _masked(message);
      case FormatException(:final message):
        return 'The URL or a header could not be read: ${_firstLine(_masked(message))}';
      default:
        return 'The request failed: ${_firstLine(_masked(error.toString()))}';
    }
  }

  /// The full text behind [summary], for the expandable details; null when it
  /// would only repeat it (an [InvalidRequestException] already says it all).
  String? _detailOf(Object error, String summary) {
    if (error is InvalidRequestException) return null;
    final detail = _masked(error.toString()).trim();
    return detail.isEmpty || detail == summary ? null : detail;
  }

  /// Secrets can ride along in an exception's text: the URL a failure quotes,
  /// the credentials of a proxy, a token in a header.
  static String _masked(String text) => SecretMasker.maskMessage(text);

  static String _firstLine(String text) {
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return text.trim();
  }

  void updateName(String name) => _update((r) => r.copyWith(name: name));
  void updateMethod(HttpMethod method) => _update((r) => r.copyWith(method: method));
  void updateUrl(String url) {
    if (applyPastedCurl(url)) return;
    _update((r) => r.copyWith(url: url));
  }

  /// Smart paste: a `curl ...` command pasted into the URL field fills the
  /// whole request (method, URL, headers, body, auth) instead of becoming a
  /// nonsense URL. Returns whether [text] was one.
  bool applyPastedCurl(String text) {
    final trimmed = text.trimLeft();
    if (!RegExp(r'^curl\s', caseSensitive: false).hasMatch(trimmed)) return false;
    final parsed = CurlParser.parse(trimmed);
    if (parsed == null || parsed.url.isEmpty) return false;
    final pasted = parsed.requestBody;
    _update((r) => r.copyWith(
          method: parsed.method,
          url: parsed.url,
          headers: parsed.headers,
          body: pasted.type == BodyType.none ? r.body : pasted,
          auth: parsed.auth,
        ));
    urlRevision++;
    notifyListeners();
    return true;
  }
  void updateHeaders(List<KeyValueItem> headers) => _update((r) => r.copyWith(headers: headers));
  void updateQueryParams(List<KeyValueItem> params) => _update((r) => r.copyWith(queryParams: params));
  void updateBody(RequestBody body) => _update((r) => r.copyWith(body: body));
  void updateAuth(RequestAuth auth) => _update((r) => r.copyWith(auth: auth));

  void _update(ApiRequestEntity Function(ApiRequestEntity) transform) {
    final current = request;
    if (current == null) return;
    request = transform(current);
    notifyListeners();
    _requestRepository.saveRequest(request!);
  }

  /// Every edit re-saves the whole request from this snapshot, so a rename made
  /// elsewhere (the sidebar) must land here or the next edit would undo it. A
  /// move to another folder lands too: what the request inherits (headers,
  /// auth, variables, tests) follows its folder.
  void _mergeExternalName(ApiRequestEntity? latest) {
    final current = request;
    if (latest == null || current == null) return;
    final renamed = latest.name != current.name;
    final moved = latest.folderId != current.folderId || latest.collectionId != current.collectionId;
    // A token the app renewed by itself before a send (see `OAuth2TokenManager`) is stored on the request; without it
    // here the next edit would save the old token over it, and the old refresh token may no longer work.
    final renewedAuth = current.auth.takeNewerOAuth2Token(latest.auth);
    if (!renamed && !moved && renewedAuth == null) return;
    var merged = current;
    if (renamed) merged = merged.copyWith(name: latest.name);
    if (moved) merged = merged.inFolder(latest.folderId, collectionId: latest.collectionId);
    if (renewedAuth != null) merged = merged.copyWith(auth: renewedAuth);
    request = merged;
    notifyListeners();
  }

  Future<String> generateCodeSnippet(CodeGenerator generator) {
    final current = request;
    if (current == null) return Future.value('');
    return _generateCodeSnippetUseCase(GenerateCodeSnippetParams(current, generator));
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel();
    _requestSubscription?.cancel();
    _settingsSubscription?.cancel();
    super.dispose();
  }
}
