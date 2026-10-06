import 'dart:math' as math;
import '../entities/api_docs_model.dart';
import 'markdown_html_renderer.dart';

const _methodClasses = {'get', 'post', 'put', 'patch', 'delete', 'head', 'options'};
final _unsafeLanguage = RegExp(r'[^A-Za-z0-9_+#.\-]');

const _styles = '''
:root{color-scheme:light dark;--bg:#fff;--fg:#1a1d24;--muted:#6b7280;--border:#e1e4ea;--code:#f3f4f6;--accent:#e2571f;--get:#2e7d32;--post:#b35a00;--put:#1565c0;--patch:#6a1b9a;--delete:#c62828}
@media (prefers-color-scheme:dark){:root{--bg:#15171c;--fg:#e7e9ed;--muted:#9aa0ac;--border:#2c2f38;--code:#1d2027;--accent:#ff8a5c;--get:#4caf50;--post:#e0a030;--put:#4fa3f7;--patch:#bb6bd9;--delete:#e0554f}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.layout{display:flex;align-items:flex-start;max-width:1240px;margin:0 auto}
nav{position:sticky;top:0;width:300px;flex:none;max-height:100vh;overflow:auto;padding:24px 16px;border-right:1px solid var(--border);font-size:13px}
nav h2{margin:0 0 8px;font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}
nav ul{list-style:none;margin:0;padding-left:14px}
nav>ul{padding-left:0}
nav a{display:block;padding:2px 0;color:inherit;text-decoration:none}
nav a:hover{color:var(--accent)}
main{flex:1;min-width:0;padding:24px 32px 64px}
h1{margin:0 0 8px;font-size:28px}
h2,h3,h4,h5,h6{margin:28px 0 8px;line-height:1.3}
section.request{margin:16px 0;padding:8px 20px 16px;border:1px solid var(--border);border-radius:8px}
section.request>h2,section.request>h3,section.request>h4,section.request>h5,section.request>h6{margin-top:12px}
.endpoint{display:flex;flex-wrap:wrap;gap:10px;align-items:baseline;margin:8px 0}
.badge{display:inline-block;min-width:56px;padding:0 8px;border-radius:4px;background:var(--muted);color:#fff;font:700 11px/1.7 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;text-align:center}
.badge.get{background:var(--get)}.badge.post{background:var(--post)}.badge.put{background:var(--put)}.badge.patch{background:var(--patch)}.badge.delete{background:var(--delete)}
nav .badge{min-width:0;margin-right:6px;padding:0 5px;font-size:10px}
code,pre{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px}
code{padding:1px 5px;border-radius:4px;background:var(--code);overflow-wrap:anywhere}
pre{margin:8px 0;padding:12px;overflow:auto;border:1px solid var(--border);border-radius:6px;background:var(--code)}
pre code{padding:0;background:none}
table{width:100%;margin:8px 0;border-collapse:collapse}
th,td{padding:6px 10px;border:1px solid var(--border);text-align:left;vertical-align:top}
th{background:var(--code)}
blockquote{margin:8px 0;padding:0 14px;border-left:3px solid var(--border);color:var(--muted)}
.tag{display:inline-block;margin:0 6px 4px 0;padding:0 8px;border:1px solid var(--border);border-radius:999px;color:var(--muted);font-size:12px}
.label{margin:16px 0 4px;color:var(--muted);font-size:12px;font-weight:600;letter-spacing:.05em;text-transform:uppercase}
a{color:var(--accent)}
@media (max-width:800px){.layout{display:block}nav{position:static;width:auto;max-height:none;border-right:0;border-bottom:1px solid var(--border)}main{padding:16px}}
@media print{nav{display:none}section.request{break-inside:avoid}}
''';

/// Writes an [ApiDocsModel] as one self-contained HTML page: inline styles, a
/// table of contents, method badges, and every value escaped.
final class ApiDocsHtmlWriter {
  final _body = StringBuffer();
  var _nextId = 0;

  String write(ApiDocsModel model) {
    final name = MarkdownHtmlRenderer.escape(model.name);
    _body.writeln('<header>');
    _body.writeln('<h1>$name</h1>');
    _meta(tags: model.tags, description: model.description, level: 1);
    if (model.authSummary.isNotEmpty) _label('Authorization', '<p>${_e(model.authSummary)}</p>');
    if (model.variables.isNotEmpty) _label('Variables', _fieldTable(['Variable', 'Value'], model.variables));
    _body.writeln('</header>');
    final toc = _children(model.folders, model.requests, depth: 0);

    return '<!doctype html>\n'
        '<html lang="en">\n'
        '<head>\n'
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        '<title>$name</title>\n'
        '<style>\n$_styles</style>\n'
        '</head>\n'
        '<body>\n'
        '<div class="layout">\n'
        '<nav aria-label="Contents">\n<h2>Contents</h2>\n<ul>\n$toc</ul>\n</nav>\n'
        '<main>\n$_body</main>\n'
        '</div>\n'
        '</body>\n'
        '</html>\n';
  }

  /// Writes the sections into the page body and returns their table-of-contents items.
  String _children(List<ApiDocsFolder> folders, List<ApiDocsRequest> requests, {required int depth}) {
    final level = math.min(6, depth + 2);
    final toc = StringBuffer();
    for (final folder in folders) {
      final id = 'f${++_nextId}';
      _body.writeln('<section class="folder" id="$id">');
      _body.writeln('<h$level>${_e(folder.name)}</h$level>');
      _meta(tags: folder.tags, description: folder.description, level: level);
      final inner = _children(folder.folders, folder.requests, depth: depth + 1);
      _body.writeln('</section>');
      toc.writeln('<li><a href="#$id">${_e(folder.name)}</a>${inner.isEmpty ? '' : '\n<ul>\n$inner</ul>\n'}</li>');
    }
    for (final request in requests) {
      toc.writeln(_request(request, level));
    }
    return toc.toString();
  }

  String _request(ApiDocsRequest request, int level) {
    final id = 'r${++_nextId}';
    final badge = _badge(request.method);
    _body.writeln('<section class="request" id="$id">');
    _body.writeln('<h$level>${_e(request.name)}</h$level>');
    _body.writeln('<div class="endpoint">$badge${request.url.isEmpty ? '' : '<code>${_e(request.url)}</code>'}</div>');
    _meta(tags: request.tags, description: request.description, level: level);
    if (request.queryParams.isNotEmpty) {
      _label('Query parameters', _fieldTable(['Key', 'Value'], request.queryParams));
    }
    if (request.headers.isNotEmpty) _label('Headers', _fieldTable(['Key', 'Value'], request.headers));
    _requestBody(request.body);
    if (request.authSummary.isNotEmpty) _label('Authorization', '<p>${_e(request.authSummary)}</p>');
    for (final example in request.examples) {
      _label(
        'Example: ${example.name} (${example.statusCode})',
        example.body.trim().isEmpty ? '' : _pre(example.body, _guessLanguage(example.body)),
      );
    }
    _body.writeln('</section>');
    return '<li><a href="#$id">$badge${_e(request.name)}</a></li>';
  }

  void _requestBody(ApiDocsBody? body) {
    if (body == null) return;
    final parts = StringBuffer();
    if (body.fields.isNotEmpty) parts.write(_fieldTable(['Key', 'Value'], body.fields));
    if (body.text.trim().isNotEmpty) parts.write(_pre(body.text, body.language));
    if (body.variablesText.trim().isNotEmpty) {
      parts
        ..write('<div class="label">Variables</div>')
        ..write(_pre(body.variablesText, 'json'));
    }
    _label('Body (${body.typeLabel})', parts.toString());
  }

  void _meta({required List<String> tags, required String description, required int level}) {
    if (tags.isNotEmpty) {
      _body.writeln('<div class="tags">${[for (final tag in tags) '<span class="tag">${_e(tag)}</span>'].join()}</div>');
    }
    final html = MarkdownHtmlRenderer.render(description, shiftHeadings: level);
    if (html.isNotEmpty) _body.writeln('<div class="description">\n$html</div>');
  }

  void _label(String label, String content) {
    _body.writeln('<div class="label">${_e(label)}</div>');
    if (content.isNotEmpty) _body.writeln(content);
  }

  String _badge(String method) {
    final kind = method.toLowerCase();
    return '<span class="badge${_methodClasses.contains(kind) ? ' $kind' : ''}">${_e(method)}</span>';
  }

  /// A third column says where an inherited row (a header a folder or the collection passes down) was set.
  String _fieldTable(List<String> header, List<ApiDocsField> rows) {
    final withOrigin = rows.any((r) => r.origin.isNotEmpty);
    final out = StringBuffer('<table>\n<thead><tr>');
    for (final title in [...header, if (withOrigin) 'Inherited from']) {
      out.write('<th>${_e(title)}</th>');
    }
    out.write('</tr></thead>\n<tbody>\n');
    for (final row in rows) {
      out.writeln(
        '<tr><td>${_cell(row.key)}</td><td>${_cell(row.value)}</td>${withOrigin ? '<td>${_e(row.origin)}</td>' : ''}</tr>',
      );
    }
    out.write('</tbody>\n</table>');
    return out.toString();
  }

  String _cell(String value) => value.isEmpty ? '' : '<code>${_e(value)}</code>';

  String _pre(String code, String language) {
    final safe = language.replaceAll(_unsafeLanguage, '');
    return '<pre><code${safe.isEmpty ? '' : ' class="language-$safe"'}>${_e(code.trimRight())}</code></pre>';
  }

  static String _guessLanguage(String body) {
    final start = body.trimLeft();
    return start.startsWith('{') || start.startsWith('[') ? 'json' : '';
  }

  static String _e(String text) => MarkdownHtmlRenderer.escape(text);
}
