import 'dart:convert';
import '../../../../../core/enums/auth_type.dart';
import '../../../../../core/enums/body_type.dart';
import '../../../../../core/enums/http_method.dart';
import '../../../../../core/network/upload_body.dart';
import '../../entities/key_value_item.dart';
import '../../entities/request_auth.dart';
import '../../entities/request_body.dart';
import 'upload_path_note.dart';

final class ParsedCurlRequest {
  final HttpMethod method;
  final String url;

  /// Includes the `Content-Type` curl would send for a body the command did not
  /// type itself (`application/x-www-form-urlencoded`, which is curl's default
  /// for `-d`), so a request built from this is sent the way the command was.
  final List<KeyValueItem> headers;

  /// The raw data of `-d` / `--data*` / `--json`, several pieces joined with `&`
  /// as curl does; null when there is none (or when `-F` fields carry the body).
  final String? body;
  final RequestAuth auth;

  /// The fields of `-F` / `--form`; they make the body multipart form data. A `name=@file` field is a file row.
  final List<KeyValueItem> formFields;

  /// The file of `--data-binary @file` or `-T file`: the whole body, sent as it is. A file row without a key.
  final KeyValueItem? binaryFile;

  /// What the command asks for that PostPilot cannot do (a body read from a
  /// file, ...), and what it brought in that needs a look (a file path of this machine), one sentence each.
  /// Never dropped silently.
  final List<String> notes;

  const ParsedCurlRequest({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
    required this.auth,
    this.formFields = const [],
    this.binaryFile,
    this.notes = const [],
  });

  /// The body as a request body: form data for `-F`, a binary body for `--data-binary @file`, otherwise the raw
  /// text typed by its `Content-Type` (JSON-looking text is JSON when none is declared). [RequestBody.empty] when
  /// the command sends nothing.
  RequestBody get requestBody {
    if (formFields.isNotEmpty) return RequestBody(type: BodyType.formData, formFields: formFields);
    final file = binaryFile;
    if (file != null) return const RequestBody(type: BodyType.binary).withBinaryFile(file);
    final text = body;
    if (text == null) return RequestBody.empty;
    return RequestBody(type: BodyType.raw, rawContentType: _rawTypeOf(headers, text), rawText: text);
  }

  static RawContentType _rawTypeOf(List<KeyValueItem> headers, String text) {
    for (final header in headers) {
      if (header.key.toLowerCase() != 'content-type') continue;
      final essence = header.value.split(';').first.trim().toLowerCase();
      return switch (essence) {
        final t when t.contains('json') => RawContentType.json,
        final t when t.contains('xml') => RawContentType.xml,
        final t when t.contains('html') => RawContentType.html,
        final t when t.contains('javascript') => RawContentType.javascript,
        _ => RawContentType.text,
      };
    }
    return CurlParser.looksJson(text) ? RawContentType.json : RawContentType.text;
  }
}

/// Parses a `curl ...` command line into a request. Covers the flags people
/// actually paste from browser dev tools / API docs: -X, -H, -d/--data*/--json
/// (several pieces are joined with `&`, `-G` moves them into the query),
/// -F (form data; `name=@file` is a file field), `--data-binary @file` and -T
/// (the file as the binary body), -u (basic or `--digest` auth), -b/-A/-e/-r (Cookie,
/// User-Agent, Referer, Range headers), -I (HEAD). Every other flag is
/// accepted and skipped *together with its value* (`-o /dev/null`, `-m 30`,
/// `--retry 3`, `-w '%{http_code}'` ...), so what follows it is never mistaken
/// for the URL, and a user pasting a real cURL command doesn't get an import
/// failure over a flag we don't model yet. What the command needs that
/// PostPilot cannot do is listed in [ParsedCurlRequest.notes].
///
/// Returns null when there is no URL, or when the command is cut off in the
/// middle of an option (curl itself rejects `curl https://x -H`).
abstract final class CurlParser {
  static ParsedCurlRequest? parse(String command) {
    final tokens = _tokenize(command.trim());
    if (tokens.isEmpty) return null;
    final state = _State();
    var i = _afterCurl(tokens);

    String? next() {
      if (i + 1 >= tokens.length) {
        state.malformed = true;
        return null;
      }
      return tokens[++i];
    }

    // Hands an option to the state with its value, which is [attached] or the next token. A value option
    // at the end of the command (`curl https://x -H`) marks it malformed instead of applying a null.
    void apply(String option, [String? attached]) {
      if (!_valueOptions.contains(option)) {
        state.apply(option, null);
        return;
      }
      final value = attached ?? next();
      if (!state.malformed) state.apply(option, value);
    }

    while (i < tokens.length && !state.malformed) {
      final token = tokens[i];
      if (token == '--') {
        state.positional.addAll(tokens.skip(i + 1));
        break;
      }
      if (token.startsWith('--')) {
        apply(token.substring(2));
      } else if (token.length > 1 && token.startsWith('-')) {
        // Bundled short flags: `-sSL`, `-XPOST`, `-H'A: b'`. The first flag that takes a value ends the bundle.
        for (var j = 1; j < token.length && !state.malformed; j++) {
          final option = _shortFlags[token[j]] ?? token[j];
          if (!_valueOptions.contains(option)) {
            state.apply(option, null);
            continue;
          }
          final attached = token.substring(j + 1);
          apply(option, attached.isEmpty ? null : attached);
          break;
        }
      } else {
        state.positional.add(token);
      }
      i++;
    }
    return state.malformed ? null : state.build();
  }

  /// Whether [text] starts like a JSON document.
  static bool looksJson(String text) {
    final head = text.trimLeft();
    return head.startsWith('{') || head.startsWith('[');
  }

  /// The index after the `curl` word, which may follow a prompt-ish `sudo` or `time`.
  static int _afterCurl(List<String> tokens) {
    for (var i = 0; i < tokens.length && i < 3; i++) {
      final word = tokens[i].toLowerCase();
      if (word == 'curl' || word == 'curl.exe') return i + 1;
    }
    return 0;
  }

  /// Short flag letters and the long option they stand for.
  static const _shortFlags = {
    'X': 'request',
    'H': 'header',
    'd': 'data',
    'u': 'user',
    'b': 'cookie',
    'A': 'user-agent',
    'e': 'referer',
    'F': 'form',
    'I': 'head',
    'G': 'get',
    'T': 'upload-file',
    'r': 'range',
    'L': 'location',
    's': 'silent',
    'k': 'insecure',
    'i': 'include',
    'o': 'output',
    'm': 'max-time',
    'w': 'write-out',
    'x': 'proxy',
    'K': 'config',
    'E': 'cert',
    'c': 'cookie-jar',
    'D': 'dump-header',
    'y': 'speed-time',
    'Y': 'speed-limit',
    'z': 'time-cond',
    'U': 'proxy-user',
    'C': 'continue-at',
    'Q': 'quote',
    't': 'telnet-option',
    'P': 'ftp-port',
  };

  /// Options whose next token is their value. The first group are the ones this parser models; the rest
  /// are skipped (value included) because they do not change what the request is.
  static const _valueOptions = {
    'request', 'header', 'data', 'data-ascii', 'data-raw', 'data-binary', 'data-urlencode', 'json', 'form', 'form-string',
    'user', 'cookie', 'user-agent', 'referer', 'upload-file', 'range', 'url', 'oauth2-bearer',
    // Not modelled:
    'output', 'max-time', 'connect-timeout', 'write-out', 'retry', 'retry-delay', 'retry-max-time', 'proxy', 'proxy-user',
    'noproxy', 'cacert', 'capath', 'cert', 'key', 'pass', 'cert-type', 'key-type', 'config', 'cookie-jar', 'dump-header',
    'resolve', 'connect-to', 'interface', 'limit-rate', 'max-redirs', 'keepalive-time', 'speed-limit', 'speed-time',
    'local-port', 'dns-servers', 'doh-url', 'proto', 'proto-redir', 'ciphers', 'expect100-timeout', 'trace', 'trace-ascii',
    'stderr', 'time-cond', 'continue-at', 'quote', 'proxy-header', 'proxy-cert', 'proxy-key', 'unix-socket',
    'happy-eyeballs-timeout-ms', 'alt-svc', 'hsts', 'netrc-file', 'parallel-max', 'url-query', 'variable', 'etag-save',
    'etag-compare', 'request-target', 'telnet-option', 'ftp-port', 'tls-max', 'sslv3', 'service-name', 'proxy-service-name',
    'abstract-unix-socket', 'aws-sigv4', 'form-escape', 'mail-from', 'mail-rcpt',
  };

  /// Percent-encodes [text] the way `--data-urlencode` does: everything but the RFC 3986 unreserved characters.
  static String _percentEncode(String text) {
    final out = StringBuffer();
    for (final byte in utf8.encode(text)) {
      final isUnreserved =
          (byte >= 0x30 && byte <= 0x39) ||
          (byte >= 0x41 && byte <= 0x5A) ||
          (byte >= 0x61 && byte <= 0x7A) ||
          byte == 0x2D ||
          byte == 0x2E ||
          byte == 0x5F ||
          byte == 0x7E;
      if (isUnreserved) {
        out.writeCharCode(byte);
      } else {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  /// Splits on whitespace the way a POSIX shell does for the parts a pasted command uses: single quotes,
  /// double quotes (`\"` `\\` `\$` escape), ANSI-C quotes `$'...'` (what browsers emit for bodies with
  /// escapes), a backslash outside quotes, `\`-line continuations and `#` comments. An empty quoted
  /// argument (`-d ''`) stays a token. The command ends at an unquoted `|` or `;`.
  static List<String> _tokenize(String input) {
    final text = input.replaceAll(RegExp(r'\\\r?\n'), ' ');
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inToken = false;
    String? quote; // ' or "

    void flush() {
      if (inToken) tokens.add(buffer.toString());
      buffer.clear();
      inToken = false;
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      switch (quote) {
        case "'":
          if (char == "'") {
            quote = null;
          } else {
            buffer.write(char);
          }
          continue;
        case '"':
          if (char == '"') {
            quote = null;
          } else if (char == r'\' && i + 1 < text.length && r'\"$`'.contains(text[i + 1])) {
            buffer.write(text[++i]);
          } else {
            buffer.write(char);
          }
          continue;
      }

      if (char == "'") {
        quote = "'";
        inToken = true;
      } else if (char == '"') {
        quote = '"';
        inToken = true;
      } else if (char == r'$' && i + 1 < text.length && text[i + 1] == "'") {
        // ANSI-C quoting: read up to the closing quote (a backslash protects the next character) and decode it whole.
        var end = i + 2;
        while (end < text.length && text[end] != "'") {
          end += text[end] == r'\' ? 2 : 1;
        }
        buffer.write(_decodeAnsiC(text.substring(i + 2, end > text.length ? text.length : end)));
        inToken = true;
        i = end;
      } else if (char == r'$' && i + 1 < text.length && text[i + 1] == '"') {
        quote = '"';
        inToken = true;
        i++;
      } else if (char == r'\' && i + 1 < text.length) {
        buffer.write(text[++i]);
        inToken = true;
      } else if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        flush();
      } else if (char == '#' && !inToken) {
        while (i + 1 < text.length && text[i + 1] != '\n') {
          i++;
        }
      } else if (char == '|' || char == ';') {
        break;
      } else {
        buffer.write(char);
        inToken = true;
      }
    }
    flush();
    return tokens;
  }

  /// The text of an ANSI-C quoted string `$'...'`: the escapes `\n \t \r \a \b \e \f \v \\ \' \" \?`, octal
  /// `\nnn`, `\xHH` (a byte), `\uHHHH` and `\UHHHHHHHH` (code points). Bytes and characters are collected as
  /// UTF-8, so `\xc3\xa9` reads as the one character it spells. Any other `\c` stays as it was typed.
  static String _decodeAnsiC(String content) {
    final bytes = <int>[];
    final runes = content.runes.toList();
    const simple = {0x61: 7, 0x62: 8, 0x65: 27, 0x45: 27, 0x66: 12, 0x6E: 10, 0x72: 13, 0x74: 9, 0x76: 11};

    // The number spelled by up to [maxDigits] digits of [radix] from [from]; its length is returned through [used].
    (int?, int) number(int from, int maxDigits, int radix) {
      var end = from;
      while (end < runes.length && end - from < maxDigits && int.tryParse(String.fromCharCode(runes[end]), radix: radix) != null) {
        end++;
      }
      if (end == from) return (null, 0);
      return (int.parse(String.fromCharCodes(runes.sublist(from, end)), radix: radix), end - from);
    }

    void addCodePoint(int code) => bytes.addAll(utf8.encode(String.fromCharCode(code)));

    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      if (rune != 0x5C || i + 1 >= runes.length) {
        addCodePoint(rune);
        continue;
      }
      final escaped = runes[++i];
      if (simple.containsKey(escaped)) {
        bytes.add(simple[escaped]!);
      } else if ('\\\'"?'.runes.contains(escaped)) {
        bytes.add(escaped);
      } else if (escaped >= 0x30 && escaped <= 0x37) {
        final (value, used) = number(i, 3, 8);
        bytes.add(value! & 0xFF);
        i += used - 1;
      } else if (escaped == 0x78 || escaped == 0x75 || escaped == 0x55) {
        final digits = escaped == 0x78 ? 2 : (escaped == 0x75 ? 4 : 8);
        final (value, used) = number(i + 1, digits, 16);
        if (value == null || value > 0x10FFFF) {
          bytes.addAll(utf8.encode('\\${String.fromCharCode(escaped)}'));
        } else {
          if (escaped == 0x78) {
            bytes.add(value);
          } else {
            addCodePoint(value);
          }
          i += used;
        }
      } else {
        bytes.addAll(utf8.encode('\\${String.fromCharCode(escaped)}'));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

final class _State {
  final positional = <String>[];
  final headers = <KeyValueItem>[];
  final data = <String>[];
  final formFields = <KeyValueItem>[];
  final notes = <String>[];
  final urls = <String>[];
  KeyValueItem? binaryFile;
  String? method;
  String? userPass;
  String? bearer;
  var digest = false;
  var headMode = false;
  var getMode = false;
  var uploadMode = false;
  var jsonShortcut = false;

  /// Whether any `-d`-style option was given, even one whose data cannot be read: the command still POSTs.
  var sendsData = false;
  var malformed = false;

  void apply(String option, String? value) {
    switch (option) {
      case 'request':
        method = value;
      case 'header':
        final sep = (value ?? '').indexOf(':');
        if (sep != -1) {
          headers.add(KeyValueItem(key: value!.substring(0, sep).trim(), value: value.substring(sep + 1).trim()));
        }
      case 'data' || 'data-ascii' || 'data-raw' || 'data-binary':
        _addData(value!, readsFiles: option != 'data-raw', binary: option == 'data-binary');
      case 'data-urlencode':
        _addUrlEncoded(value!);
      case 'json':
        jsonShortcut = true;
        _addData(value!, readsFiles: true);
      case 'form' || 'form-string':
        _addForm(value!, readsFiles: option == 'form');
      case 'user':
        userPass = value;
      case 'oauth2-bearer':
        bearer = value;
      case 'digest':
        digest = true;
      case 'cookie':
        if (value!.contains('=')) {
          headers.add(KeyValueItem(key: 'Cookie', value: value));
        } else {
          notes.add('The cookies are read from a file ("$value"), which cannot be imported.');
        }
      case 'user-agent':
        headers.add(KeyValueItem(key: 'User-Agent', value: value!));
      case 'referer':
        headers.add(KeyValueItem(key: 'Referer', value: value!.replaceFirst(RegExp(r';auto$'), '')));
      case 'range':
        headers.add(KeyValueItem(key: 'Range', value: 'bytes=$value'));
      case 'head':
        headMode = true;
      case 'get':
        getMode = true;
      case 'upload-file':
        uploadMode = true;
        if (value == '-' || value == '.') {
          notes.add('The command uploads standard input ("$value"), which cannot be imported; the body is empty.');
        } else {
          binaryFile ??= _fileRow('', value!);
        }
      case 'url':
        urls.add(value!);
    }
  }

  /// `--data-binary @file` sends the file exactly as it is, which is a binary body. `-d @file` and `--json @file`
  /// strip line breaks or add headers on the way, so those cannot be reproduced and stay a note.
  void _addData(String piece, {required bool readsFiles, bool binary = false}) {
    sendsData = true;
    if (readsFiles && piece.startsWith('@')) {
      if (binary && piece.length > 1 && piece != '@-') {
        binaryFile ??= _fileRow('', piece.substring(1));
      } else {
        notes.add('The body is read from a file or standard input ("$piece"), which cannot be imported.');
      }
      return;
    }
    data.add(piece);
  }

  static KeyValueItem _fileRow(String key, String path, {String contentType = '', String fileName = ''}) =>
      KeyValueItem(key: key, value: path, kind: FormFieldKind.file, contentType: contentType, fileName: fileName);

  /// `content`, `=content`, `name=content` are encoded; `@file` and `name@file` read a file.
  void _addUrlEncoded(String argument) {
    sendsData = true;
    final eq = argument.indexOf('=');
    if (eq != -1) {
      final name = argument.substring(0, eq);
      final encoded = CurlParser._percentEncode(argument.substring(eq + 1));
      data.add(name.isEmpty ? encoded : '$name=$encoded');
    } else if (argument.contains('@')) {
      notes.add('A URL-encoded body part is read from a file ("$argument"), which cannot be imported.');
    } else {
      data.add(CurlParser._percentEncode(argument));
    }
  }

  /// `name=value` is a text field and `name=@file` a file field (with its `;type=` and `;filename=`). A field that
  /// takes its text from a file (`name=<file`) cannot be reproduced: it is kept but switched off.
  void _addForm(String argument, {required bool readsFiles}) {
    final eq = argument.indexOf('=');
    if (eq <= 0) return;
    final name = argument.substring(0, eq);
    var value = argument.substring(eq + 1);
    if (readsFiles && value.startsWith('@')) {
      final file = _CurlFormFile.parse(value.substring(1));
      formFields.add(_fileRow(name, file.path, contentType: file.contentType, fileName: file.fileName));
      if (file.several) {
        notes.add('Form field "$name" sends several files ("$value"); only the first was imported.');
      }
      return;
    }
    if (readsFiles && value.startsWith('<')) {
      formFields.add(KeyValueItem(key: name, value: value, enabled: false));
      notes.add('Form field "$name" takes its text from a file ("$value"), which cannot be imported; it was kept switched off.');
      return;
    }
    value = value.replaceFirst(RegExp(r';type=[^;]*$'), '');
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
    formFields.add(KeyValueItem(key: name, value: value));
  }

  ParsedCurlRequest? build() {
    final url = _pickUrl();
    if (url == null) return null;

    final headers = [...this.headers];
    var targetUrl = url;
    String? body = data.isEmpty ? null : data.join('&');
    if (getMode && body != null) {
      targetUrl = '$url${url.contains('?') ? '&' : '?'}$body';
      body = null;
    }
    final fields = formFields;
    if (fields.isNotEmpty) body = null;

    bool has(String name) => headers.any((h) => h.key.toLowerCase() == name);
    if (jsonShortcut) {
      if (!has('content-type')) headers.add(KeyValueItem(key: 'Content-Type', value: 'application/json'));
      if (!has('accept')) headers.add(KeyValueItem(key: 'Accept', value: 'application/json'));
    } else if (body != null && !has('content-type') && !CurlParser.looksJson(body)) {
      // curl sends `-d` data as a form unless told otherwise; without the header the app would send text/plain.
      headers.add(KeyValueItem(key: 'Content-Type', value: 'application/x-www-form-urlencoded'));
    }

    final file = fields.isEmpty ? binaryFile : null;
    if (file != null) {
      if (body != null) notes.add('The command sends a file and other data as its body; only the file was imported.');
      body = null;
      // `-T file` to a URL that ends in a slash is sent to that URL with the file's name appended.
      if (uploadMode && targetUrl.endsWith('/')) targetUrl = '$targetUrl${Uri.encodeComponent(FilePaths.baseName(file.value))}';
    } else if (binaryFile != null) {
      notes.add('The command sends a file and form fields; only the form fields were imported.');
    }

    bool hasType() => headers.any((h) => h.key.toLowerCase() == 'content-type');
    // curl types `--data-binary` like any `-d` data unless told otherwise (`-T` sends no type, the app's default applies).
    if (file != null && !uploadMode && !hasType() && !jsonShortcut) {
      headers.add(KeyValueItem(key: 'Content-Type', value: 'application/x-www-form-urlencoded'));
    }

    final hasBody = sendsData || fields.isNotEmpty || file != null;
    final verb = method ?? (headMode ? 'HEAD' : uploadMode ? 'PUT' : (hasBody && !getMode ? 'POST' : 'GET'));
    final paths = UploadPathNote.of(UploadPathNote.machineSpecificRows([...fields, ?file]));
    return ParsedCurlRequest(
      method: HttpMethod.fromString(verb),
      url: targetUrl,
      headers: headers,
      body: body,
      auth: _auth(),
      formFields: fields,
      binaryFile: file,
      notes: [...notes, ?paths],
    );
  }

  /// The explicit `--url`, else the first positional with a scheme, else the first positional. A value of
  /// an option this parser does not know about can end up among the positionals; a real URL wins over it.
  String? _pickUrl() {
    final candidates = [...urls, ...positional].where((t) => t.isNotEmpty && t != '-').toList();
    final scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://');
    for (final candidate in candidates) {
      if (scheme.hasMatch(candidate)) return candidate;
    }
    return candidates.firstOrNull;
  }

  RequestAuth _auth() {
    final pair = userPass;
    if (pair != null) {
      final sep = pair.indexOf(':');
      return RequestAuth(
        type: digest ? AuthType.digest : AuthType.basic,
        basicUsername: sep == -1 ? pair : pair.substring(0, sep),
        basicPassword: sep == -1 ? '' : pair.substring(sep + 1),
      );
    }
    final token = bearer;
    if (token != null) return RequestAuth(type: AuthType.bearer, bearerToken: token);
    return const RequestAuth(type: AuthType.inherit);
  }
}

/// What follows the `@` of `curl --form name=@...`: the file (in double quotes, with `\"` and `\\` escaped, when it
/// holds `;` `,` or `"`), then `;type=` and `;filename=` options. An unquoted `a,b` is several files in curl; the
/// first one is taken ([several] says there were more).
final class _CurlFormFile {
  final String path;
  final String contentType;
  final String fileName;
  final bool several;

  const _CurlFormFile(this.path, this.contentType, this.fileName, this.several);

  static _CurlFormFile parse(String text) {
    var path = '';
    var end = 0;
    var several = false;
    if (text.startsWith('"')) {
      final out = StringBuffer();
      var i = 1;
      while (i < text.length && text[i] != '"') {
        if (text[i] == '\\' && i + 1 < text.length && (text[i + 1] == '"' || text[i + 1] == '\\')) i++;
        out.write(text[i]);
        i++;
      }
      path = out.toString();
      end = i + 1 > text.length ? text.length : i + 1;
    } else {
      final semicolon = text.indexOf(';');
      end = semicolon == -1 ? text.length : semicolon;
      path = text.substring(0, end);
      if (path.contains(',')) {
        several = true;
        path = path.substring(0, path.indexOf(','));
      }
    }
    var contentType = '';
    var fileName = '';
    for (final option in text.substring(end).split(';')) {
      final eq = option.indexOf('=');
      if (eq == -1) continue;
      final name = option.substring(0, eq).trim().toLowerCase();
      var value = option.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
      if (name == 'type') contentType = value;
      if (name == 'filename') fileName = value;
    }
    return _CurlFormFile(path, contentType, fileName, several);
  }
}
