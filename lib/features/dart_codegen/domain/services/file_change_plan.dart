import '../entities/generated_file.dart';
import 'unified_diff.dart';

/// What writing one generated file into a folder would do.
enum FileChangeKind {
  /// Not in the folder yet.
  created,

  /// In the folder with other content.
  changed,

  /// In the folder with the same content (line endings and trailing blank lines aside).
  unchanged,

  /// A shared file the project already has (its own `api_client.dart`): never replaced, whatever it holds.
  keptShared,
}

final class FileChange {
  final GeneratedFile file;
  final FileChangeKind kind;

  /// Old text to generated text; for a new file everything is added. Null for [FileChangeKind.unchanged] and [FileChangeKind.keptShared].
  final UnifiedDiff? diff;

  const FileChange(this.file, this.kind, this.diff);

  String get path => file.path;

  /// The diff as text with the file's path on both header lines (`/dev/null` before a new file).
  String get diffText => diff?.format(beforeLabel: kind == FileChangeKind.created ? '/dev/null' : 'a/$path', afterLabel: 'b/$path') ?? '';
}

/// Compares a generated set with what is on disk, so "Write changed files only" can show exactly what it would touch
/// before it touches anything.
final class FileChangePlan {
  final List<FileChange> changes;
  const FileChangePlan(this.changes);

  /// [onDisk] holds the current text of the files that exist in the folder, by the same relative paths.
  static FileChangePlan compute(List<GeneratedFile> files, Map<String, String> onDisk) {
    final changes = <FileChange>[];
    for (final file in files) {
      final current = onDisk[file.path];
      if (current == null) {
        changes.add(FileChange(file, FileChangeKind.created, UnifiedDiff.compute('', file.content)));
      } else if (file.shared) {
        changes.add(FileChange(file, FileChangeKind.keptShared, null));
      } else {
        final diff = UnifiedDiff.compute(current, file.content);
        changes.add(diff.isEmpty ? FileChange(file, FileChangeKind.unchanged, null) : FileChange(file, FileChangeKind.changed, diff));
      }
    }
    return FileChangePlan(changes);
  }

  Iterable<FileChange> _of(FileChangeKind kind) => changes.where((c) => c.kind == kind);

  List<FileChange> get created => _of(FileChangeKind.created).toList();
  List<FileChange> get changed => _of(FileChangeKind.changed).toList();
  List<FileChange> get unchanged => _of(FileChangeKind.unchanged).toList();
  List<FileChange> get keptShared => _of(FileChangeKind.keptShared).toList();

  /// The files "Write changed files only" writes: the new ones and the ones whose text differs.
  List<GeneratedFile> get toWrite => [for (final c in changes) if (c.kind == FileChangeKind.created || c.kind == FileChangeKind.changed) c.file];

  bool get hasWork => toWrite.isNotEmpty;
}
