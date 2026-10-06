import 'dart:io';
import 'package:path/path.dart' as p;
import 'generated_files_writer_result.dart';

bool get canWriteFilesToFolder => true;

Future<String> _base(String folder) async {
  final root = Directory(folder);
  if (!await root.exists()) throw ArgumentError.value(folder, 'folder', 'does not exist');
  return p.normalize(root.absolute.path);
}

/// The absolute path of [relative] inside [base]; throws for one that leaves it.
String _target(String base, String relative) {
  final target = p.normalize(p.join(base, relative));
  if (p.isAbsolute(relative) || !p.isWithin(base, target)) {
    throw ArgumentError.value(relative, 'path', 'resolves outside the chosen folder');
  }
  return target;
}

Future<List<String>> existingFilesInFolder(String folder, Iterable<String> paths) async {
  final base = await _base(folder);
  final existing = <String>[];
  for (final path in paths) {
    if (await FileSystemEntity.type(_target(base, path)) != FileSystemEntityType.notFound) existing.add(path);
  }
  return existing;
}

Future<WriteFilesResult> writeFilesToFolder(
  String folder,
  Map<String, String> files, {
  bool overwrite = false,
  Set<String> neverOverwrite = const {},
}) async {
  final base = await _base(folder);
  // Every path is checked before the first file is written.
  final targets = {for (final path in files.keys) path: _target(base, path)};
  final written = <String>[];
  final overwritten = <String>[];
  final skipped = <String>[];
  for (final entry in files.entries) {
    final path = entry.key;
    final file = File(targets[path]!);
    final type = await FileSystemEntity.type(file.path);
    if (type == FileSystemEntityType.directory) throw ArgumentError.value(path, 'path', 'is a folder, not a file');
    final exists = type != FileSystemEntityType.notFound;
    if (exists && (!overwrite || neverOverwrite.contains(path))) {
      skipped.add(path);
      continue;
    }
    await file.parent.create(recursive: true);
    if (!exists) {
      try {
        // Exclusive: if something created the file since the check above, it is not replaced.
        await file.create(exclusive: true);
      } on FileSystemException {
        if (await FileSystemEntity.type(file.path) == FileSystemEntityType.notFound) rethrow;
        skipped.add(path);
        continue;
      }
    }
    await file.writeAsString(entry.value, flush: true);
    written.add(path);
    if (exists) overwritten.add(path);
  }
  return WriteFilesResult(written: written, overwritten: overwritten, skipped: skipped);
}
