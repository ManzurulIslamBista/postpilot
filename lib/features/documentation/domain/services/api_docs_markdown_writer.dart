import 'dart:math' as math;
import '../entities/api_docs_model.dart';
import 'markdown_embedder.dart';

final _markdownSpecials = RegExp(r'[\\`*_\[\]<>&|]');
final _unsafeLanguage = RegExp(r'[^A-Za-z0-9_+#.\-]');

/// Writes an [ApiDocsModel] as one Markdown document. Values sit in code
/// spans and cells so their `*`, `_` or `|` cannot turn into formatting.
final class ApiDocsMarkdownWriter {
  final _out = StringBuffer();

  String write(ApiDocsModel model) {
    _out
      ..writeln('# ${_plain(model.name)}')
      ..writeln();
    _meta(tags: model.tags, description: model.description, level: 1);
    _labelled('Authorization', model.authSummary);
    if (model.variables.isNotEmpty) {
      _out
        ..writeln('## Variables')
        ..writeln();
      _table(['Variable', 'Value'], model.variables);
    }
    _children(model.folders, model.requests, depth: 0);
    return '${_out.toString().trimRight()}\n';
  }

  void _children(List<ApiDocsFolder> folders, List<ApiDocsRequest> requests, {required int depth}) {
    final level = math.min(6, depth + 2);
    for (final folder in folders) {
      _heading(level, folder.name);
      _meta(tags: folder.tags, description: folder.description, level: level);
      _children(folder.folders, folder.requests, depth: depth + 1);
    }
    for (final request in requests) {
      _request(request, level);
    }
  }

  void _request(ApiDocsRequest request, int level) {
    _heading(level, request.name);
    _out
      ..writeln(request.url.isEmpty
          ? '**${_plain(request.method)}**'
          : '**${_plain(request.method)}** ${_code(request.url)}')
      ..writeln();
    _meta(tags: request.tags, description: request.description, level: level);
    _fields('Query parameters', request.queryParams);
    _fields('Headers', request.headers);
    _body(request.body);
    _labelled('Authorization', request.authSummary);
    for (final example in request.examples) {
      _out
        ..writeln('**Example: ${_plain(example.name)} (${example.statusCode})**')
        ..writeln();
      if (example.body.trim().isNotEmpty) _fence(example.body, _guessLanguage(example.body));
    }
  }

  void _body(ApiDocsBody? body) {
    if (body == null) return;
    _out
      ..writeln('**Body** (${_plain(body.typeLabel)})')
      ..writeln();
    if (body.fields.isNotEmpty) _table(['Key', 'Value'], body.fields);
    if (body.text.trim().isNotEmpty) _fence(body.text, body.language);
    if (body.variablesText.trim().isNotEmpty) {
      _out
        ..writeln('**Variables**')
        ..writeln();
      _fence(body.variablesText, 'json');
    }
  }

  void _heading(int level, String text) => _out
    ..writeln('${'#' * level} ${_plain(text)}')
    ..writeln();

  void _meta({required List<String> tags, required String description, required int level}) {
    if (tags.isNotEmpty) {
      _out
        ..writeln('**Tags:** ${tags.map(_code).join(', ')}')
        ..writeln();
    }
    final text = MarkdownEmbedder.prepare(description, shiftHeadings: level);
    if (text.isNotEmpty) {
      _out
        ..writeln(text)
        ..writeln();
    }
  }

  void _labelled(String label, String value) {
    if (value.isEmpty) return;
    _out
      ..writeln('**$label:** ${_plain(value)}')
      ..writeln();
  }

  void _fields(String label, List<ApiDocsField> fields) {
    if (fields.isEmpty) return;
    _out
      ..writeln('**$label**')
      ..writeln();
    _table(['Key', 'Value'], fields);
  }

  void _table(List<String> header, List<ApiDocsField> rows) {
    _out
      ..writeln('| ${header.join(' | ')} |')
      ..writeln('| ${header.map((_) => '---').join(' | ')} |');
    for (final row in rows) {
      _out.writeln('| ${_cell(row.key)} | ${_cell(row.value)} |');
    }
    _out.writeln();
  }

  void _fence(String code, String language) {
    var longest = 0;
    var run = 0;
    for (final unit in code.codeUnits) {
      run = unit == 0x60 ? run + 1 : 0;
      longest = math.max(longest, run);
    }
    final fence = '`' * math.max(3, longest + 1);
    var end = code.length;
    while (end > 0 && (code[end - 1] == '\n' || code[end - 1] == '\r')) {
      end--;
    }
    _out
      ..writeln('$fence${language.replaceAll(_unsafeLanguage, '')}')
      ..writeln(code.substring(0, end))
      ..writeln(fence)
      ..writeln();
  }

  static String _guessLanguage(String body) {
    final start = body.trimLeft();
    return start.startsWith('{') || start.startsWith('[') ? 'json' : '';
  }

  static String _plain(String text) => text
      .replaceAll('\r\n', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .replaceAllMapped(_markdownSpecials, (m) => '\\${m[0]}');

  static String _cell(String value) => value.isEmpty ? '' : _code(value).replaceAll('|', r'\|');

  /// An inline code span whose delimiter is longer than any backtick run inside.
  static String _code(String value) {
    final text = value.replaceAll('\r', '').replaceAll('\n', ' ');
    if (text.isEmpty) return '';
    var longest = 0;
    var run = 0;
    for (final unit in text.codeUnits) {
      run = unit == 0x60 ? run + 1 : 0;
      longest = math.max(longest, run);
    }
    final delimiter = '`' * (longest + 1);
    final pad = text.startsWith('`') || text.endsWith('`') || (text.startsWith(' ') && text.endsWith(' ') && text.trim().isNotEmpty);
    return pad ? '$delimiter $text $delimiter' : '$delimiter$text$delimiter';
  }
}
