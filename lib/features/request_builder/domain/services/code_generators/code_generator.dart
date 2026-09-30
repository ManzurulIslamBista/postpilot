import 'dart:convert';
import '../resolved_request_spec.dart';

abstract interface class CodeGenerator {
  String get id;
  String get label;
  String generate(ResolvedRequestSpec spec);
}

/// Decodes a resolved body to text for display in a snippet, falling back to
/// a placeholder comment for binary payloads (e.g. multipart) instead of
/// emitting garbled bytes.
String? bodyTextOf(ResolvedRequestSpec spec) {
  final bytes = spec.bodyBytes;
  if (bytes == null || bytes.isEmpty) return null;
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

/// The value of header [name], matched case-insensitively.
String? headerValueOf(ResolvedRequestSpec spec, String name) {
  final wanted = name.toLowerCase();
  for (final entry in spec.headers.entries) {
    if (entry.key.toLowerCase() == wanted) return entry.value;
  }
  return null;
}
