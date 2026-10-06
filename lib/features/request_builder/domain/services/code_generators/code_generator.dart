import 'dart:convert';
import '../../../../../core/network/upload_body.dart';
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

/// The form of a request that carries a file, for the generators. A form-data body with a `file` part and a binary
/// body cannot be printed as the bytes they send (the bytes live in a file the snippet only names), so each generator
/// writes them with its language's own multipart or file API, naming the file by its path.
MultipartUpload? multipartOf(ResolvedRequestSpec spec) => switch (spec.upload) {
      final MultipartUpload upload => upload,
      _ => null,
    };

/// The file a binary body sends.
UploadFile? binaryFileOf(ResolvedRequestSpec spec) => switch (spec.upload) {
      BinaryUpload(:final file) => file,
      _ => null,
    };

/// The headers a snippet writes. A multipart body's `Content-Type` is left out: it holds the boundary of the body
/// PostPilot wrote, while every client library writes its own boundary together with the header.
Map<String, String> snippetHeadersOf(ResolvedRequestSpec spec) {
  if (multipartOf(spec) == null) return spec.headers;
  return {
    for (final entry in spec.headers.entries)
      if (entry.key.toLowerCase() != 'content-type') entry.key: entry.value,
  };
}

/// Whether the name sent for [file] is not the one a library would take from its path, so a generator that cannot
/// set a name has to say so.
bool hasCustomFileName(UploadFile file) => file.fileName != FilePaths.baseName(file.path);
