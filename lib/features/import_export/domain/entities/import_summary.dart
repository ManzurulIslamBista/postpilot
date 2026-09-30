import 'import_format.dart';

/// What an import or restore created, for the success message.
final class ImportSummary {
  final ImportFormat format;

  /// The collections that were created (or, for a cURL import into an existing
  /// collection, the one that received the requests).
  final List<int> collectionIds;

  /// Set when exactly one collection is involved and its name is known.
  final String? collectionName;
  final int folders;
  final int requests;
  final int environments;
  final int globalVariables;

  /// Entries that could not be imported (a HAR entry with no URL, a global
  /// variable that already exists, ...).
  final int skipped;

  const ImportSummary({
    required this.format,
    this.collectionIds = const [],
    this.collectionName,
    this.folders = 0,
    this.requests = 0,
    this.environments = 0,
    this.globalVariables = 0,
    this.skipped = 0,
  });

  String get description {
    final verb = format == ImportFormat.backup ? 'Restored' : 'Imported';
    final head = switch (collectionIds.length) {
      _ when collectionName != null => '$verb "$collectionName"',
      > 1 => '$verb ${collectionIds.length} collections',
      _ => verb,
    };
    final parts = [
      if (folders > 0) _plural(folders, 'folder'),
      _plural(requests, 'request'),
      if (environments > 0) _plural(environments, 'environment'),
      if (globalVariables > 0) _plural(globalVariables, 'global variable'),
    ];
    final skippedNote = skipped > 0 ? ' ($skipped skipped)' : '';
    return '$head: ${parts.join(', ')}$skippedNote';
  }

  static String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
}
