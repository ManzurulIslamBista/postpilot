import 'dart:convert';

enum SyncKind { collection, folder, request }

/// One synced entity — a collection, folder or request as it lives in the Git
/// repository. [uid] is its identity across machines; local database ids never
/// reach a file. Everything except the reserved keys lives in [data] and is
/// stored flat next to them in the file.
final class SyncDoc {
  static const reservedKeys = {'uid', 'kind', 'parent', 'name', 'order'};

  final String uid;
  final SyncKind kind;

  /// Uid of the containing folder, or of the collection for top-level items.
  /// Null only for the collection doc itself.
  final String? parentUid;
  final String name;

  /// Position among siblings (ascending).
  final int order;

  /// JSON-safe payload (maps, lists, strings, numbers, bools, null) whose keys
  /// never collide with [reservedKeys].
  final Map<String, Object?> data;

  const SyncDoc({
    required this.uid,
    required this.kind,
    required this.parentUid,
    required this.name,
    this.order = 0,
    this.data = const {},
  });

  /// What the three-way merge compares: `name`, `parentUid`, `order` and every
  /// [data] key, one entry per field.
  Map<String, Object?> get fields => {'name': name, 'parentUid': parentUid, 'order': order, ...data};

  /// Rebuilds a doc from a [fields] map (inverse of [fields]).
  SyncDoc withFields(Map<String, Object?> fields) => SyncDoc(
        uid: uid,
        kind: kind,
        parentUid: fields['parentUid'] as String?,
        name: fields['name'] as String? ?? name,
        order: (fields['order'] as num?)?.toInt() ?? order,
        data: {
          for (final e in fields.entries)
            if (e.key != 'name' && e.key != 'parentUid' && e.key != 'order') e.key: e.value,
        },
      );

  Map<String, Object?> toJson() => {
        'uid': uid,
        'kind': kind.name,
        'parent': parentUid,
        'name': name,
        'order': order,
        ...data,
      };

  factory SyncDoc.fromJson(Map<String, dynamic> json) => SyncDoc(
        uid: json['uid'] as String,
        kind: SyncKind.values.firstWhere((k) => k.name == json['kind']),
        parentUid: json['parent'] as String?,
        name: json['name'] as String? ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        data: {
          for (final e in json.entries)
            if (!reservedKeys.contains(e.key)) e.key: e.value,
        },
      );

  /// Byte-stable text for this doc: sorted keys, two-space indent, trailing
  /// newline — what is written to the repository file and what change
  /// detection compares.
  String get canonicalText => canonicalJson(toJson());

  @override
  bool operator ==(Object other) => other is SyncDoc && other.canonicalText == canonicalText;

  @override
  int get hashCode => canonicalText.hashCode;
}

/// Every synced doc of one collection, keyed by uid. Exactly one doc has
/// [SyncKind.collection].
final class SyncSnapshot {
  final Map<String, SyncDoc> docs;
  const SyncSnapshot(this.docs);

  static const empty = SyncSnapshot({});

  SyncDoc? get root {
    for (final doc in docs.values) {
      if (doc.kind == SyncKind.collection) return doc;
    }
    return null;
  }

  bool get isEmpty => docs.isEmpty;
}

/// JSON with recursively sorted map keys, two-space indent and a trailing
/// newline. Two logically equal values always encode to the same text, so Git
/// diffs show only real edits.
String canonicalJson(Object? value) => '${const JsonEncoder.withIndent('  ').convert(_sorted(value))}\n';

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sorted(value[k])};
  }
  if (value is List) return [for (final e in value) _sorted(e)];
  return value;
}
