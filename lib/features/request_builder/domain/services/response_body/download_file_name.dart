import '../../../../../core/utils/safe_file_name.dart';

// The extension of a saved body comes from this table, never from the
// response headers themselves: a Content-Type is server-controlled text and
// must not decide what a file on the user's disk is called. Types that would
// save as a script (JavaScript, shell) are deliberately absent, so they fall
// back to a plain-text extension.
const _extensionByMimeType = <String, String>{
  'application/json': 'json',
  'application/xml': 'xml',
  'text/xml': 'xml',
  'text/html': 'html',
  'image/svg+xml': 'svg',
  'text/csv': 'csv',
  'text/css': 'css',
  'text/markdown': 'md',
  'text/x-markdown': 'md',
  'application/yaml': 'yaml',
  'application/x-yaml': 'yaml',
  'text/yaml': 'yaml',
  'text/x-yaml': 'yaml',
  'application/toml': 'toml',
  'application/pdf': 'pdf',
  'application/zip': 'zip',
  'application/gzip': 'gz',
  'application/x-gzip': 'gz',
  'application/x-tar': 'tar',
  'application/x-bzip2': 'bz2',
  'application/x-7z-compressed': '7z',
  'application/vnd.rar': 'rar',
  'application/x-rar-compressed': 'rar',
  'application/msword': 'doc',
  'application/vnd.ms-excel': 'xls',
  'application/vnd.ms-powerpoint': 'ppt',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
  'application/vnd.oasis.opendocument.text': 'odt',
  'application/vnd.oasis.opendocument.spreadsheet': 'ods',
  'application/vnd.oasis.opendocument.presentation': 'odp',
  'application/rtf': 'rtf',
  'application/epub+zip': 'epub',
  'application/wasm': 'wasm',
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/bmp': 'bmp',
  'image/avif': 'avif',
  'image/tiff': 'tiff',
  'image/x-icon': 'ico',
  'image/vnd.microsoft.icon': 'ico',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/ogg': 'ogg',
  'video/mp4': 'mp4',
  'video/webm': 'webm',
  'video/quicktime': 'mov',
  'font/woff': 'woff',
  'font/woff2': 'woff2',
  'font/ttf': 'ttf',
  'font/otf': 'otf',
};

final _extendedFilename = RegExp(r'(?:^|;)\s*filename\*\s*=\s*([^;]*)', caseSensitive: false);
final _plainFilename = RegExp(r'(?:^|;)\s*filename\s*=\s*("(?:[^"\\]|\\.)*"|[^;]*)', caseSensitive: false);
final _pathSeparators = RegExp(r'[/\\]');
final _escapedChar = RegExp(r'\\(.)');
final _plainExtension = RegExp(r'^[a-z0-9]{1,8}$', caseSensitive: false);

/// The file extension for [mimeType], or null when it is not in the table.
String? extensionForMimeType(String mimeType) => _extensionByMimeType[mimeType];

/// The file name a server suggests in a Content-Disposition header, reduced to
/// a single safe path component with a plain alphanumeric extension that is
/// not executable; anything else about the extension is replaced by
/// [fallbackExtension]. Null when the header names no usable file.
String? fileNameFromContentDisposition(String? header, {required String fallbackExtension}) {
  if (header == null) return null;
  final raw = _extendedName(header) ?? _plainName(header);
  if (raw == null) return null;
  final name = sanitizeFileName(raw.split(_pathSeparators).last);
  if (name == null) return null;

  final dot = name.lastIndexOf('.');
  if (dot == -1) return '$name.$fallbackExtension';
  final extension = name.substring(dot + 1);
  if (isExecutableExtension(extension)) return '${name.substring(0, dot)}.$fallbackExtension';
  return _plainExtension.hasMatch(extension) ? name : '$name.$fallbackExtension';
}

// RFC 5987/6266 `filename*=UTF-8''percent-encoded`, which wins over `filename`.
String? _extendedName(String header) {
  final value = _extendedFilename.firstMatch(header)?[1]?.trim();
  if (value == null) return null;
  final parts = value.split("'");
  if (parts.length < 3 || parts.first.toLowerCase() != 'utf-8') return null;
  try {
    return Uri.decodeComponent(parts.sublist(2).join("'"));
  } catch (_) {
    return null;
  }
}

String? _plainName(String header) {
  final value = _plainFilename.firstMatch(header)?[1]?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1).replaceAllMapped(_escapedChar, (match) => match[1]!);
  }
  return value;
}
