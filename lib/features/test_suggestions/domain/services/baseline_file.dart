import 'dart:convert';
import '../entities/baseline_snapshot.dart';

/// One request's baseline in an export file, named by where the request sits in the workspace (the same names the
/// command line uses to select requests), because the numeric ids of a request differ from machine to machine.
final class BaselineFileEntry {
  final String collection;

  /// `Folder/Sub-folder`, empty at the top level of the collection.
  final String folder;
  final String name;

  /// `GET`, `POST`...
  final String method;
  final DateTime? recordedAt;
  final BaselineSnapshot snapshot;

  const BaselineFileEntry({
    required this.collection,
    required this.folder,
    required this.name,
    required this.method,
    required this.snapshot,
    this.recordedAt,
  });
}

/// The JSON file "Export baselines…" writes and `postpilot run --baseline-file` reads. Baselines are kept on the
/// device that recorded them; this file is how a CI job gets them.
///
/// ```json
/// {
///   "format": "postpilot-baselines", "version": 1, "exportedAt": "2026-10-06T12:00:00.000Z",
///   "baselines": [
///     {"collection": "Shop", "folder": "Orders", "name": "List orders", "method": "GET",
///      "recordedAt": "...", "snapshot": {...}}
///   ]
/// }
/// ```
final class BaselineFile {
  static const format = 'postpilot-baselines';
  static const version = 1;

  final List<BaselineFileEntry> entries;
  const BaselineFile(this.entries);

  static const empty = BaselineFile([]);

  String encode({DateTime? exportedAt}) => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'baselines': [
          for (final e in entries)
            {
              'collection': e.collection,
              'folder': e.folder,
              'name': e.name,
              'method': e.method,
              if (e.recordedAt != null) 'recordedAt': e.recordedAt!.toUtc().toIso8601String(),
              'snapshot': e.snapshot.toJson(),
            },
        ],
      });

  /// Reads [text]. Throws a [FormatException] whose message says what is wrong with the file; an entry that is
  /// malformed is skipped rather than failing the whole file.
  static BaselineFile parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('The baseline file is not valid JSON: ${e.message}');
    }
    if (decoded is! Map || decoded['format'] != format) {
      throw const FormatException('This is not a PostPilot baseline file (use "Export baselines…" in Response tools).');
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion > version) {
      throw FormatException('The baseline file has version $fileVersion; this PostPilot reads version $version. Update PostPilot.');
    }
    final list = decoded['baselines'];
    final entries = <BaselineFileEntry>[];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final snapshot = BaselineSnapshot.fromJson(item['snapshot']);
        final name = item['name'];
        final collection = item['collection'];
        if (snapshot == null || name is! String || collection is! String) continue;
        final folder = item['folder'];
        final method = item['method'];
        final recorded = item['recordedAt'];
        entries.add(BaselineFileEntry(
          collection: collection,
          folder: folder is String ? folder : '',
          name: name,
          method: method is String ? method.toUpperCase() : 'GET',
          snapshot: snapshot,
          recordedAt: recorded is String ? DateTime.tryParse(recorded) : null,
        ));
      }
    }
    return BaselineFile(entries);
  }

  /// The baseline of the request called [name] in [folder] of [collection], or null.
  BaselineSnapshot? find({required String collection, required String folder, required String name, required String method}) {
    final wanted = method.toUpperCase();
    for (final e in entries) {
      if (e.collection == collection && e.folder == folder && e.name == name && e.method == wanted) return e.snapshot;
    }
    return null;
  }
}
