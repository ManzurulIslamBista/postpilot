import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/unreachable_message.dart';
import '../../../../core/network/api_http_response.dart';
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
import '../../../scripting/domain/entities/script_run_result.dart';
import '../../../scripting/domain/usecases/run_request_scripts_usecase.dart';

final class RequestBuilderViewModel with ChangeNotifier {
  final RequestRepository _requestRepository;
  final SendRequestUseCase _sendRequestUseCase;
  final GenerateCodeSnippetUseCase _generateCodeSnippetUseCase;
  final RunRequestScriptsUseCase _runRequestScriptsUseCase;

  RequestBuilderViewModel(
    this._requestRepository,
    this._sendRequestUseCase,
    this._generateCodeSnippetUseCase,
    this._runRequestScriptsUseCase,
  );

  ApiRequestEntity? request;

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
    errorMessage = null;
    errorDetail = null;
    notifyListeners();
    _requestSubscription?.cancel();
    _requestSubscription = _requestRepository.watchById(requestId).listen(_mergeExternalName);
    request = await _requestRepository.findById(requestId);
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
    notifyListeners();

    ApiResponseEntity? sent;
    try {
      sent = await _sendRequestUseCase(current, cancelToken: cancelToken);
      response = sent;
      lastScriptResult = await _runRequestScriptsUseCase(
        RunRequestScriptsParams(requestId: current.id, collectionId: current.collectionId, response: sent),
      );
    } catch (e) {
      if (!cancelToken.isCancelled) {
        // A failed send has no response of its own; keeping the previous one
        // would show (and let the user save) a result this send never produced.
        if (sent == null) response = null;
        errorMessage = _describeError(e);
        // The message of an InvalidRequestException already says it all.
        errorDetail = e is InvalidRequestException ? null : e.toString();
      }
    }

    _cancelToken = null;
    isSending = false;
    if (!_disposed) notifyListeners();
  }

  /// Abandons the send in flight; [send] then finishes without an error.
  void cancelSend() => _cancelToken?.cancel();

  /// Translates the exceptions actually thrown by [SendRequestUseCase] into
  /// short, human-readable text. [DioApiClient] wraps every network failure
  /// in a [NetworkException] with a [NetworkErrorKind]; an unsendable URL is
  /// an [InvalidUrlException], and one `Uri.parse` can't read surfaces as a
  /// [FormatException] before the request ever reaches Dio.
  String _describeError(Object error) {
    if (error is NetworkException) {
      switch (error.kind) {
        case NetworkErrorKind.timeout:
          return 'Request timed out';
        case NetworkErrorKind.connectionError:
          return unreachableServerMessage();
        case NetworkErrorKind.badResponse:
          return 'The server returned an unexpected response';
        case NetworkErrorKind.cancelled:
          return 'Request cancelled';
        case NetworkErrorKind.other:
          return 'Something went wrong sending this request';
      }
    }
    if (error is InvalidUrlException) {
      return "That URL isn't valid — it needs a host, e.g. https://api.example.com/users";
    }
    if (error is InvalidRequestException) return error.message;
    if (error is FormatException) {
      return unreachableServerMessage();
    }
    return 'Something went wrong sending this request';
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
    final raw = parsed.body;
    final looksJson = raw != null && (raw.trimLeft().startsWith('{') || raw.trimLeft().startsWith('['));
    _update((r) => r.copyWith(
          method: parsed.method,
          url: parsed.url,
          headers: parsed.headers,
          body: raw == null
              ? r.body
              : RequestBody(type: BodyType.raw, rawContentType: looksJson ? RawContentType.json : RawContentType.text, rawText: raw),
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
  /// elsewhere (the sidebar) must land here or the next edit would undo it.
  void _mergeExternalName(ApiRequestEntity? latest) {
    final current = request;
    if (latest == null || current == null || latest.name == current.name) return;
    request = current.copyWith(name: latest.name);
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
    super.dispose();
  }
}
