import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/network/api_client.dart';
import '../../../core/network/api_http_response.dart';
import 'ai_settings_store.dart';

/// Something went wrong asking the model, in words a person can act on.
final class AiException implements Exception {
  final String message;
  const AiException(this.message);

  @override
  String toString() => message;
}

/// Asks Claude through the Anthropic Messages API with the person's own key.
/// Goes through the app's [ApiClient], so the proxy and TLS settings apply and
/// the call shows in the Console like any other.
final class AiClient {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  final ApiClient _api;
  final AiSettingsStore _settings;

  const AiClient(this._api, this._settings);

  Future<bool> get hasKey async => (await _settings.apiKey()) != null;

  Future<String> complete({required String system, required String user, int maxTokens = 2048}) async {
    final key = await _settings.apiKey();
    if (key == null) throw const AiException('Add your Anthropic API key first.');
    final model = await _settings.model();
    final ApiHttpResponse response;
    try {
      response = await _api.send(ApiRequestSpec(
        method: 'POST',
        url: _endpoint,
        headers: {
          'x-api-key': key,
          'anthropic-version': _version,
          'content-type': 'application/json',
          // A browser blocks the call unless the caller says it knowingly sends its own key.
          if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
        },
        body: utf8.encode(jsonEncode({
          'model': model,
          'max_tokens': maxTokens,
          'system': system,
          'messages': [
            {'role': 'user', 'content': user},
          ],
        })),
        options: const ApiRequestOptions(timeout: Duration(seconds: 90), maxResponseBytes: 4 * 1024 * 1024),
      ));
    } catch (e) {
      throw AiException("Couldn't reach the Anthropic API. Check your connection. ($e)");
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      // Handled below with the status code.
    }
    if (response.statusCode >= 400 || json is! Map) throw AiException(_describe(response.statusCode, json, text));
    final content = json['content'];
    if (content is List) {
      final parts = [for (final c in content) if (c is Map && c['type'] == 'text') '${c['text']}'];
      if (parts.isNotEmpty) return parts.join('\n').trim();
    }
    throw const AiException('The model answered with nothing. Try again.');
  }

  String _describe(int status, Object? json, String body) {
    final error = json is Map && json['error'] is Map ? json['error'] as Map : null;
    final detail = error?['message'] ?? (body.length > 160 ? '${body.substring(0, 160)}…' : body);
    return switch (status) {
      401 => 'The API key was rejected. Check it in the AI settings.',
      403 => 'This key is not allowed to use that model or feature. $detail',
      404 => 'The model "${error?['message'] ?? 'unknown'}" was not found. Choose another model in the AI settings.',
      429 => 'Rate limit reached. Wait a moment and try again.',
      >= 500 => 'The Anthropic service is busy or down ($status). Try again shortly.',
      _ => 'The request was refused ($status): $detail',
    };
  }
}
