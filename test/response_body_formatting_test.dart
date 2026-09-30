import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/safe_file_name.dart';
import 'package:postpilot/features/request_builder/domain/services/response_body/body_decoder.dart';
import 'package:postpilot/features/request_builder/domain/services/response_body/download_file_name.dart';
import 'package:postpilot/features/request_builder/domain/services/response_body/html_preview.dart';
import 'package:postpilot/features/request_builder/domain/services/response_body/pretty_printer.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/response_body_formatter.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);
Uint8List utf(String text) => Uint8List.fromList(utf8.encode(text));

final replacement = String.fromCharCode(0xFFFD);
final pngHeader = bytes([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);

String? decode(List<int> body, String mimeType, [String? charset]) =>
    decodeResponseBody(bytes(body), mimeType: mimeType, charset: charset);

ResponseBodyFormatter formatter(Map<String, String> headers, Uint8List body) => ResponseBodyFormatter(headers, body);

void main() {
  group('safe file names', () {
    test('sanitizeFileName removes path separators, edge dots and bidi controls', () {
      expect(sanitizeFileName('../../AppData/x.bat'), '_.._AppData_x.bat');
      expect(sanitizeFileName('a.exe. .'), 'a.exe');
      expect(sanitizeFileName('...'), isNull);
      expect(sanitizeFileName('a${String.fromCharCode(0x202E)}fdp.exe'), 'a_fdp.exe');
      expect(sanitizeFileName('a' * 400)!.length, 150);
      expect(sanitizeFileName('a${'.' * 1000000}b'), 'a');
    });

    test('sanitizeFileName defuses reserved Windows device names', () {
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
      expect(sanitizeFileName('lpt1'), '_lpt1');
    });

    test('isSafeFileName accepts one plain name and rejects everything that could escape or execute', () {
      expect(isSafeFileName('report.json'), isTrue);
      expect(isSafeFileName('a.exe.json'), isTrue);
      expect(isSafeFileName('a/b.json'), isFalse);
      expect(isSafeFileName('a\\b.json'), isFalse);
      expect(isSafeFileName('response.../../AppData/x.bat'), isFalse);
      expect(isSafeFileName('..'), isFalse);
      expect(isSafeFileName('a.exe.'), isFalse);
      expect(isSafeFileName('a.EXE'), isFalse);
      expect(isSafeFileName('a.txt:evil.exe'), isFalse);
    });
  });

  group('decodeResponseBody', () {
    test('decodes UTF-8 and drops a byte-order mark', () {
      expect(decode(utf8.encode('{"a":"é"}'), 'application/json'), '{"a":"é"}');
      expect(decode([0xEF, 0xBB, 0xBF, 0x41], 'text/plain'), 'A');
    });

    test('honours the declared charset', () {
      expect(decode([0x4A, 0x6F, 0x73, 0xE9], 'application/xml', 'ISO-8859-1'), 'José');
      expect(decode([0x93, 0x41, 0x94], 'text/plain', 'windows-1252'), String.fromCharCodes([0x201C, 0x41, 0x201D]));
    });

    test('honours an encoding the document declares about itself', () {
      final xml = latin1.encode('<?xml version="1.0" encoding="ISO-8859-1"?><a>Jos${String.fromCharCode(0xE9)}</a>');
      expect(decode(xml, 'application/xml'), endsWith('<a>José</a>'));
      final html = latin1.encode('<meta charset="iso-8859-1">Jos${String.fromCharCode(0xE9)}');
      expect(decode(html, 'text/html'), endsWith('José'));
    });

    test('decodes UTF-16 with a BOM or a declared charset and repairs lone surrogates', () {
      expect(decode([0xFF, 0xFE, 0x41, 0x00, 0x42, 0x00], 'text/plain'), 'AB');
      expect(decode([0xFE, 0xFF, 0x00, 0x41, 0x00, 0x42], 'text/plain'), 'AB');
      expect(decode([0x41, 0x00, 0x42, 0x00], 'text/plain', 'utf-16'), 'AB');
      expect(decode([0xFE, 0xFF, 0xD8, 0x3D, 0xDE, 0x00], 'text/plain'), String.fromCharCodes([0xD83D, 0xDE00]));
      expect(decode([0xFE, 0xFF, 0xD8, 0x3D, 0x00, 0x41], 'text/plain'), '${replacement}A');
    });

    test('keeps text with a stray invalid byte readable instead of calling it binary', () {
      expect(decode([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xE9, 0x22, 0x7D], 'application/json'), '{"a":"$replacement"}');
      expect(decode([0x41, 0xFF, 0x42], 'text/plain', 'utf-8'), 'A${replacement}B');
      expect(decode([0x4A, 0xE9], 'text/plain'), 'Jé');
    });

    test('reports binary content as null', () {
      expect(decode([0x89, 0x50, 0x4E, 0x47], 'application/octet-stream'), isNull);
      expect(decode([0xFF, 0xD8, 0xFF], ''), isNull);
      expect(decode([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00], 'image/png'), isNull);
      expect(decode([0, 0, 0, 1], 'application/octet-stream'), isNull);
    });

    test('charsetOfContentType reads the charset parameter', () {
      expect(charsetOfContentType('text/html; charset="UTF-8"; x=y'), 'UTF-8');
      expect(charsetOfContentType('text/html;Charset=windows-1251'), 'windows-1251');
      expect(charsetOfContentType('text/html'), isNull);
    });
  });

  group('prettyPrintJson', () {
    test('indents objects and arrays and keeps empty containers compact', () {
      expect(
        prettyPrintJson('{"a":1,"b":[1,2],"c":{},"d":[]}'),
        '{\n  "a": 1,\n  "b": [\n    1,\n    2\n  ],\n  "c": {},\n  "d": []\n}',
      );
    });

    test('matches JsonEncoder for ordinary documents', () {
      final doc = {
        'a': [1, 2, {'b': 'x y', 'c': null, 'd': true}],
        'e': {},
        'f': [],
      };
      expect(prettyPrintJson(jsonEncode(doc)), const JsonEncoder.withIndent('  ').convert(doc));
    });

    test('keeps numbers, escapes and duplicate keys exactly as sent', () {
      expect(
        prettyPrintJson('{"price":10.50,"n":1E2,"id":12345678901234567890}'),
        '{\n  "price": 10.50,\n  "n": 1E2,\n  "id": 12345678901234567890\n}',
      );
      expect(prettyPrintJson('{"a":1,"a":2}'), '{\n  "a": 1,\n  "a": 2\n}');
      expect(prettyPrintJson('[1e999]'), '[\n  1e999\n]');
      expect(prettyPrintJson(r'{"k":"a,b:{c}[d]\"e\\","x":"\u00e9"}'), '{\n  "k": "a,b:{c}[d]\\"e\\\\",\n  "x": "\\u00e9"\n}');
    });

    test('leaves anything that is not a valid object or array alone', () {
      expect(prettyPrintJson('[INFO] hi'), '[INFO] hi');
      expect(prettyPrintJson('{"a":1}\n{"b":2}'), '{"a":1}\n{"b":2}');
      expect(prettyPrintJson('"x"'), '"x"');
      expect(prettyPrintJson('{"a":'), '{"a":');
    });

    test('stops growing the indentation for absurdly deep nesting', () {
      final deep = '[' * 5000 + ']' * 5000;
      expect(prettyPrintJson(deep).length, lessThan(5000 * 300));
    });
  });

  group('prettyPrintMarkup', () {
    test('puts each XML tag on its own line and keeps text-only elements on one', () {
      expect(
        prettyPrintMarkup('<?xml version="1.0"?><root><a>1</a><b><c/></b><d></d></root>', html: false),
        '<?xml version="1.0"?>\n<root>\n  <a>1</a>\n  <b>\n    <c/>\n  </b>\n  <d></d>\n</root>',
      );
      expect(
        prettyPrintMarkup('<r><!-- c --><a><![CDATA[x<y]]></a></r>', html: false),
        '<r>\n  <!-- c -->\n  <a>\n    <![CDATA[x<y]]>\n  </a>\n</r>',
      );
    });

    test('handles HTML void elements and leaves script, style and pre verbatim', () {
      expect(
        prettyPrintMarkup('<html><head><meta charset="utf-8"></head><body><br><p>x</p></body></html>', html: true),
        '<html>\n  <head>\n    <meta charset="utf-8">\n  </head>\n  <body>\n    <br>\n    <p>x</p>\n  </body>\n</html>',
      );
      expect(
        prettyPrintMarkup('<body><script>if (a<b) {x()}</script></body>', html: true),
        '<body>\n  <script>if (a<b) {x()}</script>\n</body>',
      );
      expect(prettyPrintMarkup('<div><pre>  a\n   b </pre></div>', html: true), '<div>\n  <pre>  a\n   b </pre>\n</div>');
    });

    test('returns text without markup unchanged and bounds runaway nesting', () {
      expect(prettyPrintMarkup('just text', html: false), 'just text');
      expect(prettyPrintMarkup('<a>' * 20000, html: true).length, lessThan(20000 * 140));
    });

    test('stays linear on bodies built to defeat backtracking', () {
      final watch = Stopwatch()..start();
      final hostile = ['<!--' * 100000, '<![CDATA[' * 50000, '<a ' * 100000, '<script>' * 50000, '<pre>' * 50000, '${' ' * 500000}x'];
      for (final body in hostile) {
        prettyPrintMarkup(body, html: true);
        htmlToPlainText(body);
      }
      expect(watch.elapsedMilliseconds, lessThan(10000));
    });
  });

  group('htmlToPlainText', () {
    test('drops markup, scripts, styles and comments and breaks lines at blocks', () {
      expect(htmlToPlainText('<style>a{}</style><script>x()</script><h1>Title</h1><p>Body</p><!-- c -->'), 'Title\nBody');
    });

    test('decodes named, decimal and hexadecimal entities in one pass', () {
      expect(
        htmlToPlainText('<p>&copy; 2024 &mdash; a&nbsp;b &amp;lt; &#39;x&#x27; &apos;</p>'),
        "${String.fromCharCode(0xA9)} 2024 ${String.fromCharCode(0x2014)} a b &lt; 'x' '",
      );
      expect(htmlToPlainText('<p>&lt;b&gt;bold&lt;/b&gt;</p>'), '<b>bold</b>');
    });

    test('survives out-of-range, surrogate and oversized numeric entities', () {
      expect(
        htmlToPlainText('a &#1114112; b &#xD800; c &#99999999999999999999; d'),
        'a $replacement b $replacement c &#99999999999999999999; d',
      );
    });
  });

  group('download file names', () {
    test('the extension table covers common types and omits scripts', () {
      expect(extensionForMimeType('application/pdf'), 'pdf');
      expect(extensionForMimeType('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'), 'xlsx');
      expect(extensionForMimeType('application/javascript'), isNull);
    });

    test('Content-Disposition names are honoured but made safe', () {
      String? name(String header, [String fallback = 'bin']) =>
          fileNameFromContentDisposition(header, fallbackExtension: fallback);
      expect(name('attachment; filename=q3.pdf'), 'q3.pdf');
      expect(name('attachment; filename="Q3 report.pdf"'), 'Q3 report.pdf');
      expect(name("attachment; filename*=UTF-8''na%C3%AFve%20file.txt"), 'naïve file.txt');
      expect(name("attachment; filename=\"a.txt\"; filename*=UTF-8''b.txt"), 'b.txt');
      expect(name('attachment; filename="../../AppData/Startup/x.bat"', 'txt'), 'x.txt');
      expect(name('attachment; filename="..\\..\\x.exe"'), 'x.bin');
      expect(name('attachment; filename=report', 'pdf'), 'report.pdf');
      expect(name('attachment; filename=a.abcdefghijk'), 'a.abcdefghijk.bin');
      expect(name('attachment; filename=app.js', 'txt'), 'app.txt');
      expect(name('attachment; filename=NUL.txt'), '_NUL.txt');
      expect(name("attachment; filename*=UTF-8''%E0%A4%A; filename=ok.txt"), 'ok.txt');
      expect(name('inline'), isNull);
      expect(name('attachment; filename=""'), isNull);
      expect(name('attachment; xfilename=a.pdf'), isNull);
      expect(fileNameFromContentDisposition(null, fallbackExtension: 'bin'), isNull);
    });
  });

  group('ResponseBodyFormatter', () {
    test('a hostile Content-Type can never choose the saved file name or extension', () {
      for (final hostile in [
        'image/../../../AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/x.bat',
        'image/bat',
        'image/exe',
        'image/../x',
        'image/x.js',
      ]) {
        final response = formatter({'Content-Type': hostile}, pngHeader);
        expect(response.fileExtension, 'bin', reason: hostile);
        expect(response.downloadFileName(requestName: 'Get users'), 'Get users.bin', reason: hostile);
      }
    });

    test('a hostile request name or Content-Disposition cannot escape either', () {
      final json = formatter({'content-type': 'application/json'}, utf('{}'));
      expect(isSafeFileName(json.downloadFileName(requestName: '../../evil')), isTrue);
      expect(json.downloadFileName(requestName: 'con'), '_con.json');
      expect(json.downloadFileName(), 'response.json');
      final disposition = formatter({
        'content-type': 'application/json',
        'content-disposition': 'attachment; filename="../../AppData/x.bat"',
      }, utf('{}'));
      expect(disposition.downloadFileName(), 'x.json');
    });

    test('picks the extension from a table, falling back to the detected kind', () {
      String ext(String contentType, [Uint8List? body]) =>
          formatter({'content-type': contentType}, body ?? utf('x')).fileExtension;
      expect(ext('image/png', pngHeader), 'png');
      expect(ext('image/jpeg', pngHeader), 'jpg');
      expect(ext('image/svg+xml', utf('<svg/>')), 'svg');
      expect(ext('application/pdf', pngHeader), 'pdf');
      expect(ext('application/zip', pngHeader), 'zip');
      expect(ext('text/css'), 'css');
      expect(ext('text/markdown'), 'md');
      expect(ext('application/yaml'), 'yaml');
      expect(ext('text/csv'), 'csv');
      expect(ext('application/vnd.api+json', utf('{}')), 'json');
      expect(ext('text/plain', utf('{"a":1}')), 'json');
      expect(ext('application/octet-stream', pngHeader), 'bin');
      expect(ext('application/javascript'), 'txt');
      expect(formatter({}, pngHeader).fileExtension, 'bin');
    });

    test('decodes by charset and only calls truly binary bodies binary', () {
      final latin1Xml = bytes([0x3C, 0x61, 0x3E, 0x4A, 0x6F, 0x73, 0xE9, 0x3C, 0x2F, 0x61, 0x3E]);
      expect(formatter({'content-type': 'application/xml; charset=ISO-8859-1'}, latin1Xml).text, '<a>José</a>');
      final strayByte = bytes([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xE9, 0x22, 0x7D]);
      final json = formatter({'content-type': 'application/json'}, strayByte);
      expect(json.kind, ResponseContentKind.json);
      expect(json.isTextual, isTrue);
      final binary = formatter({'content-type': 'application/octet-stream'}, pngHeader);
      expect(binary.raw, '<8 bytes of binary data>');
      expect(binary.isTextual, isFalse);
      expect(formatter({'content-type': 'image/png'}, pngHeader).isTextual, isFalse);
    });

    test('Pretty indents JSON, XML and HTML and never throws on hostile bodies', () {
      String pretty(String contentType, String body) => formatter({'content-type': contentType}, utf(body)).pretty;
      expect(pretty('application/json', '{"a":1e999}'), '{\n  "a": 1e999\n}');
      expect(pretty('application/json', '{"a":'), '{"a":');
      expect(pretty('application/xml', '<a><b>1</b></a>'), '<a>\n  <b>1</b>\n</a>');
      expect(pretty('text/html', '<html><body><p>x</p></body></html>'), '<html>\n  <body>\n    <p>x</p>\n  </body>\n</html>');
      expect(pretty('text/html', '{"a":1}'), '{\n  "a": 1\n}');
      expect(pretty('text/plain', 'hello'), 'hello');
      final preview = formatter({'content-type': 'text/html'}, utf('<p>&#1114112;&copy; x</p>')).preview;
      expect(preview, '$replacement${String.fromCharCode(0xA9)} x');
    });

    test('fromText does not apply the header charset to already-decoded text', () {
      final example = ResponseBodyFormatter.fromText({'Content-Type': 'text/plain; charset=ISO-8859-1'}, 'José');
      expect(example.text, 'José');
      expect(utf8.decode(example.bytes), 'José');
    });

    test('only lays out the head of a huge body, at a line boundary, and keeps the full text', () {
      final body = 'line of text\n' * 100000;
      final huge = formatter({'content-type': 'text/plain'}, utf(body));
      final shown = huge.displayTextFor(ResponseBodyMode.raw);
      expect(huge.isTruncated(ResponseBodyMode.raw), isTrue);
      expect(shown.length, lessThanOrEqualTo(maxDisplayedBodyChars));
      expect(shown, endsWith('text'));
      expect(identical(shown, huge.displayTextFor(ResponseBodyMode.raw)), isTrue);
      expect(huge.textFor(ResponseBodyMode.raw).length, body.length);

      final small = formatter({'content-type': 'text/plain'}, utf('abc'));
      expect(small.isTruncated(ResponseBodyMode.raw), isFalse);
      expect(identical(small.displayTextFor(ResponseBodyMode.raw), small.textFor(ResponseBodyMode.raw)), isTrue);
    });

    test('never cuts a surrogate pair in half', () {
      final emoji = String.fromCharCodes([0xD83D, 0xDE00]) * 300000;
      final shown = formatter({'content-type': 'text/plain'}, utf(emoji)).displayTextFor(ResponseBodyMode.raw);
      final last = shown.codeUnitAt(shown.length - 1);
      expect(last >= 0xD800 && last <= 0xDBFF, isFalse);
    });
  });

  group('findMatches', () {
    test('finds non-overlapping case-insensitive matches', () {
      expect(findMatches('aXbxc', 'x'), [1, 3]);
      expect(findMatches('aaaa', 'aa'), [0, 2]);
      expect(findMatches('Hello HELLO', 'hello'), [0, 6]);
      expect(findMatches('abc', ''), isEmpty);
    });

    test('stops at the highlight limit', () {
      expect(findMatches('e' * 5000, 'e'), hasLength(maxSearchHighlights));
      expect(findMatches('e' * 50, 'e', limit: 7), hasLength(7));
    });
  });
}
