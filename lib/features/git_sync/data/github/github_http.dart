import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/entities/git_link.dart';
import '../../domain/repositories/git_credentials_store.dart';
import '../../domain/repositories/git_host_client.dart';

const _apiBase = 'https://api.github.com';
const _connectTimeout = Duration(seconds: 20);
const _receiveTimeout = Duration(seconds: 60);
const _unreadable = 'GitHub sent a response PostPilot could not read';

/// A decoded GitHub reply. Non-2xx statuses are plain data here so callers can
/// treat 404/409 as answers; [ensureOk] turns the rest into domain exceptions.
final class GitHubResponse {
  GitHubResponse({required this.status, required this.json, required this.headers, required this.hadToken});

  final int status;
  final Object? json;
  final Headers headers;
  final bool hadToken;

  bool get ok => status >= 200 && status < 300;

  String? header(String name) => headers[name]?.firstOrNull;

  String? get message {
    final body = json;
    return body is Map && body['message'] is String ? body['message'] as String : null;
  }

  /// The Git Data API answers 409 "Git Repository is empty." for a repository
  /// that has no commits yet.
  bool get isEmptyRepository => status == 409 && (message ?? '').toLowerCase().contains('empty');

  GitHubResponse ensureOk(String subject) => ok ? this : throw _failure(this, subject);

  /// Runs [parse] on the body; a body of the wrong shape becomes a
  /// [GitHostException] instead of leaking a cast error.
  T read<T>(T Function(Object? json) parse) {
    try {
      return parse(json);
    } on TypeError {
      throw const GitHostException(_unreadable);
    } on FormatException {
      throw const GitHostException(_unreadable);
    }
  }
}

/// Transport for the GitHub REST API: the only place that builds headers,
/// sends a request and maps HTTP failures to [GitHostException]s.
///
/// Browsers preflight cross-origin calls and api.github.com allows a fixed set
/// of request headers, so only Authorization, Accept, X-GitHub-Api-Version and
/// Content-Type are ever sent. Its Cache-Control (max-age=60) also lets a
/// browser serve a stale branch head or branch list, and without Cache-Control
/// or If-None-Match on the wire the only way around that is a throwaway query
/// parameter on GETs whose answer can change.
final class GitHubHttp {
  GitHubHttp(this._credentials, {Dio? dio}) : _dio = (dio ?? Dio())..options.baseUrl = _apiBase;

  final GitCredentialsStore _credentials;
  final Dio _dio;

  Future<String?> token() async {
    final saved = (await _credentials.readToken(GitProvider.github))?.trim();
    return saved == null || saved.isEmpty ? null : saved;
  }

  Future<String> requireToken() async => await token() ?? (throw const GitMissingTokenException());

  /// [cacheBust] false is for answers addressed by sha, which never change.
  Future<GitHubResponse> get(String path, {Map<String, Object> query = const {}, bool cacheBust = true}) =>
      _send('GET', path, query: query, cacheBust: cacheBust);

  Future<GitHubResponse> post(String path, Map<String, Object?> body) => _send('POST', path, body: body);

  Future<GitHubResponse> put(String path, Map<String, Object?> body) => _send('PUT', path, body: body);

  Future<GitHubResponse> patch(String path, Map<String, Object?> body) => _send('PATCH', path, body: body);

  Future<GitHubResponse> _send(
    String method,
    String path, {
    Map<String, Object> query = const {},
    Map<String, Object?>? body,
    bool cacheBust = false,
  }) async {
    final token = await this.token();
    if (body != null && token == null) throw const GitMissingTokenException();
    try {
      final res = await _dio.request<String>(
        path,
        data: body == null ? null : jsonEncode(body),
        queryParameters: {...query, if (cacheBust) 'cb': DateTime.now().millisecondsSinceEpoch},
        options: Options(
          method: method,
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          contentType: body == null ? null : Headers.jsonContentType,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          connectTimeout: _connectTimeout,
          receiveTimeout: _receiveTimeout,
        ),
      );
      return GitHubResponse(
        status: res.statusCode ?? 0,
        json: _decode(res.data),
        headers: res.headers,
        hadToken: token != null,
      );
    } on DioException catch (e) {
      throw GitHostException(_unreachable(e));
    }
  }
}

Object? _decode(String? body) {
  if (body == null || body.trim().isEmpty) return null;
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

String _unreachable(DioException e) => switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Could not reach GitHub: the request timed out.',
      _ => 'Could not reach GitHub. Check your internet connection and try again.',
    };

GitHostException _failure(GitHubResponse res, String subject) {
  final status = res.status;
  final text = (res.message ?? '').toLowerCase();
  if (status == 401) return GitAuthException(_rejectedToken(res.message));
  if (status == 403 || status == 429) {
    final limited = status == 429 ||
        res.header('x-ratelimit-remaining') == '0' ||
        res.header('retry-after') != null ||
        text.contains('rate limit');
    if (limited) return GitRateLimitException(_rateLimited(res));
    if (text.contains('bad credentials') || text.contains('saml') || text.contains('personal access token')) {
      return GitAuthException(_rejectedToken(res.message));
    }
  }
  if (status == 404) return GitNotFoundException('$subject not found, or your token cannot see it');
  return GitHostException(_describe(res));
}

String _rejectedToken(String? detail) =>
    detail == null ? 'GitHub rejected the saved token' : 'GitHub rejected the saved token: $detail';

String _rateLimited(GitHubResponse res) {
  final retryAfter = int.tryParse(res.header('retry-after') ?? '');
  final reset = int.tryParse(res.header('x-ratelimit-reset') ?? '');
  final when = retryAfter != null
      ? 'Try again in ${retryAfter}s.'
      : reset != null
          ? 'It resets at ${_clock(reset)}.'
          : 'Try again later.';
  final hint = res.hadToken ? '' : ' Saving a GitHub token raises the limit.';
  return 'GitHub rate limit reached. $when$hint';
}

String _clock(int epochSeconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String _describe(GitHubResponse res) {
  final message = res.message;
  if (message == null) return 'GitHub returned ${res.status}';
  final errors = (res.json as Map)['errors'];
  final details = errors is List
      ? [for (final e in errors) if (e is Map && e['message'] is String) e['message'] as String]
      : const <String>[];
  return details.isEmpty ? message : '$message (${details.join('; ')})';
}
