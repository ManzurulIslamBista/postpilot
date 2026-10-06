import 'dart:convert';
import 'package:yaml/yaml.dart';
import '../entities/import_format.dart';
import 'backup_codec.dart';

/// Recognises which importer a pasted document belongs to, from its shape
/// alone. Pure and side-effect free, so the dialog can call it on every edit.
abstract final class ImportFormatDetector {
  static final _curlLine = RegExp(r'^(?:\$\s+)?curl(?:\.exe)?\s', caseSensitive: false);
  static final _insomniaV5 = RegExp(r'''^type:\s*["']?collection\.insomnia\.rest/''', multiLine: true);
  static final _openApiYaml = RegExp(r'''^["']?(?:openapi|swagger)["']?\s*:\s*["']?[23]''', multiLine: true);

  static ImportFormat detect(String text) {
    final trimmed = text.replaceFirst('﻿', '').trim();
    if (trimmed.isEmpty) return ImportFormat.unknown;
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return _detectJson(trimmed);
    if (_startsWithCurl(trimmed)) return ImportFormat.curl;
    return _detectYaml(trimmed);
  }

  static ImportFormat _detectJson(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return ImportFormat.unknown;
    }
    return decoded is Map ? _detectMap(decoded) : ImportFormat.unknown;
  }

  static ImportFormat _detectMap(Map<dynamic, dynamic> map) {
    if (map['format'] == BackupCodec.formatId) return ImportFormat.backup;
    final type = map['type'];
    if (map['_type'] == 'export' || (type is String && type.startsWith('collection.insomnia.rest/'))) {
      return ImportFormat.insomnia;
    }
    final log = map['log'];
    if (log is Map && log['entries'] is List) return ImportFormat.har;
    if (map.containsKey('openapi') || map.containsKey('swagger')) return ImportFormat.openApi;
    if (map['info'] is Map && map['item'] is List) return ImportFormat.postman;
    if (_isPostmanEnvironment(map)) return ImportFormat.postmanEnvironment;
    return ImportFormat.unknown;
  }

  /// An exported environment or globals file: a `values` list of `{key, value, ...}` entries, which
  /// Postman marks with `_postman_variable_scope`. A hand-trimmed file without the marker still counts
  /// when it has a name and every entry is a keyed object.
  static bool _isPostmanEnvironment(Map<dynamic, dynamic> map) {
    final values = map['values'];
    if (values is! List) return false;
    if (map['_postman_variable_scope'] is String) return true;
    return map['name'] is String && values.every((entry) => entry is Map && entry.containsKey('key'));
  }

  static ImportFormat _detectYaml(String text) {
    if (_insomniaV5.hasMatch(text)) return ImportFormat.insomnia;
    if (_openApiYaml.hasMatch(text)) return ImportFormat.openApi;
    try {
      final doc = loadYaml(text);
      if (doc is Map) return _detectMap(doc);
    } catch (_) {
      // Arbitrary pasted text: whatever the YAML parser chokes on is simply not a known format.
    }
    return ImportFormat.unknown;
  }

  /// The first line that is neither blank nor a `#` comment must start a curl
  /// command, so a whole exported script (which opens with comments) counts.
  static bool _startsWithCurl(String text) {
    var start = 0;
    while (start < text.length) {
      final newline = text.indexOf('\n', start);
      final end = newline == -1 ? text.length : newline;
      final line = text.substring(start, end).trim();
      if (line.isNotEmpty && !line.startsWith('#')) return _curlLine.hasMatch(line);
      start = end + 1;
    }
    return false;
  }
}
