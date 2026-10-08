import '../../../collections/domain/entities/collection_entity.dart';
import '../../../defaults/domain/entities/default_variable.dart';
import '../../../defaults/domain/entities/level_defaults.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import 'field_builders.dart';
import 'refactor_scope.dart';
import 'unit_field.dart';

/// A collection: its name, description and tags, the auth and the headers and tests it passes down to its requests.
/// Its variables are units of their own (see `CollectionVariableUnit`).
final class CollectionUnit extends RefactorUnit {
  final CollectionEntity collection;
  final String description;
  final List<String> tags;

  /// The default auth of the collection; null when it sets none.
  final RequestAuth? auth;

  /// The headers and tests the collection passes down. Its auth and variables are kept apart, as in the database.
  final LevelDefaults defaults;

  const CollectionUnit({
    required this.collection,
    this.description = '',
    this.tags = const [],
    this.auth,
    this.defaults = LevelDefaults.empty,
  });

  @override
  UnitKind get kind => UnitKind.collection;

  @override
  int get id => collection.id;

  @override
  List<String> get trail => [collection.name];

  CollectionUnit copyWith({
    String? name,
    String? description,
    List<String>? tags,
    RequestAuth? auth,
    LevelDefaults? defaults,
  }) => CollectionUnit(
    collection: name == null ? collection : CollectionEntity(id: collection.id, name: name),
    description: description ?? this.description,
    tags: tags ?? this.tags,
    auth: auth ?? this.auth,
    defaults: defaults ?? this.defaults,
  );

  @override
  Iterable<UnitField> fields() sync* {
    if (collection.name.isNotEmpty) {
      yield UnitField(path: 'name', group: 'name', scope: RefactorScope.names, label: 'Collection name', value: collection.name, write: (v) => copyWith(name: v));
    }
    if (description.isNotEmpty) {
      yield UnitField(path: 'doc', group: 'doc', scope: RefactorScope.docs, label: 'Collection notes', value: description, write: (v) => copyWith(description: v));
    }
    for (var i = 0; i < tags.length; i++) {
      if (tags[i].isEmpty) continue;
      yield UnitField(path: 'tag.$i', group: 'tags', scope: RefactorScope.tags, label: 'Collection tag', value: tags[i], write: (v) => copyWith(tags: replacedAt(tags, i, v)));
    }
    final level = auth;
    if (level != null) {
      yield* authFields(
        auth: level,
        pathPrefix: 'auth',
        group: 'auth',
        scope: RefactorScope.defaults,
        what: 'Default auth',
        rebuild: (a) => copyWith(auth: a),
      );
    }
    yield* keyValueFields(
      rows: defaults.headers,
      pathPrefix: 'defaults.header',
      group: 'defaults',
      scope: RefactorScope.defaults,
      what: 'Default header',
      rebuild: (rows) => copyWith(defaults: defaults.copyWith(headers: rows)),
    );
    yield* testFields(
      assertions: defaults.assertions,
      extractors: defaults.extractors,
      pathPrefix: 'defaults',
      group: 'defaults',
      scope: RefactorScope.defaults,
      ownerKey: key,
      ownerLabel: 'collection "${shorten(collection.name)}"',
      rebuild: (a, x) => copyWith(defaults: defaults.copyWith(assertions: a, extractors: x)),
    );
  }
}

/// A folder: its name, description and tags, and what it passes down (headers, variables, auth, tests). All of what it
/// passes down is saved in one piece, so it is one group.
final class FolderUnit extends RefactorUnit {
  final FolderEntity folder;
  final String description;
  final List<String> tags;
  final LevelDefaults defaults;

  /// The collection and the folders above this one, outermost first.
  final List<String> parentTrail;

  const FolderUnit({
    required this.folder,
    required this.parentTrail,
    this.description = '',
    this.tags = const [],
    this.defaults = LevelDefaults.empty,
  });

  @override
  UnitKind get kind => UnitKind.folder;

  @override
  int get id => folder.id;

  @override
  List<String> get trail => [...parentTrail, folder.name];

  FolderUnit copyWith({String? name, String? description, List<String>? tags, LevelDefaults? defaults}) => FolderUnit(
    folder: name == null
        ? folder
        : FolderEntity(
            id: folder.id,
            collectionId: folder.collectionId,
            parentFolderId: folder.parentFolderId,
            name: name,
            orderIndex: folder.orderIndex,
          ),
    parentTrail: parentTrail,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    defaults: defaults ?? this.defaults,
  );

  @override
  RefactorUnit removePart(String path) {
    final prefix = 'defaults.var.';
    final index = path.startsWith(prefix) ? int.tryParse(path.substring(prefix.length)) : null;
    if (index == null || index < 0 || index >= defaults.variables.length) throw StateError('$key has no $path');
    return copyWith(defaults: defaults.copyWith(variables: [...defaults.variables]..removeAt(index)));
  }

  @override
  Iterable<UnitField> fields() sync* {
    final where = 'folder "${shorten(trail.skip(1).join(' / '), 48)}"';
    if (folder.name.isNotEmpty) {
      yield UnitField(path: 'name', group: 'name', scope: RefactorScope.names, label: 'Folder name', value: folder.name, write: (v) => copyWith(name: v));
    }
    if (description.isNotEmpty) {
      yield UnitField(path: 'doc', group: 'doc', scope: RefactorScope.docs, label: 'Folder notes', value: description, write: (v) => copyWith(description: v));
    }
    for (var i = 0; i < tags.length; i++) {
      if (tags[i].isEmpty) continue;
      yield UnitField(path: 'tag.$i', group: 'tags', scope: RefactorScope.tags, label: 'Folder tag', value: tags[i], write: (v) => copyWith(tags: replacedAt(tags, i, v)));
    }
    yield* keyValueFields(
      rows: defaults.headers,
      pathPrefix: 'defaults.header',
      group: 'defaults',
      scope: RefactorScope.defaults,
      what: 'Default header',
      rebuild: (rows) => copyWith(defaults: defaults.copyWith(headers: rows)),
    );
    final variables = defaults.variables;
    for (var i = 0; i < variables.length; i++) {
      final v = variables[i];
      UnitField field(String part, String label, String value, DefaultVariable Function(String) change, {bool secret = false, VariableDefinition? defines}) =>
          UnitField(
            path: 'defaults.var.$i.$part',
            group: 'defaults',
            scope: RefactorScope.variables,
            label: label,
            value: value,
            secret: secret,
            defines: defines,
            write: (x) => copyWith(defaults: defaults.copyWith(variables: replacedAt(variables, i, change(x)))),
          );
      if (v.key.isNotEmpty) {
        yield field(
          'key',
          'Folder variable name',
          v.key,
          (x) => v.copyWith(key: x),
          defines: v.key.trim().isEmpty
              ? null
              : VariableDefinition(
                  name: v.key.trim(),
                  home: VariableHome.folder,
                  containerKey: 'folder:$id',
                  where: 'Variables of $where',
                  unitKey: key,
                  keyPath: 'defaults.var.$i.key',
                  removePath: 'defaults.var.$i',
                  value: v.value,
                  secret: v.isSecret,
                  enabled: v.enabled,
                ),
        );
      }
      if (v.value.isNotEmpty) {
        yield field('value', 'Folder variable "${shorten(v.key)}" value', v.value, (x) => v.copyWith(value: x), secret: v.isSecret);
      }
    }
    final level = defaults.auth;
    if (level != null) {
      yield* authFields(
        auth: level,
        pathPrefix: 'defaults.auth',
        group: 'defaults',
        scope: RefactorScope.defaults,
        what: 'Default auth',
        rebuild: (a) => copyWith(defaults: defaults.withAuth(a)),
      );
    }
    yield* testFields(
      assertions: defaults.assertions,
      extractors: defaults.extractors,
      pathPrefix: 'defaults',
      group: 'defaults',
      scope: RefactorScope.defaults,
      ownerKey: key,
      ownerLabel: where,
      rebuild: (a, x) => copyWith(defaults: defaults.copyWith(assertions: a, extractors: x)),
    );
  }
}
