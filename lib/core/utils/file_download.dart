import 'dart:typed_data';
import 'file_download_stub.dart'
    if (dart.library.io) 'file_download_io.dart'
    if (dart.library.js_interop) 'file_download_web.dart' as platform;

/// Saves [bytes] as a file named [fileName]. Returns the written path on
/// platforms that write to disk, or null on web where the browser owns the
/// download.
Future<String?> downloadFile({required String fileName, required Uint8List bytes, required String mimeType}) =>
    platform.downloadFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
