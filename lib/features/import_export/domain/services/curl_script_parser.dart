import '../../../request_builder/domain/services/importers/curl_parser.dart';
import '../entities/imported_collection.dart';

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

  /// Requests found, how many `curl` commands had no URL or were cut off, and what the readable ones
  /// asked for that PostPilot cannot do (a body read from a file, ...), each prefixed with the request's name.
  static ({List<ImportedRequest> requests, int skipped, List<String> notes}) parse(String script) {
    final requests = <ImportedRequest>[];
    final notes = <String>[];
    var skipped = 0;
    for (final entry in _split(script)) {
      final found = _requestOf(entry.command, entry.name);
      if (found == null) {
        skipped++;
      } else {
        requests.add(found.request);
        notes.addAll(found.notes.map((note) => '${found.request.name}: $note'));
      }
    }
    return (requests: requests, skipped: skipped, notes: notes);
  }

  static ({ImportedRequest request, List<String> notes})? _requestOf(String command, String? name) {
    final parsed = CurlParser.parse(_normalized(command));
    if (parsed == null) return null;

    final uri = Uri.tryParse(parsed.url);
    final path = uri == null || uri.path.isEmpty ? '/' : uri.path;
    final request = ImportedRequest(
      name ?? '${parsed.method.label} $path',
      method: parsed.method,
      url: parsed.url,
      headers: parsed.headers,
      body: parsed.requestBody,
      auth: parsed.auth,
    );
    return (request: request, notes: parsed.notes);
  }

  /// `curl.exe` and a `$ ` prompt are reduced to plain `curl`. (The shell's `'\''` idiom for an apostrophe
  /// inside single quotes, which `CurlGenerator` emits, needs no rewriting: [CurlParser] reads it as the
  /// shell does.)
  static String _normalized(String command) => command.trim().replaceFirst(_curlStart, 'curl');

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

  /// The open quote (`'`, `"`, `$'` or empty) after [line], starting from [quote]
  /// carried over from the previous line. A backslash escapes the next
  /// character outside single quotes (inside `$'...'` too, where `\'` does not
  /// close it); an unquoted ` #` starts a comment.
  static String _quoteStateAfter(String line, String quote) {
    var state = quote;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (state == "'") {
        if (char == "'") state = '';
      } else if (state == r"$'") {
        if (char == r'\') {
          i++;
        } else if (char == "'") {
          state = '';
        }
      } else if (char == r'\') {
        i++;
      } else if (state == '"') {
        if (char == '"') state = '';
      } else if (char == r'$' && i + 1 < line.length && line[i + 1] == "'") {
        state = r"$'";
        i++;
      } else if (char == "'" || char == '"') {
        state = char;
      } else if (char == '#' && (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
        break;
      }
    }
    return state;
  }
}
