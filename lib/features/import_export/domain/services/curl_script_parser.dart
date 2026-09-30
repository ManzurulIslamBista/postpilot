import '../../../../core/enums/body_type.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../../../request_builder/domain/services/importers/curl_parser.dart';
import '../entities/imported_collection.dart';
import 'imported_body_mapper.dart';

/// Reads a text with one or more `curl` commands (a pasted command, or a
/// whole script such as the one "Export cURL script" writes) into requests.
///
/// A command may span lines (`\` continuations, quoted multi-line bodies). The
/// last `#` comment above a command names the request; without one it is
/// named "METHOD /path". Lines that aren't curl commands (`echo`, `set -e`,
/// the shebang) are ignored.
abstract final class CurlScriptParser {
  static final _curlStart = RegExp(r'^(?:\$\s+)?curl(?:\.exe)?(?=\s|$)', caseSensitive: false);
  static final _commentPrefix = RegExp(r'^#+\s*');

  /// Requests found, plus how many `curl` commands had no URL or were cut off.
  static ({List<ImportedRequest> requests, int skipped}) parse(String script) {
    final requests = <ImportedRequest>[];
    var skipped = 0;
    for (final entry in _split(script)) {
      final request = _requestOf(entry.command, entry.name);
      if (request == null) {
        skipped++;
      } else {
        requests.add(request);
      }
    }
    return (requests: requests, skipped: skipped);
  }

  static ImportedRequest? _requestOf(String command, String? name) {
    final ParsedCurlRequest? parsed;
    try {
      parsed = CurlParser.parse(_normalized(command));
    } on RangeError {
      return null;
    }
    if (parsed == null) return null;

    final headers = [...parsed.headers];
    final rawBody = parsed.body;
    var body = RequestBody.empty;
    if (rawBody != null) {
      body = RequestBody(
        type: BodyType.raw,
        rawContentType: _rawTypeOf(headers, rawBody),
        rawText: rawBody,
      );
      // curl sends `-d` data as a form unless told otherwise.
      if (!ImportedBodyMapper.hasContentType(headers) && body.rawContentType == RawContentType.text) {
        headers.add(KeyValueItem(key: ImportedBodyMapper.contentTypeHeader, value: 'application/x-www-form-urlencoded'));
      }
    }
    final uri = Uri.tryParse(parsed.url);
    final path = uri == null || uri.path.isEmpty ? '/' : uri.path;
    return ImportedRequest(
      name ?? '${parsed.method.label} $path',
      method: parsed.method,
      url: parsed.url,
      headers: headers,
      body: body,
      auth: parsed.auth,
    );
  }

  static RawContentType _rawTypeOf(List<KeyValueItem> headers, String body) {
    for (final h in headers) {
      if (h.key.toLowerCase() == ImportedBodyMapper.contentTypeHeader.toLowerCase()) {
        return ImportedBodyMapper.rawTypeOf(h.value);
      }
    }
    return ImportedBodyMapper.sniffRawType(body);
  }

  /// [CurlParser] tokenizes quotes but not the shell's `'\''` idiom (an
  /// apostrophe inside single quotes, which `CurlGenerator` emits), so that is
  /// rewritten to the equivalent `'"'"'` first; `curl.exe` and a `$ ` prompt
  /// are reduced to plain `curl`.
  static String _normalized(String command) =>
      command.trim().replaceFirst(_curlStart, 'curl').replaceAll(r"'\''", "'\"'\"'");

  /// Splits [script] into commands, each with the comment that names it.
  static List<({String? name, String command})> _split(String script) {
    final entries = <({String? name, String command})>[];
    StringBuffer? current;
    String? currentName;
    String? pendingName;
    var quote = '';

    for (final line in script.replaceAll('\r\n', '\n').split('\n')) {
      if (current == null) {
        final trimmed = line.trim();
        if (trimmed.startsWith('#')) {
          if (!trimmed.startsWith('#!')) pendingName = trimmed.replaceFirst(_commentPrefix, '').trim();
          continue;
        }
        if (!_curlStart.hasMatch(trimmed)) continue;
        current = StringBuffer();
        currentName = pendingName == null || pendingName.isEmpty ? null : pendingName;
        pendingName = null;
      } else {
        current.write('\n');
      }
      current.write(line);
      quote = _quoteStateAfter(line, quote);
      final continues = quote.isNotEmpty || line.trimRight().endsWith(r'\');
      if (!continues) {
        entries.add((name: currentName, command: current.toString()));
        current = null;
      }
    }
    if (current != null) entries.add((name: currentName, command: current.toString()));
    return entries;
  }

  /// The open quote (`'`, `"` or empty) after [line], starting from [quote]
  /// carried over from the previous line. A backslash escapes the next
  /// character outside single quotes; an unquoted ` #` starts a comment.
  static String _quoteStateAfter(String line, String quote) {
    var state = quote;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (state == "'") {
        if (char == "'") state = '';
      } else if (char == r'\') {
        i++;
      } else if (state == '"') {
        if (char == '"') state = '';
      } else if (char == "'" || char == '"') {
        state = char;
      } else if (char == '#' && (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
        break;
      }
    }
    return state;
  }
}
