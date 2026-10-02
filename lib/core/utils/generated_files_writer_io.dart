import 'dart:io';
import 'package:path/path.dart' as p;

bool get canWriteFilesToFolder => true;

Future<int> writeFilesToFolder(String folder, Map<String, String> files) async {
  final root = Directory(folder);
  if (!await root.exists()) throw ArgumentError.value(folder, 'folder', 'does not exist');
  final base = p.normalize(root.absolute.path);
  var written = 0;
  for (final entry in files.entries) {
    final target = p.normalize(p.join(base, entry.key));
    if (p.isAbsolute(entry.key) || !p.isWithin(base, target)) {
      throw ArgumentError.value(entry.key, 'path', 'resolves outside the chosen folder');
    }
    final file = File(target);
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value, flush: true);
    written++;
  }
  return written;
}
