// Pure Dart (no Flutter, no dart:io): the command-line build, the web build and the app all use these.
import 'dart:convert';
import 'dart:typed_data';

/// A file a request uploads: what is sent in a form-data `file` part or as the whole body, named by the request
/// (its `{{variables}}` already resolved). Only the reference travels through the request pipeline: the bytes are
/// read from storage at send time (see `UploadPreparer`), never kept in a request, a snapshot or a document.
final class UploadFile {
  /// A path on disk, or a [SessionFiles] reference for a file picked in the browser.
  final String path;

  /// The name the server sees (`filename=` of a form part).
  final String fileName;
  final String contentType;

  /// Where the request uses it, for messages: `the form field "avatar"`, `the request body`.
  final String label;

  const UploadFile({required this.path, required this.fileName, required this.contentType, required this.label});
}

sealed class UploadPart {
  final String name;
  const UploadPart(this.name);
}

final class UploadTextPart extends UploadPart {
  final String value;
  const UploadTextPart(super.name, this.value);
}

final class UploadFilePart extends UploadPart {
  final UploadFile file;
  const UploadFilePart(super.name, this.file);
}

/// A piece of the encoded body: literal bytes, or the place a file's content goes.
sealed class UploadSegment {
  const UploadSegment();
}

final class BytesSegment extends UploadSegment {
  final Uint8List bytes;
  const BytesSegment(this.bytes);
}

final class FileSegment extends UploadSegment {
  final UploadFile file;
  const FileSegment(this.file);
}

/// A request body that carries a file. [ResolvedRequestSpec] holds one next to (never together with) the plain
/// `bodyBytes`, the code generators print it, and `UploadPreparer` turns it into a streamed body at send time.
sealed class UploadBody {
  const UploadBody();

  /// The `Content-Type` of the whole body.
  String get contentType;

  /// Every file the body reads, in the order it is written.
  List<UploadFile> get files;

  /// The body as the pieces it is written in. The files are streamed between the pieces, never loaded here.
  List<UploadSegment> segments();
}

/// `multipart/form-data` made of text parts and file parts, RFC 7578. Names and file names are written the way
/// browsers do (WHATWG): a double quote, CR and LF are percent-encoded, anything else is sent as UTF-8.
final class MultipartUpload extends UploadBody {
  final String boundary;
  final List<UploadPart> parts;

  const MultipartUpload({required this.boundary, required this.parts});

  @override
  String get contentType => 'multipart/form-data; boundary=$boundary';

  @override
  List<UploadFile> get files => [
        for (final part in parts)
          if (part is UploadFilePart) part.file,
      ];

  @override
  List<UploadSegment> segments() {
    final segments = <UploadSegment>[];
    final pending = BytesBuilder(copy: false);

    void text(String value) => pending.add(utf8.encode(value));
    void flush() {
      if (pending.isEmpty) return;
      segments.add(BytesSegment(pending.takeBytes()));
    }

    for (final part in parts) {
      text('--$boundary\r\n');
      switch (part) {
        case UploadTextPart(:final name, :final value):
          text('Content-Disposition: form-data; name="${_quoted(name)}"\r\n\r\n');
          text('$value\r\n');
        case UploadFilePart(:final name, :final file):
          text('Content-Disposition: form-data; name="${_quoted(name)}"; filename="${_quoted(file.fileName)}"\r\n');
          text('Content-Type: ${_singleLine(file.contentType)}\r\n\r\n');
          flush();
          segments.add(FileSegment(file));
          text('\r\n');
      }
    }
    text('--$boundary--\r\n');
    flush();
    return segments;
  }

  /// The whole body, for a form without a file. A form with one has to be streamed instead.
  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false);
    for (final segment in segments()) {
      switch (segment) {
        case BytesSegment(:final bytes):
          builder.add(bytes);
        case FileSegment():
          throw StateError('A form with a file part has to be streamed, not turned into bytes.');
      }
    }
    return builder.takeBytes();
  }

  static String _quoted(String text) => text.replaceAll('"', '%22').replaceAll('\r', '%0D').replaceAll('\n', '%0A');

  /// A type that came from a variable must not be able to end its header line and start another.
  static String _singleLine(String text) => text.replaceAll(RegExp(r'[\r\n]+'), ' ');
}

/// The bytes of one file as the whole body (an S3 `PUT`, `application/octet-stream`).
final class BinaryUpload extends UploadBody {
  final UploadFile file;
  const BinaryUpload(this.file);

  static const defaultContentType = 'application/octet-stream';

  /// The type its file names: the one the user chose, else [defaultContentType].
  @override
  String get contentType => file.contentType;

  @override
  List<UploadFile> get files => [file];

  @override
  List<UploadSegment> segments() => [FileSegment(file)];
}

/// Limits on what is uploaded.
abstract final class UploadLimits {
  /// The default of the "Maximum upload size" setting, in megabytes.
  static const defaultMegabytes = 100;

  /// The largest file the web build keeps in memory for a session (a browser cannot stream from disk).
  static const webSessionBytes = defaultMegabytes * 1024 * 1024;

  /// `3.5 MB`, `120 KB`, `12 bytes`.
  static String describe(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes ${bytes == 1 ? 'byte' : 'bytes'}';
  }
}

/// Names and tells apart the paths a request holds. Written by hand rather than with `dart:io` or `package:path`
/// because a path from a workspace made on Windows has to be read the same on Linux and in the browser.
abstract final class FilePaths {
  /// The last segment of [path]; for a [SessionFiles] reference the name it was picked with.
  static String baseName(String path) {
    if (SessionFiles.isReference(path)) return SessionFiles.nameOf(path);
    final trimmed = path.trim();
    final cut = trimmed.lastIndexOf(RegExp(r'[\\/]'));
    return cut == -1 ? trimmed : trimmed.substring(cut + 1);
  }

  /// `/home/me/a.png`, `C:\a.png`, `C:/a.png`, `\\server\share\a.png` and `~/a.png` name one place on one machine.
  /// A path that starts with a `{{variable}}` is not machine-specific: the variable decides where it points.
  static bool isMachineSpecific(String path) {
    final text = path.trim();
    if (text.isEmpty || SessionFiles.isReference(text) || text.startsWith('{{')) return false;
    return text.startsWith('/') || text.startsWith(r'\\') || text.startsWith('~') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(text);
  }

  /// [path] against the folder [baseDir] when it is relative; an absolute path, a session reference and a path
  /// that starts with an unresolved `{{variable}}` are returned as they are. The result uses [baseDir]'s own
  /// separator, so it names the file on the machine [baseDir] came from.
  static String resolve(String path, String? baseDir) {
    final text = path.trim();
    if (baseDir == null || baseDir.isEmpty || text.isEmpty) return text;
    if (SessionFiles.isReference(text) || text.startsWith('{{') || isMachineSpecific(text)) return text;
    final separator = baseDir.contains('\\') && !baseDir.contains('/') ? '\\' : '/';
    final base = baseDir.endsWith('/') || baseDir.endsWith('\\') ? baseDir : '$baseDir$separator';
    final relative = text.startsWith('./') || text.startsWith(r'.\') ? text.substring(2) : text;
    return '$base${separator == '\\' ? relative.replaceAll('/', r'\') : relative}';
  }
}

/// Files picked in a browser. A browser hands out no path and cannot read a file again later, so the picked bytes are
/// kept in memory for the session and the request holds a reference to them. The reference is the only thing that is
/// saved: after a reload it points to nothing, [contains] says so, and the editor asks for the file again.
final class SessionFiles {
  static const scheme = 'session-file:';

  /// The one registry of the running app, shared by the editor that picks and the client that sends.
  static final shared = SessionFiles();

  final Map<String, Uint8List> _bytes = {};
  int _next = 0;

  /// Keeps [bytes] for this session and returns the reference to save in the request.
  String add({required String name, required Uint8List bytes}) {
    final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_next++).toRadixString(36)}';
    _bytes[id] = bytes;
    return '$scheme$id/$name';
  }

  /// Whether [reference] is one of the files kept in this session.
  bool contains(String reference) => bytesOf(reference) != null;

  Uint8List? bytesOf(String reference) => isReference(reference) ? _bytes[_idOf(reference)] : null;

  void remove(String reference) {
    if (isReference(reference)) _bytes.remove(_idOf(reference));
  }

  static bool isReference(String path) => path.startsWith(scheme);

  /// The name a file was picked with, kept in the reference so it can be shown after a reload.
  static String nameOf(String reference) {
    final rest = reference.substring(scheme.length);
    final slash = rest.indexOf('/');
    return slash == -1 ? '' : rest.substring(slash + 1);
  }

  static String _idOf(String reference) {
    final rest = reference.substring(scheme.length);
    final slash = rest.indexOf('/');
    return slash == -1 ? rest : rest.substring(0, slash);
  }
}

/// Content types guessed from a file name's extension, the way a browser or `curl` would.
abstract final class ContentTypes {
  static const fallback = 'application/octet-stream';

  /// The type for [fileName], [fallback] when its extension is not known.
  static String forFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return fallback;
    return _byExtension[fileName.substring(dot + 1).toLowerCase()] ?? fallback;
  }

  static const _byExtension = {
    'txt': 'text/plain',
    'log': 'text/plain',
    'csv': 'text/csv',
    'tsv': 'text/tab-separated-values',
    'md': 'text/markdown',
    'html': 'text/html',
    'htm': 'text/html',
    'css': 'text/css',
    'js': 'application/javascript',
    'mjs': 'application/javascript',
    'json': 'application/json',
    'ndjson': 'application/x-ndjson',
    'xml': 'application/xml',
    'yaml': 'application/yaml',
    'yml': 'application/yaml',
    'toml': 'application/toml',
    'sql': 'application/sql',
    'ics': 'text/calendar',
    'vcf': 'text/vcard',
    'rtf': 'application/rtf',
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'avif': 'image/avif',
    'heic': 'image/heic',
    'bmp': 'image/bmp',
    'ico': 'image/vnd.microsoft.icon',
    'svg': 'image/svg+xml',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
    'zip': 'application/zip',
    'gz': 'application/gzip',
    'tar': 'application/x-tar',
    '7z': 'application/x-7z-compressed',
    'rar': 'application/vnd.rar',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'm4a': 'audio/mp4',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'epub': 'application/epub+zip',
    'apk': 'application/vnd.android.package-archive',
    'wasm': 'application/wasm',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'bin': 'application/octet-stream',
  };
}
