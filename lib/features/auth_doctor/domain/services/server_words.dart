// Pure Dart (no Flutter, no database).
import 'dart:convert';
import 'auth_context.dart';

/// What the server said about the rejection in its own words: the `error_description` of a Bearer challenge, or the
/// message of a JSON error body, or a short plain-text body. Always masked and clipped before it is quoted.
abstract final class ServerWords {
  static const _keys = ['error_description', 'message', 'detail', 'error_message', 'errorMessage', 'msg', 'error', 'title', 'reason'];

  /// The server's own explanation, or null when it gave none.
  static String? of(AuthContext ctx) {
    for (final challenge in ctx.challenges) {
      final description = challenge.errorDescription;
      if (description != null && description.trim().isNotEmpty) return ctx.quote(description);
    }
    final body = ctx.body.trim();
    if (body.isEmpty) return null;
    if (ctx.isJson) {
      try {
        final found = _fromJson(jsonDecode(body));
        if (found != null) return ctx.quote(found);
      } on FormatException {
        // Not JSON after all.
      }
      return null;
    }
    if (!ctx.isHtml && body.length <= 300) return ctx.quote(body);
    return null;
  }

  /// The evidence line for [of], or nothing.
  static List<String> evidence(AuthContext ctx) {
    final words = of(ctx);
    return words == null ? const [] : ['The server said: "$words"'];
  }

  static String? _fromJson(Object? node, [int depth = 0]) {
    if (depth > 3) return null;
    if (node is Map) {
      for (final key in _keys) {
        final value = node[key];
        if (value is String && value.trim().isNotEmpty) return value;
      }
      for (final key in const ['error', 'errors', 'data', 'detail']) {
        final nested = _fromJson(node[key], depth + 1);
        if (nested != null) return nested;
      }
    } else if (node is List && node.isNotEmpty) {
      return _fromJson(node.first, depth + 1);
    } else if (node is String && node.trim().isNotEmpty) {
      return node;
    }
    return null;
  }
}
