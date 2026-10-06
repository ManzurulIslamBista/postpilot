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

  /// The variables an environment or globals file brought in, and the environment's name when it made one.
  final int variables;
  final String? environmentName;

  /// Entries that could not be imported (a HAR entry with no URL, a global
  /// variable that already exists, ...).
  final int skipped;

  /// One sentence per thing that was left out or changed, for the dialog to
  /// list after the import ([skipped] counts the left-out ones). Empty when
  /// the import was clean. Never holds a variable's value.
  final List<String> notes;

  const ImportSummary({
    required this.format,
    this.collectionIds = const [],
    this.collectionName,
    this.folders = 0,
    this.requests = 0,
    this.environments = 0,
    this.globalVariables = 0,
    this.variables = 0,
    this.environmentName,
    this.skipped = 0,
    this.notes = const [],
  });

  String get description {
    final verb = format == ImportFormat.backup ? 'Restored' : 'Imported';
    final head = switch (collectionIds.length) {
      _ when collectionName != null => '$verb "$collectionName"',
      _ when environmentName != null => '$verb "$environmentName"',
      > 1 => '$verb ${collectionIds.length} collections',
      _ => verb,
    };
    final parts = [
      if (folders > 0) _plural(folders, 'folder'),
      if (requests > 0 || format != ImportFormat.postmanEnvironment) _plural(requests, 'request'),
      if (environments > 0) _plural(environments, 'environment'),
      if (globalVariables > 0) _plural(globalVariables, 'global variable'),
      if (variables > 0) _plural(variables, 'variable'),
    ];
    final skippedNote = skipped > 0 ? ' ($skipped skipped)' : '';
    return '$head: ${parts.join(', ')}$skippedNote';
  }

  /// The heading of the details list: "Imported with 3 skipped items".
  String get notesHeading {
    if (skipped > 0) return 'Imported with ${_plural(skipped, 'skipped item')}';
    return 'Imported with ${_plural(notes.length, 'note')}';
  }

  static String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
}
