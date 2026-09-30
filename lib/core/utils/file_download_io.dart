import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'safe_file_name.dart';

Future<String?> downloadFile({required String fileName, required Uint8List bytes, required String mimeType}) async {
  final directory = await _targetDirectory();
  await directory.create(recursive: true);
  final file = await _uniqueFile(directory, fileName);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Directory> _targetDirectory() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } catch (_) {
    // Mobile platforms have no downloads directory; fall through to documents.
  }
  return getApplicationDocumentsDirectory();
}

// [fileName] can originate from a server, so it is checked here rather than
// trusted: it must be one plain name that stays inside [directory].
Future<File> _uniqueFile(Directory directory, String fileName) async {
  if (!isSafeFileName(fileName)) {
    throw ArgumentError.value(fileName, 'fileName', 'is not a safe file name');
  }
  final base = p.basenameWithoutExtension(fileName);
  final extension = p.extension(fileName);
  var candidate = _fileIn(directory, fileName);
  for (var i = 1; await candidate.exists(); i++) {
    candidate = _fileIn(directory, '$base ($i)$extension');
  }
  return candidate;
}

File _fileIn(Directory directory, String name) {
  final file = File(p.join(directory.path, name));
  if (!p.isWithin(p.normalize(directory.absolute.path), p.normalize(file.absolute.path))) {
    throw ArgumentError.value(name, 'fileName', 'resolves outside the download folder');
  }
  return file;
}
