// Pure Dart: the command-line build uses it too. The platform sources live in the `_io` and `_stub` files.
import 'dart:async';
import 'dart:typed_data';
import '../errors/app_exception.dart';
import '../../features/documentation/domain/services/secret_masker.dart';
import 'upload_body.dart';

export 'upload_file_source_stub.dart' if (dart.library.io) 'upload_file_source_io.dart' show createUploadFileSource;

/// Where the bytes of an [UploadFile] come from: the disk on desktop and mobile, the files kept for the session
/// in a browser. Both say what is wrong with an [InvalidRequestException] that names the file and what to do.
abstract interface class UploadFileSource {
  /// The size of [file] in bytes. Throws [InvalidRequestException] when it is missing, is a folder, cannot be read
  /// or (in a browser) was picked in an earlier session.
  Future<int> sizeOf(UploadFile file);

  /// The content of [file], read in chunks: a large file is never loaded whole.
  Stream<List<int>> read(UploadFile file);

  /// A quick look at [path] for the editor, which shows it beside the field. Never throws.
  Future<UploadFileCheck> check(String path);
}

/// What the editor shows about a file: its [size], or in [problem] a short phrase saying why it cannot be sent. A
/// path that holds a `{{variable}}` is [unresolved]: only the send knows where it points.
final class UploadFileCheck {
  final int? size;
  final String? problem;
  final bool unresolved;

  const UploadFileCheck({this.size, this.problem, this.unresolved = false});

  static const noFile = UploadFileCheck(problem: 'No file chosen');
  static const lostWithTheSession = UploadFileCheck(
    problem: 'Chosen in an earlier browser session: a browser cannot reopen it, choose the file again',
  );
}

/// What [UploadPreparer] hands the HTTP client: a body of a known [length] that can be opened again for every hop of
/// a redirect.
final class PreparedUpload {
  final int length;
  final String contentType;
  final Stream<List<int>> Function() open;

  const PreparedUpload({required this.length, required this.contentType, required this.open});
}

/// Turns an [UploadBody] into a [PreparedUpload]: every file is looked at (it must exist and be readable) and the total
/// size is held against the limit, all before anything is sent.
abstract final class UploadPreparer {
  /// [maxBytes] is the limit on the size of the whole body (null: none); [limitHint] says where to change it.
  /// Throws [InvalidRequestException]; its text is masked and safe to show as it is.
  static Future<PreparedUpload> prepare(
    UploadBody body,
    UploadFileSource source, {
    int? maxBytes,
    String limitHint = 'Raise "Maximum upload size" in Settings to send a larger file.',
  }) async {
    final sizes = <UploadFile, int>{};
    var length = 0;
    final segments = body.segments();
    for (final segment in segments) {
      switch (segment) {
        case BytesSegment(:final bytes):
          length += bytes.length;
        case FileSegment(:final file):
          final size = await source.sizeOf(file);
          sizes[file] = size;
          length += size;
      }
    }
    if (maxBytes != null && length > maxBytes) {
      throw InvalidRequestException(SecretMasker.maskMessage(
        'The upload is ${UploadLimits.describe(length)}, over the ${UploadLimits.describe(maxBytes)} limit. $limitHint',
      ));
    }
    return PreparedUpload(
      length: length,
      contentType: body.contentType,
      open: () => _write(segments, sizes, source),
    );
  }

  /// Written lazily: a file is opened when the stream gets to it, and read in the chunks the source gives.
  static Stream<List<int>> _write(List<UploadSegment> segments, Map<UploadFile, int> sizes, UploadFileSource source) async* {
    for (final segment in segments) {
      switch (segment) {
        case BytesSegment(:final bytes):
          yield bytes;
        case FileSegment(:final file):
          var read = 0;
          await for (final chunk in source.read(file)) {
            read += chunk.length;
            yield chunk;
          }
          // The size went out in `Content-Length`: a file that grew or shrank since it was measured would break the
          // request in a way the server describes badly.
          if (read != sizes[file]) {
            throw InvalidRequestException(SecretMasker.maskMessage(
              '${_capitalised(file.label)} sends "${file.fileName}", which changed while it was being sent. Send the request again.',
            ));
          }
      }
    }
  }

  static String _capitalised(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}

/// The one message shape for a file that cannot be sent, shared by every source.
abstract final class UploadFileProblem {
  static InvalidRequestException notFound(UploadFile file) => _problem(
        file,
        'sends the file "${file.path}", which was not found. Check the path (or the variable it uses), '
        'or choose the file again.',
      );

  static InvalidRequestException notAFile(UploadFile file) =>
      _problem(file, 'sends "${file.path}", which is a folder, not a file. Choose a file.');

  static InvalidRequestException unreadable(UploadFile file, String reason) =>
      _problem(file, 'sends "${file.path}", which cannot be read ($reason). Check its permissions or choose the file again.');

  static InvalidRequestException noFileChosen(UploadFile file) =>
      _problem(file, 'has no file chosen. Choose a file, or switch the field off.');

  static InvalidRequestException lostWithTheSession(UploadFile file) => _problem(
        file,
        'sends "${file.fileName}", which was chosen in an earlier browser session. A browser cannot read it again: '
        'choose the file again.',
      );

  static InvalidRequestException _problem(UploadFile file, String what) {
    final subject = file.label.isEmpty ? 'A file' : '${file.label[0].toUpperCase()}${file.label.substring(1)}';
    return InvalidRequestException(SecretMasker.maskMessage('$subject $what'));
  }
}

/// A source over files already in memory (the web build, and tests).
final class MemoryUploadFileSource implements UploadFileSource {
  final SessionFiles files;
  const MemoryUploadFileSource(this.files);

  @override
  Future<int> sizeOf(UploadFile file) async => _bytes(file).length;

  @override
  Stream<List<int>> read(UploadFile file) => Stream.value(_bytes(file));

  @override
  Future<UploadFileCheck> check(String path) async {
    final text = path.trim();
    if (text.isEmpty) return UploadFileCheck.noFile;
    final bytes = files.bytesOf(text);
    if (bytes != null) return UploadFileCheck(size: bytes.length);
    if (text.contains('{{')) return const UploadFileCheck(unresolved: true);
    return SessionFiles.isReference(text)
        ? UploadFileCheck.lostWithTheSession
        : const UploadFileCheck(problem: 'A browser can only send a file chosen with the button: choose the file');
  }

  Uint8List _bytes(UploadFile file) {
    if (file.path.isEmpty) throw UploadFileProblem.noFileChosen(file);
    final bytes = files.bytesOf(file.path);
    if (bytes == null) throw UploadFileProblem.lostWithTheSession(file);
    return bytes;
  }
}
