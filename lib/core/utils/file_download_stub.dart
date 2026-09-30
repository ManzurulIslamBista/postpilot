import 'dart:typed_data';

Future<String?> downloadFile({required String fileName, required Uint8List bytes, required String mimeType}) =>
    throw UnsupportedError('File download is not supported on this platform');
