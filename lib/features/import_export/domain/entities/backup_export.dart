/// A finished backup file with what it holds, for the export dialog.
final class BackupExport {
  final String text;
  final int collections;
  final int folders;
  final int requests;
  final int environments;
  final int globalVariables;

  const BackupExport({
    required this.text,
    required this.collections,
    required this.folders,
    required this.requests,
    required this.environments,
    required this.globalVariables,
  });
}
