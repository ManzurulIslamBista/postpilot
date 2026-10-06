// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, Collection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _forkedFromIdMeta = const VerificationMeta(
    'forkedFromId',
  );
  @override
  late final GeneratedColumn<int> forkedFromId = GeneratedColumn<int>(
    'forked_from_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, forkedFromId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Collection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('forked_from_id')) {
      context.handle(
        _forkedFromIdMeta,
        forkedFromId.isAcceptableOrUnknown(
          data['forked_from_id']!,
          _forkedFromIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Collection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Collection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      forkedFromId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}forked_from_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }
}

class Collection extends DataClass implements Insertable<Collection> {
  final int id;
  final String name;
  final int? forkedFromId;
  final DateTime createdAt;
  const Collection({
    required this.id,
    required this.name,
    this.forkedFromId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || forkedFromId != null) {
      map['forked_from_id'] = Variable<int>(forkedFromId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      id: Value(id),
      name: Value(name),
      forkedFromId: forkedFromId == null && nullToAbsent
          ? const Value.absent()
          : Value(forkedFromId),
      createdAt: Value(createdAt),
    );
  }

  factory Collection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Collection(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      forkedFromId: serializer.fromJson<int?>(json['forkedFromId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'forkedFromId': serializer.toJson<int?>(forkedFromId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Collection copyWith({
    int? id,
    String? name,
    Value<int?> forkedFromId = const Value.absent(),
    DateTime? createdAt,
  }) => Collection(
    id: id ?? this.id,
    name: name ?? this.name,
    forkedFromId: forkedFromId.present ? forkedFromId.value : this.forkedFromId,
    createdAt: createdAt ?? this.createdAt,
  );
  Collection copyWithCompanion(CollectionsCompanion data) {
    return Collection(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      forkedFromId: data.forkedFromId.present
          ? data.forkedFromId.value
          : this.forkedFromId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Collection(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('forkedFromId: $forkedFromId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, forkedFromId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Collection &&
          other.id == this.id &&
          other.name == this.name &&
          other.forkedFromId == this.forkedFromId &&
          other.createdAt == this.createdAt);
}

class CollectionsCompanion extends UpdateCompanion<Collection> {
  final Value<int> id;
  final Value<String> name;
  final Value<int?> forkedFromId;
  final Value<DateTime> createdAt;
  const CollectionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.forkedFromId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CollectionsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.forkedFromId = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Collection> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? forkedFromId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (forkedFromId != null) 'forked_from_id': forkedFromId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CollectionsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int?>? forkedFromId,
    Value<DateTime>? createdAt,
  }) {
    return CollectionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      forkedFromId: forkedFromId ?? this.forkedFromId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (forkedFromId.present) {
      map['forked_from_id'] = Variable<int>(forkedFromId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('forkedFromId: $forkedFromId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $FoldersTable extends Folders with TableInfo<$FoldersTable, Folder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<int> collectionId = GeneratedColumn<int>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _parentFolderIdMeta = const VerificationMeta(
    'parentFolderId',
  );
  @override
  late final GeneratedColumn<int> parentFolderId = GeneratedColumn<int>(
    'parent_folder_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    collectionId,
    parentFolderId,
    name,
    orderIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Folder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('parent_folder_id')) {
      context.handle(
        _parentFolderIdMeta,
        parentFolderId.isAcceptableOrUnknown(
          data['parent_folder_id']!,
          _parentFolderIdMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Folder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Folder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}collection_id'],
      )!,
      parentFolderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_folder_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class Folder extends DataClass implements Insertable<Folder> {
  final int id;
  final int collectionId;
  final int? parentFolderId;
  final String name;
  final int orderIndex;
  const Folder({
    required this.id,
    required this.collectionId,
    this.parentFolderId,
    required this.name,
    required this.orderIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['collection_id'] = Variable<int>(collectionId);
    if (!nullToAbsent || parentFolderId != null) {
      map['parent_folder_id'] = Variable<int>(parentFolderId);
    }
    map['name'] = Variable<String>(name);
    map['order_index'] = Variable<int>(orderIndex);
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      collectionId: Value(collectionId),
      parentFolderId: parentFolderId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentFolderId),
      name: Value(name),
      orderIndex: Value(orderIndex),
    );
  }

  factory Folder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Folder(
      id: serializer.fromJson<int>(json['id']),
      collectionId: serializer.fromJson<int>(json['collectionId']),
      parentFolderId: serializer.fromJson<int?>(json['parentFolderId']),
      name: serializer.fromJson<String>(json['name']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'collectionId': serializer.toJson<int>(collectionId),
      'parentFolderId': serializer.toJson<int?>(parentFolderId),
      'name': serializer.toJson<String>(name),
      'orderIndex': serializer.toJson<int>(orderIndex),
    };
  }

  Folder copyWith({
    int? id,
    int? collectionId,
    Value<int?> parentFolderId = const Value.absent(),
    String? name,
    int? orderIndex,
  }) => Folder(
    id: id ?? this.id,
    collectionId: collectionId ?? this.collectionId,
    parentFolderId: parentFolderId.present
        ? parentFolderId.value
        : this.parentFolderId,
    name: name ?? this.name,
    orderIndex: orderIndex ?? this.orderIndex,
  );
  Folder copyWithCompanion(FoldersCompanion data) {
    return Folder(
      id: data.id.present ? data.id.value : this.id,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      parentFolderId: data.parentFolderId.present
          ? data.parentFolderId.value
          : this.parentFolderId,
      name: data.name.present ? data.name.value : this.name,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Folder(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('parentFolderId: $parentFolderId, ')
          ..write('name: $name, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, collectionId, parentFolderId, name, orderIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Folder &&
          other.id == this.id &&
          other.collectionId == this.collectionId &&
          other.parentFolderId == this.parentFolderId &&
          other.name == this.name &&
          other.orderIndex == this.orderIndex);
}

class FoldersCompanion extends UpdateCompanion<Folder> {
  final Value<int> id;
  final Value<int> collectionId;
  final Value<int?> parentFolderId;
  final Value<String> name;
  final Value<int> orderIndex;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.parentFolderId = const Value.absent(),
    this.name = const Value.absent(),
    this.orderIndex = const Value.absent(),
  });
  FoldersCompanion.insert({
    this.id = const Value.absent(),
    required int collectionId,
    this.parentFolderId = const Value.absent(),
    required String name,
    this.orderIndex = const Value.absent(),
  }) : collectionId = Value(collectionId),
       name = Value(name);
  static Insertable<Folder> custom({
    Expression<int>? id,
    Expression<int>? collectionId,
    Expression<int>? parentFolderId,
    Expression<String>? name,
    Expression<int>? orderIndex,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collectionId != null) 'collection_id': collectionId,
      if (parentFolderId != null) 'parent_folder_id': parentFolderId,
      if (name != null) 'name': name,
      if (orderIndex != null) 'order_index': orderIndex,
    });
  }

  FoldersCompanion copyWith({
    Value<int>? id,
    Value<int>? collectionId,
    Value<int?>? parentFolderId,
    Value<String>? name,
    Value<int>? orderIndex,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      parentFolderId: parentFolderId ?? this.parentFolderId,
      name: name ?? this.name,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<int>(collectionId.value);
    }
    if (parentFolderId.present) {
      map['parent_folder_id'] = Variable<int>(parentFolderId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('parentFolderId: $parentFolderId, ')
          ..write('name: $name, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }
}

class $RequestsTable extends Requests with TableInfo<$RequestsTable, Request> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<int> collectionId = GeneratedColumn<int>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('get'),
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _headersJsonMeta = const VerificationMeta(
    'headersJson',
  );
  @override
  late final GeneratedColumn<String> headersJson = GeneratedColumn<String>(
    'headers_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _queryParamsJsonMeta = const VerificationMeta(
    'queryParamsJson',
  );
  @override
  late final GeneratedColumn<String> queryParamsJson = GeneratedColumn<String>(
    'query_params_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _bodyTypeMeta = const VerificationMeta(
    'bodyType',
  );
  @override
  late final GeneratedColumn<String> bodyType = GeneratedColumn<String>(
    'body_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _rawContentTypeMeta = const VerificationMeta(
    'rawContentType',
  );
  @override
  late final GeneratedColumn<String> rawContentType = GeneratedColumn<String>(
    'raw_content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('json'),
  );
  static const VerificationMeta _bodyTextMeta = const VerificationMeta(
    'bodyText',
  );
  @override
  late final GeneratedColumn<String> bodyText = GeneratedColumn<String>(
    'body_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _formFieldsJsonMeta = const VerificationMeta(
    'formFieldsJson',
  );
  @override
  late final GeneratedColumn<String> formFieldsJson = GeneratedColumn<String>(
    'form_fields_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _urlEncodedFieldsJsonMeta =
      const VerificationMeta('urlEncodedFieldsJson');
  @override
  late final GeneratedColumn<String> urlEncodedFieldsJson =
      GeneratedColumn<String>(
        'url_encoded_fields_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _graphqlQueryMeta = const VerificationMeta(
    'graphqlQuery',
  );
  @override
  late final GeneratedColumn<String> graphqlQuery = GeneratedColumn<String>(
    'graphql_query',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _graphqlVariablesMeta = const VerificationMeta(
    'graphqlVariables',
  );
  @override
  late final GeneratedColumn<String> graphqlVariables = GeneratedColumn<String>(
    'graphql_variables',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _authTypeMeta = const VerificationMeta(
    'authType',
  );
  @override
  late final GeneratedColumn<String> authType = GeneratedColumn<String>(
    'auth_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('inherit'),
  );
  static const VerificationMeta _authConfigJsonMeta = const VerificationMeta(
    'authConfigJson',
  );
  @override
  late final GeneratedColumn<String> authConfigJson = GeneratedColumn<String>(
    'auth_config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    collectionId,
    folderId,
    name,
    method,
    url,
    headersJson,
    queryParamsJson,
    bodyType,
    rawContentType,
    bodyText,
    formFieldsJson,
    urlEncodedFieldsJson,
    graphqlQuery,
    graphqlVariables,
    authType,
    authConfigJson,
    orderIndex,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<Request> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('headers_json')) {
      context.handle(
        _headersJsonMeta,
        headersJson.isAcceptableOrUnknown(
          data['headers_json']!,
          _headersJsonMeta,
        ),
      );
    }
    if (data.containsKey('query_params_json')) {
      context.handle(
        _queryParamsJsonMeta,
        queryParamsJson.isAcceptableOrUnknown(
          data['query_params_json']!,
          _queryParamsJsonMeta,
        ),
      );
    }
    if (data.containsKey('body_type')) {
      context.handle(
        _bodyTypeMeta,
        bodyType.isAcceptableOrUnknown(data['body_type']!, _bodyTypeMeta),
      );
    }
    if (data.containsKey('raw_content_type')) {
      context.handle(
        _rawContentTypeMeta,
        rawContentType.isAcceptableOrUnknown(
          data['raw_content_type']!,
          _rawContentTypeMeta,
        ),
      );
    }
    if (data.containsKey('body_text')) {
      context.handle(
        _bodyTextMeta,
        bodyText.isAcceptableOrUnknown(data['body_text']!, _bodyTextMeta),
      );
    }
    if (data.containsKey('form_fields_json')) {
      context.handle(
        _formFieldsJsonMeta,
        formFieldsJson.isAcceptableOrUnknown(
          data['form_fields_json']!,
          _formFieldsJsonMeta,
        ),
      );
    }
    if (data.containsKey('url_encoded_fields_json')) {
      context.handle(
        _urlEncodedFieldsJsonMeta,
        urlEncodedFieldsJson.isAcceptableOrUnknown(
          data['url_encoded_fields_json']!,
          _urlEncodedFieldsJsonMeta,
        ),
      );
    }
    if (data.containsKey('graphql_query')) {
      context.handle(
        _graphqlQueryMeta,
        graphqlQuery.isAcceptableOrUnknown(
          data['graphql_query']!,
          _graphqlQueryMeta,
        ),
      );
    }
    if (data.containsKey('graphql_variables')) {
      context.handle(
        _graphqlVariablesMeta,
        graphqlVariables.isAcceptableOrUnknown(
          data['graphql_variables']!,
          _graphqlVariablesMeta,
        ),
      );
    }
    if (data.containsKey('auth_type')) {
      context.handle(
        _authTypeMeta,
        authType.isAcceptableOrUnknown(data['auth_type']!, _authTypeMeta),
      );
    }
    if (data.containsKey('auth_config_json')) {
      context.handle(
        _authConfigJsonMeta,
        authConfigJson.isAcceptableOrUnknown(
          data['auth_config_json']!,
          _authConfigJsonMeta,
        ),
      );
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Request map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Request(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}collection_id'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      headersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}headers_json'],
      )!,
      queryParamsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query_params_json'],
      )!,
      bodyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_type'],
      )!,
      rawContentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_content_type'],
      )!,
      bodyText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_text'],
      )!,
      formFieldsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}form_fields_json'],
      )!,
      urlEncodedFieldsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url_encoded_fields_json'],
      )!,
      graphqlQuery: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}graphql_query'],
      )!,
      graphqlVariables: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}graphql_variables'],
      )!,
      authType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_type'],
      )!,
      authConfigJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_config_json'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RequestsTable createAlias(String alias) {
    return $RequestsTable(attachedDatabase, alias);
  }
}

class Request extends DataClass implements Insertable<Request> {
  final int id;
  final int collectionId;
  final int? folderId;
  final String name;
  final String method;
  final String url;
  final String headersJson;
  final String queryParamsJson;
  final String bodyType;
  final String rawContentType;
  final String bodyText;
  final String formFieldsJson;
  final String urlEncodedFieldsJson;
  final String graphqlQuery;
  final String graphqlVariables;
  final String authType;
  final String authConfigJson;
  final int orderIndex;
  final DateTime updatedAt;
  const Request({
    required this.id,
    required this.collectionId,
    this.folderId,
    required this.name,
    required this.method,
    required this.url,
    required this.headersJson,
    required this.queryParamsJson,
    required this.bodyType,
    required this.rawContentType,
    required this.bodyText,
    required this.formFieldsJson,
    required this.urlEncodedFieldsJson,
    required this.graphqlQuery,
    required this.graphqlVariables,
    required this.authType,
    required this.authConfigJson,
    required this.orderIndex,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['collection_id'] = Variable<int>(collectionId);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<int>(folderId);
    }
    map['name'] = Variable<String>(name);
    map['method'] = Variable<String>(method);
    map['url'] = Variable<String>(url);
    map['headers_json'] = Variable<String>(headersJson);
    map['query_params_json'] = Variable<String>(queryParamsJson);
    map['body_type'] = Variable<String>(bodyType);
    map['raw_content_type'] = Variable<String>(rawContentType);
    map['body_text'] = Variable<String>(bodyText);
    map['form_fields_json'] = Variable<String>(formFieldsJson);
    map['url_encoded_fields_json'] = Variable<String>(urlEncodedFieldsJson);
    map['graphql_query'] = Variable<String>(graphqlQuery);
    map['graphql_variables'] = Variable<String>(graphqlVariables);
    map['auth_type'] = Variable<String>(authType);
    map['auth_config_json'] = Variable<String>(authConfigJson);
    map['order_index'] = Variable<int>(orderIndex);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RequestsCompanion toCompanion(bool nullToAbsent) {
    return RequestsCompanion(
      id: Value(id),
      collectionId: Value(collectionId),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      name: Value(name),
      method: Value(method),
      url: Value(url),
      headersJson: Value(headersJson),
      queryParamsJson: Value(queryParamsJson),
      bodyType: Value(bodyType),
      rawContentType: Value(rawContentType),
      bodyText: Value(bodyText),
      formFieldsJson: Value(formFieldsJson),
      urlEncodedFieldsJson: Value(urlEncodedFieldsJson),
      graphqlQuery: Value(graphqlQuery),
      graphqlVariables: Value(graphqlVariables),
      authType: Value(authType),
      authConfigJson: Value(authConfigJson),
      orderIndex: Value(orderIndex),
      updatedAt: Value(updatedAt),
    );
  }

  factory Request.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Request(
      id: serializer.fromJson<int>(json['id']),
      collectionId: serializer.fromJson<int>(json['collectionId']),
      folderId: serializer.fromJson<int?>(json['folderId']),
      name: serializer.fromJson<String>(json['name']),
      method: serializer.fromJson<String>(json['method']),
      url: serializer.fromJson<String>(json['url']),
      headersJson: serializer.fromJson<String>(json['headersJson']),
      queryParamsJson: serializer.fromJson<String>(json['queryParamsJson']),
      bodyType: serializer.fromJson<String>(json['bodyType']),
      rawContentType: serializer.fromJson<String>(json['rawContentType']),
      bodyText: serializer.fromJson<String>(json['bodyText']),
      formFieldsJson: serializer.fromJson<String>(json['formFieldsJson']),
      urlEncodedFieldsJson: serializer.fromJson<String>(
        json['urlEncodedFieldsJson'],
      ),
      graphqlQuery: serializer.fromJson<String>(json['graphqlQuery']),
      graphqlVariables: serializer.fromJson<String>(json['graphqlVariables']),
      authType: serializer.fromJson<String>(json['authType']),
      authConfigJson: serializer.fromJson<String>(json['authConfigJson']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'collectionId': serializer.toJson<int>(collectionId),
      'folderId': serializer.toJson<int?>(folderId),
      'name': serializer.toJson<String>(name),
      'method': serializer.toJson<String>(method),
      'url': serializer.toJson<String>(url),
      'headersJson': serializer.toJson<String>(headersJson),
      'queryParamsJson': serializer.toJson<String>(queryParamsJson),
      'bodyType': serializer.toJson<String>(bodyType),
      'rawContentType': serializer.toJson<String>(rawContentType),
      'bodyText': serializer.toJson<String>(bodyText),
      'formFieldsJson': serializer.toJson<String>(formFieldsJson),
      'urlEncodedFieldsJson': serializer.toJson<String>(urlEncodedFieldsJson),
      'graphqlQuery': serializer.toJson<String>(graphqlQuery),
      'graphqlVariables': serializer.toJson<String>(graphqlVariables),
      'authType': serializer.toJson<String>(authType),
      'authConfigJson': serializer.toJson<String>(authConfigJson),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Request copyWith({
    int? id,
    int? collectionId,
    Value<int?> folderId = const Value.absent(),
    String? name,
    String? method,
    String? url,
    String? headersJson,
    String? queryParamsJson,
    String? bodyType,
    String? rawContentType,
    String? bodyText,
    String? formFieldsJson,
    String? urlEncodedFieldsJson,
    String? graphqlQuery,
    String? graphqlVariables,
    String? authType,
    String? authConfigJson,
    int? orderIndex,
    DateTime? updatedAt,
  }) => Request(
    id: id ?? this.id,
    collectionId: collectionId ?? this.collectionId,
    folderId: folderId.present ? folderId.value : this.folderId,
    name: name ?? this.name,
    method: method ?? this.method,
    url: url ?? this.url,
    headersJson: headersJson ?? this.headersJson,
    queryParamsJson: queryParamsJson ?? this.queryParamsJson,
    bodyType: bodyType ?? this.bodyType,
    rawContentType: rawContentType ?? this.rawContentType,
    bodyText: bodyText ?? this.bodyText,
    formFieldsJson: formFieldsJson ?? this.formFieldsJson,
    urlEncodedFieldsJson: urlEncodedFieldsJson ?? this.urlEncodedFieldsJson,
    graphqlQuery: graphqlQuery ?? this.graphqlQuery,
    graphqlVariables: graphqlVariables ?? this.graphqlVariables,
    authType: authType ?? this.authType,
    authConfigJson: authConfigJson ?? this.authConfigJson,
    orderIndex: orderIndex ?? this.orderIndex,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Request copyWithCompanion(RequestsCompanion data) {
    return Request(
      id: data.id.present ? data.id.value : this.id,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      name: data.name.present ? data.name.value : this.name,
      method: data.method.present ? data.method.value : this.method,
      url: data.url.present ? data.url.value : this.url,
      headersJson: data.headersJson.present
          ? data.headersJson.value
          : this.headersJson,
      queryParamsJson: data.queryParamsJson.present
          ? data.queryParamsJson.value
          : this.queryParamsJson,
      bodyType: data.bodyType.present ? data.bodyType.value : this.bodyType,
      rawContentType: data.rawContentType.present
          ? data.rawContentType.value
          : this.rawContentType,
      bodyText: data.bodyText.present ? data.bodyText.value : this.bodyText,
      formFieldsJson: data.formFieldsJson.present
          ? data.formFieldsJson.value
          : this.formFieldsJson,
      urlEncodedFieldsJson: data.urlEncodedFieldsJson.present
          ? data.urlEncodedFieldsJson.value
          : this.urlEncodedFieldsJson,
      graphqlQuery: data.graphqlQuery.present
          ? data.graphqlQuery.value
          : this.graphqlQuery,
      graphqlVariables: data.graphqlVariables.present
          ? data.graphqlVariables.value
          : this.graphqlVariables,
      authType: data.authType.present ? data.authType.value : this.authType,
      authConfigJson: data.authConfigJson.present
          ? data.authConfigJson.value
          : this.authConfigJson,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Request(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('folderId: $folderId, ')
          ..write('name: $name, ')
          ..write('method: $method, ')
          ..write('url: $url, ')
          ..write('headersJson: $headersJson, ')
          ..write('queryParamsJson: $queryParamsJson, ')
          ..write('bodyType: $bodyType, ')
          ..write('rawContentType: $rawContentType, ')
          ..write('bodyText: $bodyText, ')
          ..write('formFieldsJson: $formFieldsJson, ')
          ..write('urlEncodedFieldsJson: $urlEncodedFieldsJson, ')
          ..write('graphqlQuery: $graphqlQuery, ')
          ..write('graphqlVariables: $graphqlVariables, ')
          ..write('authType: $authType, ')
          ..write('authConfigJson: $authConfigJson, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    collectionId,
    folderId,
    name,
    method,
    url,
    headersJson,
    queryParamsJson,
    bodyType,
    rawContentType,
    bodyText,
    formFieldsJson,
    urlEncodedFieldsJson,
    graphqlQuery,
    graphqlVariables,
    authType,
    authConfigJson,
    orderIndex,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Request &&
          other.id == this.id &&
          other.collectionId == this.collectionId &&
          other.folderId == this.folderId &&
          other.name == this.name &&
          other.method == this.method &&
          other.url == this.url &&
          other.headersJson == this.headersJson &&
          other.queryParamsJson == this.queryParamsJson &&
          other.bodyType == this.bodyType &&
          other.rawContentType == this.rawContentType &&
          other.bodyText == this.bodyText &&
          other.formFieldsJson == this.formFieldsJson &&
          other.urlEncodedFieldsJson == this.urlEncodedFieldsJson &&
          other.graphqlQuery == this.graphqlQuery &&
          other.graphqlVariables == this.graphqlVariables &&
          other.authType == this.authType &&
          other.authConfigJson == this.authConfigJson &&
          other.orderIndex == this.orderIndex &&
          other.updatedAt == this.updatedAt);
}

class RequestsCompanion extends UpdateCompanion<Request> {
  final Value<int> id;
  final Value<int> collectionId;
  final Value<int?> folderId;
  final Value<String> name;
  final Value<String> method;
  final Value<String> url;
  final Value<String> headersJson;
  final Value<String> queryParamsJson;
  final Value<String> bodyType;
  final Value<String> rawContentType;
  final Value<String> bodyText;
  final Value<String> formFieldsJson;
  final Value<String> urlEncodedFieldsJson;
  final Value<String> graphqlQuery;
  final Value<String> graphqlVariables;
  final Value<String> authType;
  final Value<String> authConfigJson;
  final Value<int> orderIndex;
  final Value<DateTime> updatedAt;
  const RequestsCompanion({
    this.id = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.name = const Value.absent(),
    this.method = const Value.absent(),
    this.url = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.queryParamsJson = const Value.absent(),
    this.bodyType = const Value.absent(),
    this.rawContentType = const Value.absent(),
    this.bodyText = const Value.absent(),
    this.formFieldsJson = const Value.absent(),
    this.urlEncodedFieldsJson = const Value.absent(),
    this.graphqlQuery = const Value.absent(),
    this.graphqlVariables = const Value.absent(),
    this.authType = const Value.absent(),
    this.authConfigJson = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  RequestsCompanion.insert({
    this.id = const Value.absent(),
    required int collectionId,
    this.folderId = const Value.absent(),
    required String name,
    this.method = const Value.absent(),
    this.url = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.queryParamsJson = const Value.absent(),
    this.bodyType = const Value.absent(),
    this.rawContentType = const Value.absent(),
    this.bodyText = const Value.absent(),
    this.formFieldsJson = const Value.absent(),
    this.urlEncodedFieldsJson = const Value.absent(),
    this.graphqlQuery = const Value.absent(),
    this.graphqlVariables = const Value.absent(),
    this.authType = const Value.absent(),
    this.authConfigJson = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : collectionId = Value(collectionId),
       name = Value(name);
  static Insertable<Request> custom({
    Expression<int>? id,
    Expression<int>? collectionId,
    Expression<int>? folderId,
    Expression<String>? name,
    Expression<String>? method,
    Expression<String>? url,
    Expression<String>? headersJson,
    Expression<String>? queryParamsJson,
    Expression<String>? bodyType,
    Expression<String>? rawContentType,
    Expression<String>? bodyText,
    Expression<String>? formFieldsJson,
    Expression<String>? urlEncodedFieldsJson,
    Expression<String>? graphqlQuery,
    Expression<String>? graphqlVariables,
    Expression<String>? authType,
    Expression<String>? authConfigJson,
    Expression<int>? orderIndex,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collectionId != null) 'collection_id': collectionId,
      if (folderId != null) 'folder_id': folderId,
      if (name != null) 'name': name,
      if (method != null) 'method': method,
      if (url != null) 'url': url,
      if (headersJson != null) 'headers_json': headersJson,
      if (queryParamsJson != null) 'query_params_json': queryParamsJson,
      if (bodyType != null) 'body_type': bodyType,
      if (rawContentType != null) 'raw_content_type': rawContentType,
      if (bodyText != null) 'body_text': bodyText,
      if (formFieldsJson != null) 'form_fields_json': formFieldsJson,
      if (urlEncodedFieldsJson != null)
        'url_encoded_fields_json': urlEncodedFieldsJson,
      if (graphqlQuery != null) 'graphql_query': graphqlQuery,
      if (graphqlVariables != null) 'graphql_variables': graphqlVariables,
      if (authType != null) 'auth_type': authType,
      if (authConfigJson != null) 'auth_config_json': authConfigJson,
      if (orderIndex != null) 'order_index': orderIndex,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  RequestsCompanion copyWith({
    Value<int>? id,
    Value<int>? collectionId,
    Value<int?>? folderId,
    Value<String>? name,
    Value<String>? method,
    Value<String>? url,
    Value<String>? headersJson,
    Value<String>? queryParamsJson,
    Value<String>? bodyType,
    Value<String>? rawContentType,
    Value<String>? bodyText,
    Value<String>? formFieldsJson,
    Value<String>? urlEncodedFieldsJson,
    Value<String>? graphqlQuery,
    Value<String>? graphqlVariables,
    Value<String>? authType,
    Value<String>? authConfigJson,
    Value<int>? orderIndex,
    Value<DateTime>? updatedAt,
  }) {
    return RequestsCompanion(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      folderId: folderId ?? this.folderId,
      name: name ?? this.name,
      method: method ?? this.method,
      url: url ?? this.url,
      headersJson: headersJson ?? this.headersJson,
      queryParamsJson: queryParamsJson ?? this.queryParamsJson,
      bodyType: bodyType ?? this.bodyType,
      rawContentType: rawContentType ?? this.rawContentType,
      bodyText: bodyText ?? this.bodyText,
      formFieldsJson: formFieldsJson ?? this.formFieldsJson,
      urlEncodedFieldsJson: urlEncodedFieldsJson ?? this.urlEncodedFieldsJson,
      graphqlQuery: graphqlQuery ?? this.graphqlQuery,
      graphqlVariables: graphqlVariables ?? this.graphqlVariables,
      authType: authType ?? this.authType,
      authConfigJson: authConfigJson ?? this.authConfigJson,
      orderIndex: orderIndex ?? this.orderIndex,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<int>(collectionId.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (headersJson.present) {
      map['headers_json'] = Variable<String>(headersJson.value);
    }
    if (queryParamsJson.present) {
      map['query_params_json'] = Variable<String>(queryParamsJson.value);
    }
    if (bodyType.present) {
      map['body_type'] = Variable<String>(bodyType.value);
    }
    if (rawContentType.present) {
      map['raw_content_type'] = Variable<String>(rawContentType.value);
    }
    if (bodyText.present) {
      map['body_text'] = Variable<String>(bodyText.value);
    }
    if (formFieldsJson.present) {
      map['form_fields_json'] = Variable<String>(formFieldsJson.value);
    }
    if (urlEncodedFieldsJson.present) {
      map['url_encoded_fields_json'] = Variable<String>(
        urlEncodedFieldsJson.value,
      );
    }
    if (graphqlQuery.present) {
      map['graphql_query'] = Variable<String>(graphqlQuery.value);
    }
    if (graphqlVariables.present) {
      map['graphql_variables'] = Variable<String>(graphqlVariables.value);
    }
    if (authType.present) {
      map['auth_type'] = Variable<String>(authType.value);
    }
    if (authConfigJson.present) {
      map['auth_config_json'] = Variable<String>(authConfigJson.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RequestsCompanion(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('folderId: $folderId, ')
          ..write('name: $name, ')
          ..write('method: $method, ')
          ..write('url: $url, ')
          ..write('headersJson: $headersJson, ')
          ..write('queryParamsJson: $queryParamsJson, ')
          ..write('bodyType: $bodyType, ')
          ..write('rawContentType: $rawContentType, ')
          ..write('bodyText: $bodyText, ')
          ..write('formFieldsJson: $formFieldsJson, ')
          ..write('urlEncodedFieldsJson: $urlEncodedFieldsJson, ')
          ..write('graphqlQuery: $graphqlQuery, ')
          ..write('graphqlVariables: $graphqlVariables, ')
          ..write('authType: $authType, ')
          ..write('authConfigJson: $authConfigJson, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $EnvironmentsTable extends Environments
    with TableInfo<$EnvironmentsTable, Environment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EnvironmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, isActive];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'environments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Environment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Environment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Environment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $EnvironmentsTable createAlias(String alias) {
    return $EnvironmentsTable(attachedDatabase, alias);
  }
}

class Environment extends DataClass implements Insertable<Environment> {
  final int id;
  final String name;
  final bool isActive;
  const Environment({
    required this.id,
    required this.name,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  EnvironmentsCompanion toCompanion(bool nullToAbsent) {
    return EnvironmentsCompanion(
      id: Value(id),
      name: Value(name),
      isActive: Value(isActive),
    );
  }

  factory Environment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Environment(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  Environment copyWith({int? id, String? name, bool? isActive}) => Environment(
    id: id ?? this.id,
    name: name ?? this.name,
    isActive: isActive ?? this.isActive,
  );
  Environment copyWithCompanion(EnvironmentsCompanion data) {
    return Environment(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Environment(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Environment &&
          other.id == this.id &&
          other.name == this.name &&
          other.isActive == this.isActive);
}

class EnvironmentsCompanion extends UpdateCompanion<Environment> {
  final Value<int> id;
  final Value<String> name;
  final Value<bool> isActive;
  const EnvironmentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isActive = const Value.absent(),
  });
  EnvironmentsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.isActive = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Environment> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? isActive,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isActive != null) 'is_active': isActive,
    });
  }

  EnvironmentsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<bool>? isActive,
  }) {
    return EnvironmentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EnvironmentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }
}

class $EnvironmentVariablesTable extends EnvironmentVariables
    with TableInfo<$EnvironmentVariablesTable, EnvironmentVariable> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EnvironmentVariablesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _environmentIdMeta = const VerificationMeta(
    'environmentId',
  );
  @override
  late final GeneratedColumn<int> environmentId = GeneratedColumn<int>(
    'environment_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES environments (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isSecretMeta = const VerificationMeta(
    'isSecret',
  );
  @override
  late final GeneratedColumn<bool> isSecret = GeneratedColumn<bool>(
    'is_secret',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_secret" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    environmentId,
    key,
    value,
    isSecret,
    enabled,
    orderIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'environment_variables';
  @override
  VerificationContext validateIntegrity(
    Insertable<EnvironmentVariable> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('environment_id')) {
      context.handle(
        _environmentIdMeta,
        environmentId.isAcceptableOrUnknown(
          data['environment_id']!,
          _environmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_environmentIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('is_secret')) {
      context.handle(
        _isSecretMeta,
        isSecret.isAcceptableOrUnknown(data['is_secret']!, _isSecretMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EnvironmentVariable map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EnvironmentVariable(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      environmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}environment_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      isSecret: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_secret'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
    );
  }

  @override
  $EnvironmentVariablesTable createAlias(String alias) {
    return $EnvironmentVariablesTable(attachedDatabase, alias);
  }
}

class EnvironmentVariable extends DataClass
    implements Insertable<EnvironmentVariable> {
  final int id;
  final int environmentId;
  final String key;
  final String value;
  final bool isSecret;
  final bool enabled;
  final int orderIndex;
  const EnvironmentVariable({
    required this.id,
    required this.environmentId,
    required this.key,
    required this.value,
    required this.isSecret,
    required this.enabled,
    required this.orderIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['environment_id'] = Variable<int>(environmentId);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['is_secret'] = Variable<bool>(isSecret);
    map['enabled'] = Variable<bool>(enabled);
    map['order_index'] = Variable<int>(orderIndex);
    return map;
  }

  EnvironmentVariablesCompanion toCompanion(bool nullToAbsent) {
    return EnvironmentVariablesCompanion(
      id: Value(id),
      environmentId: Value(environmentId),
      key: Value(key),
      value: Value(value),
      isSecret: Value(isSecret),
      enabled: Value(enabled),
      orderIndex: Value(orderIndex),
    );
  }

  factory EnvironmentVariable.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EnvironmentVariable(
      id: serializer.fromJson<int>(json['id']),
      environmentId: serializer.fromJson<int>(json['environmentId']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      isSecret: serializer.fromJson<bool>(json['isSecret']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'environmentId': serializer.toJson<int>(environmentId),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'isSecret': serializer.toJson<bool>(isSecret),
      'enabled': serializer.toJson<bool>(enabled),
      'orderIndex': serializer.toJson<int>(orderIndex),
    };
  }

  EnvironmentVariable copyWith({
    int? id,
    int? environmentId,
    String? key,
    String? value,
    bool? isSecret,
    bool? enabled,
    int? orderIndex,
  }) => EnvironmentVariable(
    id: id ?? this.id,
    environmentId: environmentId ?? this.environmentId,
    key: key ?? this.key,
    value: value ?? this.value,
    isSecret: isSecret ?? this.isSecret,
    enabled: enabled ?? this.enabled,
    orderIndex: orderIndex ?? this.orderIndex,
  );
  EnvironmentVariable copyWithCompanion(EnvironmentVariablesCompanion data) {
    return EnvironmentVariable(
      id: data.id.present ? data.id.value : this.id,
      environmentId: data.environmentId.present
          ? data.environmentId.value
          : this.environmentId,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      isSecret: data.isSecret.present ? data.isSecret.value : this.isSecret,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EnvironmentVariable(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('isSecret: $isSecret, ')
          ..write('enabled: $enabled, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, environmentId, key, value, isSecret, enabled, orderIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EnvironmentVariable &&
          other.id == this.id &&
          other.environmentId == this.environmentId &&
          other.key == this.key &&
          other.value == this.value &&
          other.isSecret == this.isSecret &&
          other.enabled == this.enabled &&
          other.orderIndex == this.orderIndex);
}

class EnvironmentVariablesCompanion
    extends UpdateCompanion<EnvironmentVariable> {
  final Value<int> id;
  final Value<int> environmentId;
  final Value<String> key;
  final Value<String> value;
  final Value<bool> isSecret;
  final Value<bool> enabled;
  final Value<int> orderIndex;
  const EnvironmentVariablesCompanion({
    this.id = const Value.absent(),
    this.environmentId = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.isSecret = const Value.absent(),
    this.enabled = const Value.absent(),
    this.orderIndex = const Value.absent(),
  });
  EnvironmentVariablesCompanion.insert({
    this.id = const Value.absent(),
    required int environmentId,
    required String key,
    this.value = const Value.absent(),
    this.isSecret = const Value.absent(),
    this.enabled = const Value.absent(),
    this.orderIndex = const Value.absent(),
  }) : environmentId = Value(environmentId),
       key = Value(key);
  static Insertable<EnvironmentVariable> custom({
    Expression<int>? id,
    Expression<int>? environmentId,
    Expression<String>? key,
    Expression<String>? value,
    Expression<bool>? isSecret,
    Expression<bool>? enabled,
    Expression<int>? orderIndex,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (environmentId != null) 'environment_id': environmentId,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (isSecret != null) 'is_secret': isSecret,
      if (enabled != null) 'enabled': enabled,
      if (orderIndex != null) 'order_index': orderIndex,
    });
  }

  EnvironmentVariablesCompanion copyWith({
    Value<int>? id,
    Value<int>? environmentId,
    Value<String>? key,
    Value<String>? value,
    Value<bool>? isSecret,
    Value<bool>? enabled,
    Value<int>? orderIndex,
  }) {
    return EnvironmentVariablesCompanion(
      id: id ?? this.id,
      environmentId: environmentId ?? this.environmentId,
      key: key ?? this.key,
      value: value ?? this.value,
      isSecret: isSecret ?? this.isSecret,
      enabled: enabled ?? this.enabled,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (environmentId.present) {
      map['environment_id'] = Variable<int>(environmentId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (isSecret.present) {
      map['is_secret'] = Variable<bool>(isSecret.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EnvironmentVariablesCompanion(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('isSecret: $isSecret, ')
          ..write('enabled: $enabled, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }
}

class $HistoryEntriesTable extends HistoryEntries
    with TableInfo<$HistoryEntriesTable, HistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<int> requestId = GeneratedColumn<int>(
    'request_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusCodeMeta = const VerificationMeta(
    'statusCode',
  );
  @override
  late final GeneratedColumn<int> statusCode = GeneratedColumn<int>(
    'status_code',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _responseHeadersJsonMeta =
      const VerificationMeta('responseHeadersJson');
  @override
  late final GeneratedColumn<String> responseHeadersJson =
      GeneratedColumn<String>(
        'response_headers_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      );
  static const VerificationMeta _responseBodyMeta = const VerificationMeta(
    'responseBody',
  );
  @override
  late final GeneratedColumn<Uint8List> responseBody =
      GeneratedColumn<Uint8List>(
        'response_body',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    requestId,
    method,
    url,
    statusCode,
    durationMs,
    responseHeadersJson,
    responseBody,
    sentAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('status_code')) {
      context.handle(
        _statusCodeMeta,
        statusCode.isAcceptableOrUnknown(data['status_code']!, _statusCodeMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('response_headers_json')) {
      context.handle(
        _responseHeadersJsonMeta,
        responseHeadersJson.isAcceptableOrUnknown(
          data['response_headers_json']!,
          _responseHeadersJsonMeta,
        ),
      );
    }
    if (data.containsKey('response_body')) {
      context.handle(
        _responseBodyMeta,
        responseBody.isAcceptableOrUnknown(
          data['response_body']!,
          _responseBodyMeta,
        ),
      );
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}request_id'],
      ),
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      statusCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status_code'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      responseHeadersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}response_headers_json'],
      )!,
      responseBody: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}response_body'],
      ),
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      )!,
    );
  }

  @override
  $HistoryEntriesTable createAlias(String alias) {
    return $HistoryEntriesTable(attachedDatabase, alias);
  }
}

class HistoryEntry extends DataClass implements Insertable<HistoryEntry> {
  final int id;
  final int? requestId;
  final String method;
  final String url;
  final int? statusCode;
  final int? durationMs;
  final String responseHeadersJson;
  final Uint8List? responseBody;
  final DateTime sentAt;
  const HistoryEntry({
    required this.id,
    this.requestId,
    required this.method,
    required this.url,
    this.statusCode,
    this.durationMs,
    required this.responseHeadersJson,
    this.responseBody,
    required this.sentAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || requestId != null) {
      map['request_id'] = Variable<int>(requestId);
    }
    map['method'] = Variable<String>(method);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || statusCode != null) {
      map['status_code'] = Variable<int>(statusCode);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['response_headers_json'] = Variable<String>(responseHeadersJson);
    if (!nullToAbsent || responseBody != null) {
      map['response_body'] = Variable<Uint8List>(responseBody);
    }
    map['sent_at'] = Variable<DateTime>(sentAt);
    return map;
  }

  HistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return HistoryEntriesCompanion(
      id: Value(id),
      requestId: requestId == null && nullToAbsent
          ? const Value.absent()
          : Value(requestId),
      method: Value(method),
      url: Value(url),
      statusCode: statusCode == null && nullToAbsent
          ? const Value.absent()
          : Value(statusCode),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      responseHeadersJson: Value(responseHeadersJson),
      responseBody: responseBody == null && nullToAbsent
          ? const Value.absent()
          : Value(responseBody),
      sentAt: Value(sentAt),
    );
  }

  factory HistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      requestId: serializer.fromJson<int?>(json['requestId']),
      method: serializer.fromJson<String>(json['method']),
      url: serializer.fromJson<String>(json['url']),
      statusCode: serializer.fromJson<int?>(json['statusCode']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      responseHeadersJson: serializer.fromJson<String>(
        json['responseHeadersJson'],
      ),
      responseBody: serializer.fromJson<Uint8List?>(json['responseBody']),
      sentAt: serializer.fromJson<DateTime>(json['sentAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'requestId': serializer.toJson<int?>(requestId),
      'method': serializer.toJson<String>(method),
      'url': serializer.toJson<String>(url),
      'statusCode': serializer.toJson<int?>(statusCode),
      'durationMs': serializer.toJson<int?>(durationMs),
      'responseHeadersJson': serializer.toJson<String>(responseHeadersJson),
      'responseBody': serializer.toJson<Uint8List?>(responseBody),
      'sentAt': serializer.toJson<DateTime>(sentAt),
    };
  }

  HistoryEntry copyWith({
    int? id,
    Value<int?> requestId = const Value.absent(),
    String? method,
    String? url,
    Value<int?> statusCode = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    String? responseHeadersJson,
    Value<Uint8List?> responseBody = const Value.absent(),
    DateTime? sentAt,
  }) => HistoryEntry(
    id: id ?? this.id,
    requestId: requestId.present ? requestId.value : this.requestId,
    method: method ?? this.method,
    url: url ?? this.url,
    statusCode: statusCode.present ? statusCode.value : this.statusCode,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    responseHeadersJson: responseHeadersJson ?? this.responseHeadersJson,
    responseBody: responseBody.present ? responseBody.value : this.responseBody,
    sentAt: sentAt ?? this.sentAt,
  );
  HistoryEntry copyWithCompanion(HistoryEntriesCompanion data) {
    return HistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      method: data.method.present ? data.method.value : this.method,
      url: data.url.present ? data.url.value : this.url,
      statusCode: data.statusCode.present
          ? data.statusCode.value
          : this.statusCode,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      responseHeadersJson: data.responseHeadersJson.present
          ? data.responseHeadersJson.value
          : this.responseHeadersJson,
      responseBody: data.responseBody.present
          ? data.responseBody.value
          : this.responseBody,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntry(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('method: $method, ')
          ..write('url: $url, ')
          ..write('statusCode: $statusCode, ')
          ..write('durationMs: $durationMs, ')
          ..write('responseHeadersJson: $responseHeadersJson, ')
          ..write('responseBody: $responseBody, ')
          ..write('sentAt: $sentAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    requestId,
    method,
    url,
    statusCode,
    durationMs,
    responseHeadersJson,
    $driftBlobEquality.hash(responseBody),
    sentAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryEntry &&
          other.id == this.id &&
          other.requestId == this.requestId &&
          other.method == this.method &&
          other.url == this.url &&
          other.statusCode == this.statusCode &&
          other.durationMs == this.durationMs &&
          other.responseHeadersJson == this.responseHeadersJson &&
          $driftBlobEquality.equals(other.responseBody, this.responseBody) &&
          other.sentAt == this.sentAt);
}

class HistoryEntriesCompanion extends UpdateCompanion<HistoryEntry> {
  final Value<int> id;
  final Value<int?> requestId;
  final Value<String> method;
  final Value<String> url;
  final Value<int?> statusCode;
  final Value<int?> durationMs;
  final Value<String> responseHeadersJson;
  final Value<Uint8List?> responseBody;
  final Value<DateTime> sentAt;
  const HistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.requestId = const Value.absent(),
    this.method = const Value.absent(),
    this.url = const Value.absent(),
    this.statusCode = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.responseHeadersJson = const Value.absent(),
    this.responseBody = const Value.absent(),
    this.sentAt = const Value.absent(),
  });
  HistoryEntriesCompanion.insert({
    this.id = const Value.absent(),
    this.requestId = const Value.absent(),
    required String method,
    required String url,
    this.statusCode = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.responseHeadersJson = const Value.absent(),
    this.responseBody = const Value.absent(),
    this.sentAt = const Value.absent(),
  }) : method = Value(method),
       url = Value(url);
  static Insertable<HistoryEntry> custom({
    Expression<int>? id,
    Expression<int>? requestId,
    Expression<String>? method,
    Expression<String>? url,
    Expression<int>? statusCode,
    Expression<int>? durationMs,
    Expression<String>? responseHeadersJson,
    Expression<Uint8List>? responseBody,
    Expression<DateTime>? sentAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (requestId != null) 'request_id': requestId,
      if (method != null) 'method': method,
      if (url != null) 'url': url,
      if (statusCode != null) 'status_code': statusCode,
      if (durationMs != null) 'duration_ms': durationMs,
      if (responseHeadersJson != null)
        'response_headers_json': responseHeadersJson,
      if (responseBody != null) 'response_body': responseBody,
      if (sentAt != null) 'sent_at': sentAt,
    });
  }

  HistoryEntriesCompanion copyWith({
    Value<int>? id,
    Value<int?>? requestId,
    Value<String>? method,
    Value<String>? url,
    Value<int?>? statusCode,
    Value<int?>? durationMs,
    Value<String>? responseHeadersJson,
    Value<Uint8List?>? responseBody,
    Value<DateTime>? sentAt,
  }) {
    return HistoryEntriesCompanion(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      method: method ?? this.method,
      url: url ?? this.url,
      statusCode: statusCode ?? this.statusCode,
      durationMs: durationMs ?? this.durationMs,
      responseHeadersJson: responseHeadersJson ?? this.responseHeadersJson,
      responseBody: responseBody ?? this.responseBody,
      sentAt: sentAt ?? this.sentAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<int>(requestId.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (statusCode.present) {
      map['status_code'] = Variable<int>(statusCode.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (responseHeadersJson.present) {
      map['response_headers_json'] = Variable<String>(
        responseHeadersJson.value,
      );
    }
    if (responseBody.present) {
      map['response_body'] = Variable<Uint8List>(responseBody.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('method: $method, ')
          ..write('url: $url, ')
          ..write('statusCode: $statusCode, ')
          ..write('durationMs: $durationMs, ')
          ..write('responseHeadersJson: $responseHeadersJson, ')
          ..write('responseBody: $responseBody, ')
          ..write('sentAt: $sentAt')
          ..write(')'))
        .toString();
  }
}

class $GlobalVariablesTable extends GlobalVariables
    with TableInfo<$GlobalVariablesTable, GlobalVariable> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GlobalVariablesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isSecretMeta = const VerificationMeta(
    'isSecret',
  );
  @override
  late final GeneratedColumn<bool> isSecret = GeneratedColumn<bool>(
    'is_secret',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_secret" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [id, key, value, isSecret, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'global_variables';
  @override
  VerificationContext validateIntegrity(
    Insertable<GlobalVariable> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('is_secret')) {
      context.handle(
        _isSecretMeta,
        isSecret.isAcceptableOrUnknown(data['is_secret']!, _isSecretMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GlobalVariable map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GlobalVariable(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      isSecret: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_secret'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
    );
  }

  @override
  $GlobalVariablesTable createAlias(String alias) {
    return $GlobalVariablesTable(attachedDatabase, alias);
  }
}

class GlobalVariable extends DataClass implements Insertable<GlobalVariable> {
  final int id;
  final String key;
  final String value;
  final bool isSecret;
  final bool enabled;
  const GlobalVariable({
    required this.id,
    required this.key,
    required this.value,
    required this.isSecret,
    required this.enabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['is_secret'] = Variable<bool>(isSecret);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  GlobalVariablesCompanion toCompanion(bool nullToAbsent) {
    return GlobalVariablesCompanion(
      id: Value(id),
      key: Value(key),
      value: Value(value),
      isSecret: Value(isSecret),
      enabled: Value(enabled),
    );
  }

  factory GlobalVariable.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GlobalVariable(
      id: serializer.fromJson<int>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      isSecret: serializer.fromJson<bool>(json['isSecret']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'isSecret': serializer.toJson<bool>(isSecret),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  GlobalVariable copyWith({
    int? id,
    String? key,
    String? value,
    bool? isSecret,
    bool? enabled,
  }) => GlobalVariable(
    id: id ?? this.id,
    key: key ?? this.key,
    value: value ?? this.value,
    isSecret: isSecret ?? this.isSecret,
    enabled: enabled ?? this.enabled,
  );
  GlobalVariable copyWithCompanion(GlobalVariablesCompanion data) {
    return GlobalVariable(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      isSecret: data.isSecret.present ? data.isSecret.value : this.isSecret,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GlobalVariable(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('isSecret: $isSecret, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, key, value, isSecret, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GlobalVariable &&
          other.id == this.id &&
          other.key == this.key &&
          other.value == this.value &&
          other.isSecret == this.isSecret &&
          other.enabled == this.enabled);
}

class GlobalVariablesCompanion extends UpdateCompanion<GlobalVariable> {
  final Value<int> id;
  final Value<String> key;
  final Value<String> value;
  final Value<bool> isSecret;
  final Value<bool> enabled;
  const GlobalVariablesCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.isSecret = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  GlobalVariablesCompanion.insert({
    this.id = const Value.absent(),
    required String key,
    this.value = const Value.absent(),
    this.isSecret = const Value.absent(),
    this.enabled = const Value.absent(),
  }) : key = Value(key);
  static Insertable<GlobalVariable> custom({
    Expression<int>? id,
    Expression<String>? key,
    Expression<String>? value,
    Expression<bool>? isSecret,
    Expression<bool>? enabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (isSecret != null) 'is_secret': isSecret,
      if (enabled != null) 'enabled': enabled,
    });
  }

  GlobalVariablesCompanion copyWith({
    Value<int>? id,
    Value<String>? key,
    Value<String>? value,
    Value<bool>? isSecret,
    Value<bool>? enabled,
  }) {
    return GlobalVariablesCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      value: value ?? this.value,
      isSecret: isSecret ?? this.isSecret,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (isSecret.present) {
      map['is_secret'] = Variable<bool>(isSecret.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GlobalVariablesCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('isSecret: $isSecret, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }
}

class $CollectionVariablesTable extends CollectionVariables
    with TableInfo<$CollectionVariablesTable, CollectionVariable> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionVariablesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<int> collectionId = GeneratedColumn<int>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [id, collectionId, key, value, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection_variables';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionVariable> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CollectionVariable map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionVariable(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}collection_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
    );
  }

  @override
  $CollectionVariablesTable createAlias(String alias) {
    return $CollectionVariablesTable(attachedDatabase, alias);
  }
}

class CollectionVariable extends DataClass
    implements Insertable<CollectionVariable> {
  final int id;
  final int collectionId;
  final String key;
  final String value;
  final bool enabled;
  const CollectionVariable({
    required this.id,
    required this.collectionId,
    required this.key,
    required this.value,
    required this.enabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['collection_id'] = Variable<int>(collectionId);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  CollectionVariablesCompanion toCompanion(bool nullToAbsent) {
    return CollectionVariablesCompanion(
      id: Value(id),
      collectionId: Value(collectionId),
      key: Value(key),
      value: Value(value),
      enabled: Value(enabled),
    );
  }

  factory CollectionVariable.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionVariable(
      id: serializer.fromJson<int>(json['id']),
      collectionId: serializer.fromJson<int>(json['collectionId']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'collectionId': serializer.toJson<int>(collectionId),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  CollectionVariable copyWith({
    int? id,
    int? collectionId,
    String? key,
    String? value,
    bool? enabled,
  }) => CollectionVariable(
    id: id ?? this.id,
    collectionId: collectionId ?? this.collectionId,
    key: key ?? this.key,
    value: value ?? this.value,
    enabled: enabled ?? this.enabled,
  );
  CollectionVariable copyWithCompanion(CollectionVariablesCompanion data) {
    return CollectionVariable(
      id: data.id.present ? data.id.value : this.id,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionVariable(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, collectionId, key, value, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionVariable &&
          other.id == this.id &&
          other.collectionId == this.collectionId &&
          other.key == this.key &&
          other.value == this.value &&
          other.enabled == this.enabled);
}

class CollectionVariablesCompanion extends UpdateCompanion<CollectionVariable> {
  final Value<int> id;
  final Value<int> collectionId;
  final Value<String> key;
  final Value<String> value;
  final Value<bool> enabled;
  const CollectionVariablesCompanion({
    this.id = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  CollectionVariablesCompanion.insert({
    this.id = const Value.absent(),
    required int collectionId,
    required String key,
    this.value = const Value.absent(),
    this.enabled = const Value.absent(),
  }) : collectionId = Value(collectionId),
       key = Value(key);
  static Insertable<CollectionVariable> custom({
    Expression<int>? id,
    Expression<int>? collectionId,
    Expression<String>? key,
    Expression<String>? value,
    Expression<bool>? enabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collectionId != null) 'collection_id': collectionId,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (enabled != null) 'enabled': enabled,
    });
  }

  CollectionVariablesCompanion copyWith({
    Value<int>? id,
    Value<int>? collectionId,
    Value<String>? key,
    Value<String>? value,
    Value<bool>? enabled,
  }) {
    return CollectionVariablesCompanion(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      key: key ?? this.key,
      value: value ?? this.value,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<int>(collectionId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionVariablesCompanion(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }
}

class $CollectionAuthTable extends CollectionAuth
    with TableInfo<$CollectionAuthTable, CollectionAuthData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionAuthTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<int> collectionId = GeneratedColumn<int>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _authJsonMeta = const VerificationMeta(
    'authJson',
  );
  @override
  late final GeneratedColumn<String> authJson = GeneratedColumn<String>(
    'auth_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [collectionId, authJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection_auth';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionAuthData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    }
    if (data.containsKey('auth_json')) {
      context.handle(
        _authJsonMeta,
        authJson.isAcceptableOrUnknown(data['auth_json']!, _authJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {collectionId};
  @override
  CollectionAuthData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionAuthData(
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}collection_id'],
      )!,
      authJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_json'],
      )!,
    );
  }

  @override
  $CollectionAuthTable createAlias(String alias) {
    return $CollectionAuthTable(attachedDatabase, alias);
  }
}

class CollectionAuthData extends DataClass
    implements Insertable<CollectionAuthData> {
  final int collectionId;
  final String authJson;
  const CollectionAuthData({
    required this.collectionId,
    required this.authJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['collection_id'] = Variable<int>(collectionId);
    map['auth_json'] = Variable<String>(authJson);
    return map;
  }

  CollectionAuthCompanion toCompanion(bool nullToAbsent) {
    return CollectionAuthCompanion(
      collectionId: Value(collectionId),
      authJson: Value(authJson),
    );
  }

  factory CollectionAuthData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionAuthData(
      collectionId: serializer.fromJson<int>(json['collectionId']),
      authJson: serializer.fromJson<String>(json['authJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'collectionId': serializer.toJson<int>(collectionId),
      'authJson': serializer.toJson<String>(authJson),
    };
  }

  CollectionAuthData copyWith({int? collectionId, String? authJson}) =>
      CollectionAuthData(
        collectionId: collectionId ?? this.collectionId,
        authJson: authJson ?? this.authJson,
      );
  CollectionAuthData copyWithCompanion(CollectionAuthCompanion data) {
    return CollectionAuthData(
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      authJson: data.authJson.present ? data.authJson.value : this.authJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionAuthData(')
          ..write('collectionId: $collectionId, ')
          ..write('authJson: $authJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(collectionId, authJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionAuthData &&
          other.collectionId == this.collectionId &&
          other.authJson == this.authJson);
}

class CollectionAuthCompanion extends UpdateCompanion<CollectionAuthData> {
  final Value<int> collectionId;
  final Value<String> authJson;
  const CollectionAuthCompanion({
    this.collectionId = const Value.absent(),
    this.authJson = const Value.absent(),
  });
  CollectionAuthCompanion.insert({
    this.collectionId = const Value.absent(),
    this.authJson = const Value.absent(),
  });
  static Insertable<CollectionAuthData> custom({
    Expression<int>? collectionId,
    Expression<String>? authJson,
  }) {
    return RawValuesInsertable({
      if (collectionId != null) 'collection_id': collectionId,
      if (authJson != null) 'auth_json': authJson,
    });
  }

  CollectionAuthCompanion copyWith({
    Value<int>? collectionId,
    Value<String>? authJson,
  }) {
    return CollectionAuthCompanion(
      collectionId: collectionId ?? this.collectionId,
      authJson: authJson ?? this.authJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (collectionId.present) {
      map['collection_id'] = Variable<int>(collectionId.value);
    }
    if (authJson.present) {
      map['auth_json'] = Variable<String>(authJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionAuthCompanion(')
          ..write('collectionId: $collectionId, ')
          ..write('authJson: $authJson')
          ..write(')'))
        .toString();
  }
}

class $RequestScriptsTable extends RequestScripts
    with TableInfo<$RequestScriptsTable, RequestScript> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RequestScriptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<int> requestId = GeneratedColumn<int>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES requests (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _assertionsJsonMeta = const VerificationMeta(
    'assertionsJson',
  );
  @override
  late final GeneratedColumn<String> assertionsJson = GeneratedColumn<String>(
    'assertions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _extractorsJsonMeta = const VerificationMeta(
    'extractorsJson',
  );
  @override
  late final GeneratedColumn<String> extractorsJson = GeneratedColumn<String>(
    'extractors_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    requestId,
    assertionsJson,
    extractorsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'request_scripts';
  @override
  VerificationContext validateIntegrity(
    Insertable<RequestScript> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('assertions_json')) {
      context.handle(
        _assertionsJsonMeta,
        assertionsJson.isAcceptableOrUnknown(
          data['assertions_json']!,
          _assertionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('extractors_json')) {
      context.handle(
        _extractorsJsonMeta,
        extractorsJson.isAcceptableOrUnknown(
          data['extractors_json']!,
          _extractorsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {requestId};
  @override
  RequestScript map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RequestScript(
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}request_id'],
      )!,
      assertionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assertions_json'],
      )!,
      extractorsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extractors_json'],
      )!,
    );
  }

  @override
  $RequestScriptsTable createAlias(String alias) {
    return $RequestScriptsTable(attachedDatabase, alias);
  }
}

class RequestScript extends DataClass implements Insertable<RequestScript> {
  final int requestId;
  final String assertionsJson;
  final String extractorsJson;
  const RequestScript({
    required this.requestId,
    required this.assertionsJson,
    required this.extractorsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['request_id'] = Variable<int>(requestId);
    map['assertions_json'] = Variable<String>(assertionsJson);
    map['extractors_json'] = Variable<String>(extractorsJson);
    return map;
  }

  RequestScriptsCompanion toCompanion(bool nullToAbsent) {
    return RequestScriptsCompanion(
      requestId: Value(requestId),
      assertionsJson: Value(assertionsJson),
      extractorsJson: Value(extractorsJson),
    );
  }

  factory RequestScript.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RequestScript(
      requestId: serializer.fromJson<int>(json['requestId']),
      assertionsJson: serializer.fromJson<String>(json['assertionsJson']),
      extractorsJson: serializer.fromJson<String>(json['extractorsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'requestId': serializer.toJson<int>(requestId),
      'assertionsJson': serializer.toJson<String>(assertionsJson),
      'extractorsJson': serializer.toJson<String>(extractorsJson),
    };
  }

  RequestScript copyWith({
    int? requestId,
    String? assertionsJson,
    String? extractorsJson,
  }) => RequestScript(
    requestId: requestId ?? this.requestId,
    assertionsJson: assertionsJson ?? this.assertionsJson,
    extractorsJson: extractorsJson ?? this.extractorsJson,
  );
  RequestScript copyWithCompanion(RequestScriptsCompanion data) {
    return RequestScript(
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      assertionsJson: data.assertionsJson.present
          ? data.assertionsJson.value
          : this.assertionsJson,
      extractorsJson: data.extractorsJson.present
          ? data.extractorsJson.value
          : this.extractorsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RequestScript(')
          ..write('requestId: $requestId, ')
          ..write('assertionsJson: $assertionsJson, ')
          ..write('extractorsJson: $extractorsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(requestId, assertionsJson, extractorsJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestScript &&
          other.requestId == this.requestId &&
          other.assertionsJson == this.assertionsJson &&
          other.extractorsJson == this.extractorsJson);
}

class RequestScriptsCompanion extends UpdateCompanion<RequestScript> {
  final Value<int> requestId;
  final Value<String> assertionsJson;
  final Value<String> extractorsJson;
  const RequestScriptsCompanion({
    this.requestId = const Value.absent(),
    this.assertionsJson = const Value.absent(),
    this.extractorsJson = const Value.absent(),
  });
  RequestScriptsCompanion.insert({
    this.requestId = const Value.absent(),
    this.assertionsJson = const Value.absent(),
    this.extractorsJson = const Value.absent(),
  });
  static Insertable<RequestScript> custom({
    Expression<int>? requestId,
    Expression<String>? assertionsJson,
    Expression<String>? extractorsJson,
  }) {
    return RawValuesInsertable({
      if (requestId != null) 'request_id': requestId,
      if (assertionsJson != null) 'assertions_json': assertionsJson,
      if (extractorsJson != null) 'extractors_json': extractorsJson,
    });
  }

  RequestScriptsCompanion copyWith({
    Value<int>? requestId,
    Value<String>? assertionsJson,
    Value<String>? extractorsJson,
  }) {
    return RequestScriptsCompanion(
      requestId: requestId ?? this.requestId,
      assertionsJson: assertionsJson ?? this.assertionsJson,
      extractorsJson: extractorsJson ?? this.extractorsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (requestId.present) {
      map['request_id'] = Variable<int>(requestId.value);
    }
    if (assertionsJson.present) {
      map['assertions_json'] = Variable<String>(assertionsJson.value);
    }
    if (extractorsJson.present) {
      map['extractors_json'] = Variable<String>(extractorsJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RequestScriptsCompanion(')
          ..write('requestId: $requestId, ')
          ..write('assertionsJson: $assertionsJson, ')
          ..write('extractorsJson: $extractorsJson')
          ..write(')'))
        .toString();
  }
}

class $ResponseExamplesTable extends ResponseExamples
    with TableInfo<$ResponseExamplesTable, ResponseExample> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResponseExamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<int> requestId = GeneratedColumn<int>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES requests (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusCodeMeta = const VerificationMeta(
    'statusCode',
  );
  @override
  late final GeneratedColumn<int> statusCode = GeneratedColumn<int>(
    'status_code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _headersJsonMeta = const VerificationMeta(
    'headersJson',
  );
  @override
  late final GeneratedColumn<String> headersJson = GeneratedColumn<String>(
    'headers_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    requestId,
    name,
    statusCode,
    headersJson,
    body,
    savedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'response_examples';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResponseExample> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('status_code')) {
      context.handle(
        _statusCodeMeta,
        statusCode.isAcceptableOrUnknown(data['status_code']!, _statusCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_statusCodeMeta);
    }
    if (data.containsKey('headers_json')) {
      context.handle(
        _headersJsonMeta,
        headersJson.isAcceptableOrUnknown(
          data['headers_json']!,
          _headersJsonMeta,
        ),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ResponseExample map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResponseExample(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}request_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      statusCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status_code'],
      )!,
      headersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}headers_json'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
    );
  }

  @override
  $ResponseExamplesTable createAlias(String alias) {
    return $ResponseExamplesTable(attachedDatabase, alias);
  }
}

class ResponseExample extends DataClass implements Insertable<ResponseExample> {
  final int id;
  final int requestId;
  final String name;
  final int statusCode;
  final String headersJson;
  final String body;
  final DateTime savedAt;
  const ResponseExample({
    required this.id,
    required this.requestId,
    required this.name,
    required this.statusCode,
    required this.headersJson,
    required this.body,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['request_id'] = Variable<int>(requestId);
    map['name'] = Variable<String>(name);
    map['status_code'] = Variable<int>(statusCode);
    map['headers_json'] = Variable<String>(headersJson);
    map['body'] = Variable<String>(body);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  ResponseExamplesCompanion toCompanion(bool nullToAbsent) {
    return ResponseExamplesCompanion(
      id: Value(id),
      requestId: Value(requestId),
      name: Value(name),
      statusCode: Value(statusCode),
      headersJson: Value(headersJson),
      body: Value(body),
      savedAt: Value(savedAt),
    );
  }

  factory ResponseExample.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResponseExample(
      id: serializer.fromJson<int>(json['id']),
      requestId: serializer.fromJson<int>(json['requestId']),
      name: serializer.fromJson<String>(json['name']),
      statusCode: serializer.fromJson<int>(json['statusCode']),
      headersJson: serializer.fromJson<String>(json['headersJson']),
      body: serializer.fromJson<String>(json['body']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'requestId': serializer.toJson<int>(requestId),
      'name': serializer.toJson<String>(name),
      'statusCode': serializer.toJson<int>(statusCode),
      'headersJson': serializer.toJson<String>(headersJson),
      'body': serializer.toJson<String>(body),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  ResponseExample copyWith({
    int? id,
    int? requestId,
    String? name,
    int? statusCode,
    String? headersJson,
    String? body,
    DateTime? savedAt,
  }) => ResponseExample(
    id: id ?? this.id,
    requestId: requestId ?? this.requestId,
    name: name ?? this.name,
    statusCode: statusCode ?? this.statusCode,
    headersJson: headersJson ?? this.headersJson,
    body: body ?? this.body,
    savedAt: savedAt ?? this.savedAt,
  );
  ResponseExample copyWithCompanion(ResponseExamplesCompanion data) {
    return ResponseExample(
      id: data.id.present ? data.id.value : this.id,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      name: data.name.present ? data.name.value : this.name,
      statusCode: data.statusCode.present
          ? data.statusCode.value
          : this.statusCode,
      headersJson: data.headersJson.present
          ? data.headersJson.value
          : this.headersJson,
      body: data.body.present ? data.body.value : this.body,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResponseExample(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('name: $name, ')
          ..write('statusCode: $statusCode, ')
          ..write('headersJson: $headersJson, ')
          ..write('body: $body, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, requestId, name, statusCode, headersJson, body, savedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResponseExample &&
          other.id == this.id &&
          other.requestId == this.requestId &&
          other.name == this.name &&
          other.statusCode == this.statusCode &&
          other.headersJson == this.headersJson &&
          other.body == this.body &&
          other.savedAt == this.savedAt);
}

class ResponseExamplesCompanion extends UpdateCompanion<ResponseExample> {
  final Value<int> id;
  final Value<int> requestId;
  final Value<String> name;
  final Value<int> statusCode;
  final Value<String> headersJson;
  final Value<String> body;
  final Value<DateTime> savedAt;
  const ResponseExamplesCompanion({
    this.id = const Value.absent(),
    this.requestId = const Value.absent(),
    this.name = const Value.absent(),
    this.statusCode = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.body = const Value.absent(),
    this.savedAt = const Value.absent(),
  });
  ResponseExamplesCompanion.insert({
    this.id = const Value.absent(),
    required int requestId,
    required String name,
    required int statusCode,
    this.headersJson = const Value.absent(),
    this.body = const Value.absent(),
    this.savedAt = const Value.absent(),
  }) : requestId = Value(requestId),
       name = Value(name),
       statusCode = Value(statusCode);
  static Insertable<ResponseExample> custom({
    Expression<int>? id,
    Expression<int>? requestId,
    Expression<String>? name,
    Expression<int>? statusCode,
    Expression<String>? headersJson,
    Expression<String>? body,
    Expression<DateTime>? savedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (requestId != null) 'request_id': requestId,
      if (name != null) 'name': name,
      if (statusCode != null) 'status_code': statusCode,
      if (headersJson != null) 'headers_json': headersJson,
      if (body != null) 'body': body,
      if (savedAt != null) 'saved_at': savedAt,
    });
  }

  ResponseExamplesCompanion copyWith({
    Value<int>? id,
    Value<int>? requestId,
    Value<String>? name,
    Value<int>? statusCode,
    Value<String>? headersJson,
    Value<String>? body,
    Value<DateTime>? savedAt,
  }) {
    return ResponseExamplesCompanion(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      name: name ?? this.name,
      statusCode: statusCode ?? this.statusCode,
      headersJson: headersJson ?? this.headersJson,
      body: body ?? this.body,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<int>(requestId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (statusCode.present) {
      map['status_code'] = Variable<int>(statusCode.value);
    }
    if (headersJson.present) {
      map['headers_json'] = Variable<String>(headersJson.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResponseExamplesCompanion(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('name: $name, ')
          ..write('statusCode: $statusCode, ')
          ..write('headersJson: $headersJson, ')
          ..write('body: $body, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }
}

class $EntityUidsTable extends EntityUids
    with TableInfo<$EntityUidsTable, EntityUid> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntityUidsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [kind, localId, uid];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entity_uids';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntityUid> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, localId};
  @override
  EntityUid map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntityUid(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      )!,
    );
  }

  @override
  $EntityUidsTable createAlias(String alias) {
    return $EntityUidsTable(attachedDatabase, alias);
  }
}

class EntityUid extends DataClass implements Insertable<EntityUid> {
  final String kind;
  final int localId;
  final String uid;
  const EntityUid({
    required this.kind,
    required this.localId,
    required this.uid,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['local_id'] = Variable<int>(localId);
    map['uid'] = Variable<String>(uid);
    return map;
  }

  EntityUidsCompanion toCompanion(bool nullToAbsent) {
    return EntityUidsCompanion(
      kind: Value(kind),
      localId: Value(localId),
      uid: Value(uid),
    );
  }

  factory EntityUid.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntityUid(
      kind: serializer.fromJson<String>(json['kind']),
      localId: serializer.fromJson<int>(json['localId']),
      uid: serializer.fromJson<String>(json['uid']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'localId': serializer.toJson<int>(localId),
      'uid': serializer.toJson<String>(uid),
    };
  }

  EntityUid copyWith({String? kind, int? localId, String? uid}) => EntityUid(
    kind: kind ?? this.kind,
    localId: localId ?? this.localId,
    uid: uid ?? this.uid,
  );
  EntityUid copyWithCompanion(EntityUidsCompanion data) {
    return EntityUid(
      kind: data.kind.present ? data.kind.value : this.kind,
      localId: data.localId.present ? data.localId.value : this.localId,
      uid: data.uid.present ? data.uid.value : this.uid,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntityUid(')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('uid: $uid')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, localId, uid);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntityUid &&
          other.kind == this.kind &&
          other.localId == this.localId &&
          other.uid == this.uid);
}

class EntityUidsCompanion extends UpdateCompanion<EntityUid> {
  final Value<String> kind;
  final Value<int> localId;
  final Value<String> uid;
  final Value<int> rowid;
  const EntityUidsCompanion({
    this.kind = const Value.absent(),
    this.localId = const Value.absent(),
    this.uid = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntityUidsCompanion.insert({
    required String kind,
    required int localId,
    required String uid,
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       localId = Value(localId),
       uid = Value(uid);
  static Insertable<EntityUid> custom({
    Expression<String>? kind,
    Expression<int>? localId,
    Expression<String>? uid,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (localId != null) 'local_id': localId,
      if (uid != null) 'uid': uid,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntityUidsCompanion copyWith({
    Value<String>? kind,
    Value<int>? localId,
    Value<String>? uid,
    Value<int>? rowid,
  }) {
    return EntityUidsCompanion(
      kind: kind ?? this.kind,
      localId: localId ?? this.localId,
      uid: uid ?? this.uid,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntityUidsCompanion(')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('uid: $uid, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GitLinksTable extends GitLinks
    with TableInfo<$GitLinksTable, GitLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GitLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<int> collectionId = GeneratedColumn<int>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repoMeta = const VerificationMeta('repo');
  @override
  late final GeneratedColumn<String> repo = GeneratedColumn<String>(
    'repo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchMeta = const VerificationMeta('branch');
  @override
  late final GeneratedColumn<String> branch = GeneratedColumn<String>(
    'branch',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _basePathMeta = const VerificationMeta(
    'basePath',
  );
  @override
  late final GeneratedColumn<String> basePath = GeneratedColumn<String>(
    'base_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _lastSyncedShaMeta = const VerificationMeta(
    'lastSyncedSha',
  );
  @override
  late final GeneratedColumn<String> lastSyncedSha = GeneratedColumn<String>(
    'last_synced_sha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _includeSecretsMeta = const VerificationMeta(
    'includeSecrets',
  );
  @override
  late final GeneratedColumn<bool> includeSecrets = GeneratedColumn<bool>(
    'include_secrets',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("include_secrets" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    collectionId,
    provider,
    owner,
    repo,
    branch,
    basePath,
    lastSyncedSha,
    lastSyncedAt,
    includeSecrets,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'git_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<GitLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('repo')) {
      context.handle(
        _repoMeta,
        repo.isAcceptableOrUnknown(data['repo']!, _repoMeta),
      );
    } else if (isInserting) {
      context.missing(_repoMeta);
    }
    if (data.containsKey('branch')) {
      context.handle(
        _branchMeta,
        branch.isAcceptableOrUnknown(data['branch']!, _branchMeta),
      );
    } else if (isInserting) {
      context.missing(_branchMeta);
    }
    if (data.containsKey('base_path')) {
      context.handle(
        _basePathMeta,
        basePath.isAcceptableOrUnknown(data['base_path']!, _basePathMeta),
      );
    }
    if (data.containsKey('last_synced_sha')) {
      context.handle(
        _lastSyncedShaMeta,
        lastSyncedSha.isAcceptableOrUnknown(
          data['last_synced_sha']!,
          _lastSyncedShaMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('include_secrets')) {
      context.handle(
        _includeSecretsMeta,
        includeSecrets.isAcceptableOrUnknown(
          data['include_secrets']!,
          _includeSecretsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GitLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GitLinkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}collection_id'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      repo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repo'],
      )!,
      branch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch'],
      )!,
      basePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_path'],
      )!,
      lastSyncedSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_synced_sha'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      ),
      includeSecrets: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}include_secrets'],
      )!,
    );
  }

  @override
  $GitLinksTable createAlias(String alias) {
    return $GitLinksTable(attachedDatabase, alias);
  }
}

class GitLinkRow extends DataClass implements Insertable<GitLinkRow> {
  final int id;
  final int collectionId;
  final String provider;
  final String owner;
  final String repo;
  final String branch;
  final String basePath;
  final String? lastSyncedSha;
  final DateTime? lastSyncedAt;
  final bool includeSecrets;
  const GitLinkRow({
    required this.id,
    required this.collectionId,
    required this.provider,
    required this.owner,
    required this.repo,
    required this.branch,
    required this.basePath,
    this.lastSyncedSha,
    this.lastSyncedAt,
    required this.includeSecrets,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['collection_id'] = Variable<int>(collectionId);
    map['provider'] = Variable<String>(provider);
    map['owner'] = Variable<String>(owner);
    map['repo'] = Variable<String>(repo);
    map['branch'] = Variable<String>(branch);
    map['base_path'] = Variable<String>(basePath);
    if (!nullToAbsent || lastSyncedSha != null) {
      map['last_synced_sha'] = Variable<String>(lastSyncedSha);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    }
    map['include_secrets'] = Variable<bool>(includeSecrets);
    return map;
  }

  GitLinksCompanion toCompanion(bool nullToAbsent) {
    return GitLinksCompanion(
      id: Value(id),
      collectionId: Value(collectionId),
      provider: Value(provider),
      owner: Value(owner),
      repo: Value(repo),
      branch: Value(branch),
      basePath: Value(basePath),
      lastSyncedSha: lastSyncedSha == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedSha),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
      includeSecrets: Value(includeSecrets),
    );
  }

  factory GitLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GitLinkRow(
      id: serializer.fromJson<int>(json['id']),
      collectionId: serializer.fromJson<int>(json['collectionId']),
      provider: serializer.fromJson<String>(json['provider']),
      owner: serializer.fromJson<String>(json['owner']),
      repo: serializer.fromJson<String>(json['repo']),
      branch: serializer.fromJson<String>(json['branch']),
      basePath: serializer.fromJson<String>(json['basePath']),
      lastSyncedSha: serializer.fromJson<String?>(json['lastSyncedSha']),
      lastSyncedAt: serializer.fromJson<DateTime?>(json['lastSyncedAt']),
      includeSecrets: serializer.fromJson<bool>(json['includeSecrets']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'collectionId': serializer.toJson<int>(collectionId),
      'provider': serializer.toJson<String>(provider),
      'owner': serializer.toJson<String>(owner),
      'repo': serializer.toJson<String>(repo),
      'branch': serializer.toJson<String>(branch),
      'basePath': serializer.toJson<String>(basePath),
      'lastSyncedSha': serializer.toJson<String?>(lastSyncedSha),
      'lastSyncedAt': serializer.toJson<DateTime?>(lastSyncedAt),
      'includeSecrets': serializer.toJson<bool>(includeSecrets),
    };
  }

  GitLinkRow copyWith({
    int? id,
    int? collectionId,
    String? provider,
    String? owner,
    String? repo,
    String? branch,
    String? basePath,
    Value<String?> lastSyncedSha = const Value.absent(),
    Value<DateTime?> lastSyncedAt = const Value.absent(),
    bool? includeSecrets,
  }) => GitLinkRow(
    id: id ?? this.id,
    collectionId: collectionId ?? this.collectionId,
    provider: provider ?? this.provider,
    owner: owner ?? this.owner,
    repo: repo ?? this.repo,
    branch: branch ?? this.branch,
    basePath: basePath ?? this.basePath,
    lastSyncedSha: lastSyncedSha.present
        ? lastSyncedSha.value
        : this.lastSyncedSha,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
    includeSecrets: includeSecrets ?? this.includeSecrets,
  );
  GitLinkRow copyWithCompanion(GitLinksCompanion data) {
    return GitLinkRow(
      id: data.id.present ? data.id.value : this.id,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      provider: data.provider.present ? data.provider.value : this.provider,
      owner: data.owner.present ? data.owner.value : this.owner,
      repo: data.repo.present ? data.repo.value : this.repo,
      branch: data.branch.present ? data.branch.value : this.branch,
      basePath: data.basePath.present ? data.basePath.value : this.basePath,
      lastSyncedSha: data.lastSyncedSha.present
          ? data.lastSyncedSha.value
          : this.lastSyncedSha,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      includeSecrets: data.includeSecrets.present
          ? data.includeSecrets.value
          : this.includeSecrets,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GitLinkRow(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('provider: $provider, ')
          ..write('owner: $owner, ')
          ..write('repo: $repo, ')
          ..write('branch: $branch, ')
          ..write('basePath: $basePath, ')
          ..write('lastSyncedSha: $lastSyncedSha, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('includeSecrets: $includeSecrets')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    collectionId,
    provider,
    owner,
    repo,
    branch,
    basePath,
    lastSyncedSha,
    lastSyncedAt,
    includeSecrets,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GitLinkRow &&
          other.id == this.id &&
          other.collectionId == this.collectionId &&
          other.provider == this.provider &&
          other.owner == this.owner &&
          other.repo == this.repo &&
          other.branch == this.branch &&
          other.basePath == this.basePath &&
          other.lastSyncedSha == this.lastSyncedSha &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.includeSecrets == this.includeSecrets);
}

class GitLinksCompanion extends UpdateCompanion<GitLinkRow> {
  final Value<int> id;
  final Value<int> collectionId;
  final Value<String> provider;
  final Value<String> owner;
  final Value<String> repo;
  final Value<String> branch;
  final Value<String> basePath;
  final Value<String?> lastSyncedSha;
  final Value<DateTime?> lastSyncedAt;
  final Value<bool> includeSecrets;
  const GitLinksCompanion({
    this.id = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.provider = const Value.absent(),
    this.owner = const Value.absent(),
    this.repo = const Value.absent(),
    this.branch = const Value.absent(),
    this.basePath = const Value.absent(),
    this.lastSyncedSha = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.includeSecrets = const Value.absent(),
  });
  GitLinksCompanion.insert({
    this.id = const Value.absent(),
    required int collectionId,
    required String provider,
    required String owner,
    required String repo,
    required String branch,
    this.basePath = const Value.absent(),
    this.lastSyncedSha = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.includeSecrets = const Value.absent(),
  }) : collectionId = Value(collectionId),
       provider = Value(provider),
       owner = Value(owner),
       repo = Value(repo),
       branch = Value(branch);
  static Insertable<GitLinkRow> custom({
    Expression<int>? id,
    Expression<int>? collectionId,
    Expression<String>? provider,
    Expression<String>? owner,
    Expression<String>? repo,
    Expression<String>? branch,
    Expression<String>? basePath,
    Expression<String>? lastSyncedSha,
    Expression<DateTime>? lastSyncedAt,
    Expression<bool>? includeSecrets,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collectionId != null) 'collection_id': collectionId,
      if (provider != null) 'provider': provider,
      if (owner != null) 'owner': owner,
      if (repo != null) 'repo': repo,
      if (branch != null) 'branch': branch,
      if (basePath != null) 'base_path': basePath,
      if (lastSyncedSha != null) 'last_synced_sha': lastSyncedSha,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (includeSecrets != null) 'include_secrets': includeSecrets,
    });
  }

  GitLinksCompanion copyWith({
    Value<int>? id,
    Value<int>? collectionId,
    Value<String>? provider,
    Value<String>? owner,
    Value<String>? repo,
    Value<String>? branch,
    Value<String>? basePath,
    Value<String?>? lastSyncedSha,
    Value<DateTime?>? lastSyncedAt,
    Value<bool>? includeSecrets,
  }) {
    return GitLinksCompanion(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      provider: provider ?? this.provider,
      owner: owner ?? this.owner,
      repo: repo ?? this.repo,
      branch: branch ?? this.branch,
      basePath: basePath ?? this.basePath,
      lastSyncedSha: lastSyncedSha ?? this.lastSyncedSha,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      includeSecrets: includeSecrets ?? this.includeSecrets,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<int>(collectionId.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (repo.present) {
      map['repo'] = Variable<String>(repo.value);
    }
    if (branch.present) {
      map['branch'] = Variable<String>(branch.value);
    }
    if (basePath.present) {
      map['base_path'] = Variable<String>(basePath.value);
    }
    if (lastSyncedSha.present) {
      map['last_synced_sha'] = Variable<String>(lastSyncedSha.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (includeSecrets.present) {
      map['include_secrets'] = Variable<bool>(includeSecrets.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GitLinksCompanion(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('provider: $provider, ')
          ..write('owner: $owner, ')
          ..write('repo: $repo, ')
          ..write('branch: $branch, ')
          ..write('basePath: $basePath, ')
          ..write('lastSyncedSha: $lastSyncedSha, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('includeSecrets: $includeSecrets')
          ..write(')'))
        .toString();
  }
}

class $GitBaseEntriesTable extends GitBaseEntries
    with TableInfo<$GitBaseEntriesTable, GitBaseEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GitBaseEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _linkIdMeta = const VerificationMeta('linkId');
  @override
  late final GeneratedColumn<int> linkId = GeneratedColumn<int>(
    'link_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES git_links (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blobShaMeta = const VerificationMeta(
    'blobSha',
  );
  @override
  late final GeneratedColumn<String> blobSha = GeneratedColumn<String>(
    'blob_sha',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _docJsonMeta = const VerificationMeta(
    'docJson',
  );
  @override
  late final GeneratedColumn<String> docJson = GeneratedColumn<String>(
    'doc_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [linkId, uid, path, blobSha, docJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'git_base_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<GitBaseEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('link_id')) {
      context.handle(
        _linkIdMeta,
        linkId.isAcceptableOrUnknown(data['link_id']!, _linkIdMeta),
      );
    } else if (isInserting) {
      context.missing(_linkIdMeta);
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('blob_sha')) {
      context.handle(
        _blobShaMeta,
        blobSha.isAcceptableOrUnknown(data['blob_sha']!, _blobShaMeta),
      );
    } else if (isInserting) {
      context.missing(_blobShaMeta);
    }
    if (data.containsKey('doc_json')) {
      context.handle(
        _docJsonMeta,
        docJson.isAcceptableOrUnknown(data['doc_json']!, _docJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_docJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {linkId, uid};
  @override
  GitBaseEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GitBaseEntry(
      linkId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}link_id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      blobSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blob_sha'],
      )!,
      docJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_json'],
      )!,
    );
  }

  @override
  $GitBaseEntriesTable createAlias(String alias) {
    return $GitBaseEntriesTable(attachedDatabase, alias);
  }
}

class GitBaseEntry extends DataClass implements Insertable<GitBaseEntry> {
  final int linkId;
  final String uid;
  final String path;
  final String blobSha;
  final String docJson;
  const GitBaseEntry({
    required this.linkId,
    required this.uid,
    required this.path,
    required this.blobSha,
    required this.docJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['link_id'] = Variable<int>(linkId);
    map['uid'] = Variable<String>(uid);
    map['path'] = Variable<String>(path);
    map['blob_sha'] = Variable<String>(blobSha);
    map['doc_json'] = Variable<String>(docJson);
    return map;
  }

  GitBaseEntriesCompanion toCompanion(bool nullToAbsent) {
    return GitBaseEntriesCompanion(
      linkId: Value(linkId),
      uid: Value(uid),
      path: Value(path),
      blobSha: Value(blobSha),
      docJson: Value(docJson),
    );
  }

  factory GitBaseEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GitBaseEntry(
      linkId: serializer.fromJson<int>(json['linkId']),
      uid: serializer.fromJson<String>(json['uid']),
      path: serializer.fromJson<String>(json['path']),
      blobSha: serializer.fromJson<String>(json['blobSha']),
      docJson: serializer.fromJson<String>(json['docJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'linkId': serializer.toJson<int>(linkId),
      'uid': serializer.toJson<String>(uid),
      'path': serializer.toJson<String>(path),
      'blobSha': serializer.toJson<String>(blobSha),
      'docJson': serializer.toJson<String>(docJson),
    };
  }

  GitBaseEntry copyWith({
    int? linkId,
    String? uid,
    String? path,
    String? blobSha,
    String? docJson,
  }) => GitBaseEntry(
    linkId: linkId ?? this.linkId,
    uid: uid ?? this.uid,
    path: path ?? this.path,
    blobSha: blobSha ?? this.blobSha,
    docJson: docJson ?? this.docJson,
  );
  GitBaseEntry copyWithCompanion(GitBaseEntriesCompanion data) {
    return GitBaseEntry(
      linkId: data.linkId.present ? data.linkId.value : this.linkId,
      uid: data.uid.present ? data.uid.value : this.uid,
      path: data.path.present ? data.path.value : this.path,
      blobSha: data.blobSha.present ? data.blobSha.value : this.blobSha,
      docJson: data.docJson.present ? data.docJson.value : this.docJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GitBaseEntry(')
          ..write('linkId: $linkId, ')
          ..write('uid: $uid, ')
          ..write('path: $path, ')
          ..write('blobSha: $blobSha, ')
          ..write('docJson: $docJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(linkId, uid, path, blobSha, docJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GitBaseEntry &&
          other.linkId == this.linkId &&
          other.uid == this.uid &&
          other.path == this.path &&
          other.blobSha == this.blobSha &&
          other.docJson == this.docJson);
}

class GitBaseEntriesCompanion extends UpdateCompanion<GitBaseEntry> {
  final Value<int> linkId;
  final Value<String> uid;
  final Value<String> path;
  final Value<String> blobSha;
  final Value<String> docJson;
  final Value<int> rowid;
  const GitBaseEntriesCompanion({
    this.linkId = const Value.absent(),
    this.uid = const Value.absent(),
    this.path = const Value.absent(),
    this.blobSha = const Value.absent(),
    this.docJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GitBaseEntriesCompanion.insert({
    required int linkId,
    required String uid,
    required String path,
    required String blobSha,
    required String docJson,
    this.rowid = const Value.absent(),
  }) : linkId = Value(linkId),
       uid = Value(uid),
       path = Value(path),
       blobSha = Value(blobSha),
       docJson = Value(docJson);
  static Insertable<GitBaseEntry> custom({
    Expression<int>? linkId,
    Expression<String>? uid,
    Expression<String>? path,
    Expression<String>? blobSha,
    Expression<String>? docJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (linkId != null) 'link_id': linkId,
      if (uid != null) 'uid': uid,
      if (path != null) 'path': path,
      if (blobSha != null) 'blob_sha': blobSha,
      if (docJson != null) 'doc_json': docJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GitBaseEntriesCompanion copyWith({
    Value<int>? linkId,
    Value<String>? uid,
    Value<String>? path,
    Value<String>? blobSha,
    Value<String>? docJson,
    Value<int>? rowid,
  }) {
    return GitBaseEntriesCompanion(
      linkId: linkId ?? this.linkId,
      uid: uid ?? this.uid,
      path: path ?? this.path,
      blobSha: blobSha ?? this.blobSha,
      docJson: docJson ?? this.docJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (linkId.present) {
      map['link_id'] = Variable<int>(linkId.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (blobSha.present) {
      map['blob_sha'] = Variable<String>(blobSha.value);
    }
    if (docJson.present) {
      map['doc_json'] = Variable<String>(docJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GitBaseEntriesCompanion(')
          ..write('linkId: $linkId, ')
          ..write('uid: $uid, ')
          ..write('path: $path, ')
          ..write('blobSha: $blobSha, ')
          ..write('docJson: $docJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingEntriesTable extends SettingEntries
    with TableInfo<$SettingEntriesTable, SettingEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setting_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingEntriesTable createAlias(String alias) {
    return $SettingEntriesTable(attachedDatabase, alias);
  }
}

class SettingEntry extends DataClass implements Insertable<SettingEntry> {
  final String key;
  final String value;
  const SettingEntry({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingEntriesCompanion toCompanion(bool nullToAbsent) {
    return SettingEntriesCompanion(key: Value(key), value: Value(value));
  }

  factory SettingEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingEntry copyWith({String? key, String? value}) =>
      SettingEntry(key: key ?? this.key, value: value ?? this.value);
  SettingEntry copyWithCompanion(SettingEntriesCompanion data) {
    return SettingEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntry(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingEntry &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingEntriesCompanion extends UpdateCompanion<SettingEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingEntriesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RequestSettingEntriesTable extends RequestSettingEntries
    with TableInfo<$RequestSettingEntriesTable, RequestSettingEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RequestSettingEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<int> requestId = GeneratedColumn<int>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES requests (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _settingsJsonMeta = const VerificationMeta(
    'settingsJson',
  );
  @override
  late final GeneratedColumn<String> settingsJson = GeneratedColumn<String>(
    'settings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [requestId, settingsJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'request_setting_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<RequestSettingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('settings_json')) {
      context.handle(
        _settingsJsonMeta,
        settingsJson.isAcceptableOrUnknown(
          data['settings_json']!,
          _settingsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {requestId};
  @override
  RequestSettingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RequestSettingEntry(
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}request_id'],
      )!,
      settingsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settings_json'],
      )!,
    );
  }

  @override
  $RequestSettingEntriesTable createAlias(String alias) {
    return $RequestSettingEntriesTable(attachedDatabase, alias);
  }
}

class RequestSettingEntry extends DataClass
    implements Insertable<RequestSettingEntry> {
  final int requestId;
  final String settingsJson;
  const RequestSettingEntry({
    required this.requestId,
    required this.settingsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['request_id'] = Variable<int>(requestId);
    map['settings_json'] = Variable<String>(settingsJson);
    return map;
  }

  RequestSettingEntriesCompanion toCompanion(bool nullToAbsent) {
    return RequestSettingEntriesCompanion(
      requestId: Value(requestId),
      settingsJson: Value(settingsJson),
    );
  }

  factory RequestSettingEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RequestSettingEntry(
      requestId: serializer.fromJson<int>(json['requestId']),
      settingsJson: serializer.fromJson<String>(json['settingsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'requestId': serializer.toJson<int>(requestId),
      'settingsJson': serializer.toJson<String>(settingsJson),
    };
  }

  RequestSettingEntry copyWith({int? requestId, String? settingsJson}) =>
      RequestSettingEntry(
        requestId: requestId ?? this.requestId,
        settingsJson: settingsJson ?? this.settingsJson,
      );
  RequestSettingEntry copyWithCompanion(RequestSettingEntriesCompanion data) {
    return RequestSettingEntry(
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      settingsJson: data.settingsJson.present
          ? data.settingsJson.value
          : this.settingsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RequestSettingEntry(')
          ..write('requestId: $requestId, ')
          ..write('settingsJson: $settingsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(requestId, settingsJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestSettingEntry &&
          other.requestId == this.requestId &&
          other.settingsJson == this.settingsJson);
}

class RequestSettingEntriesCompanion
    extends UpdateCompanion<RequestSettingEntry> {
  final Value<int> requestId;
  final Value<String> settingsJson;
  const RequestSettingEntriesCompanion({
    this.requestId = const Value.absent(),
    this.settingsJson = const Value.absent(),
  });
  RequestSettingEntriesCompanion.insert({
    this.requestId = const Value.absent(),
    this.settingsJson = const Value.absent(),
  });
  static Insertable<RequestSettingEntry> custom({
    Expression<int>? requestId,
    Expression<String>? settingsJson,
  }) {
    return RawValuesInsertable({
      if (requestId != null) 'request_id': requestId,
      if (settingsJson != null) 'settings_json': settingsJson,
    });
  }

  RequestSettingEntriesCompanion copyWith({
    Value<int>? requestId,
    Value<String>? settingsJson,
  }) {
    return RequestSettingEntriesCompanion(
      requestId: requestId ?? this.requestId,
      settingsJson: settingsJson ?? this.settingsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (requestId.present) {
      map['request_id'] = Variable<int>(requestId.value);
    }
    if (settingsJson.present) {
      map['settings_json'] = Variable<String>(settingsJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RequestSettingEntriesCompanion(')
          ..write('requestId: $requestId, ')
          ..write('settingsJson: $settingsJson')
          ..write(')'))
        .toString();
  }
}

class $EntityDocsTable extends EntityDocs
    with TableInfo<$EntityDocsTable, EntityDoc> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntityDocsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _markdownMeta = const VerificationMeta(
    'markdown',
  );
  @override
  late final GeneratedColumn<String> markdown = GeneratedColumn<String>(
    'markdown',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [kind, localId, markdown];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entity_docs';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntityDoc> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('markdown')) {
      context.handle(
        _markdownMeta,
        markdown.isAcceptableOrUnknown(data['markdown']!, _markdownMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, localId};
  @override
  EntityDoc map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntityDoc(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      markdown: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}markdown'],
      )!,
    );
  }

  @override
  $EntityDocsTable createAlias(String alias) {
    return $EntityDocsTable(attachedDatabase, alias);
  }
}

class EntityDoc extends DataClass implements Insertable<EntityDoc> {
  final String kind;
  final int localId;
  final String markdown;
  const EntityDoc({
    required this.kind,
    required this.localId,
    required this.markdown,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['local_id'] = Variable<int>(localId);
    map['markdown'] = Variable<String>(markdown);
    return map;
  }

  EntityDocsCompanion toCompanion(bool nullToAbsent) {
    return EntityDocsCompanion(
      kind: Value(kind),
      localId: Value(localId),
      markdown: Value(markdown),
    );
  }

  factory EntityDoc.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntityDoc(
      kind: serializer.fromJson<String>(json['kind']),
      localId: serializer.fromJson<int>(json['localId']),
      markdown: serializer.fromJson<String>(json['markdown']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'localId': serializer.toJson<int>(localId),
      'markdown': serializer.toJson<String>(markdown),
    };
  }

  EntityDoc copyWith({String? kind, int? localId, String? markdown}) =>
      EntityDoc(
        kind: kind ?? this.kind,
        localId: localId ?? this.localId,
        markdown: markdown ?? this.markdown,
      );
  EntityDoc copyWithCompanion(EntityDocsCompanion data) {
    return EntityDoc(
      kind: data.kind.present ? data.kind.value : this.kind,
      localId: data.localId.present ? data.localId.value : this.localId,
      markdown: data.markdown.present ? data.markdown.value : this.markdown,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntityDoc(')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('markdown: $markdown')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, localId, markdown);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntityDoc &&
          other.kind == this.kind &&
          other.localId == this.localId &&
          other.markdown == this.markdown);
}

class EntityDocsCompanion extends UpdateCompanion<EntityDoc> {
  final Value<String> kind;
  final Value<int> localId;
  final Value<String> markdown;
  final Value<int> rowid;
  const EntityDocsCompanion({
    this.kind = const Value.absent(),
    this.localId = const Value.absent(),
    this.markdown = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntityDocsCompanion.insert({
    required String kind,
    required int localId,
    this.markdown = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       localId = Value(localId);
  static Insertable<EntityDoc> custom({
    Expression<String>? kind,
    Expression<int>? localId,
    Expression<String>? markdown,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (localId != null) 'local_id': localId,
      if (markdown != null) 'markdown': markdown,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntityDocsCompanion copyWith({
    Value<String>? kind,
    Value<int>? localId,
    Value<String>? markdown,
    Value<int>? rowid,
  }) {
    return EntityDocsCompanion(
      kind: kind ?? this.kind,
      localId: localId ?? this.localId,
      markdown: markdown ?? this.markdown,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (markdown.present) {
      map['markdown'] = Variable<String>(markdown.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntityDocsCompanion(')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('markdown: $markdown, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntityTagsTable extends EntityTags
    with TableInfo<$EntityTagsTable, EntityTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntityTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [kind, localId, tag];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entity_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntityTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    } else if (isInserting) {
      context.missing(_tagMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, localId, tag};
  @override
  EntityTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntityTag(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      )!,
    );
  }

  @override
  $EntityTagsTable createAlias(String alias) {
    return $EntityTagsTable(attachedDatabase, alias);
  }
}

class EntityTag extends DataClass implements Insertable<EntityTag> {
  final String kind;
  final int localId;
  final String tag;
  const EntityTag({
    required this.kind,
    required this.localId,
    required this.tag,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['local_id'] = Variable<int>(localId);
    map['tag'] = Variable<String>(tag);
    return map;
  }

  EntityTagsCompanion toCompanion(bool nullToAbsent) {
    return EntityTagsCompanion(
      kind: Value(kind),
      localId: Value(localId),
      tag: Value(tag),
    );
  }

  factory EntityTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntityTag(
      kind: serializer.fromJson<String>(json['kind']),
      localId: serializer.fromJson<int>(json['localId']),
      tag: serializer.fromJson<String>(json['tag']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'localId': serializer.toJson<int>(localId),
      'tag': serializer.toJson<String>(tag),
    };
  }

  EntityTag copyWith({String? kind, int? localId, String? tag}) => EntityTag(
    kind: kind ?? this.kind,
    localId: localId ?? this.localId,
    tag: tag ?? this.tag,
  );
  EntityTag copyWithCompanion(EntityTagsCompanion data) {
    return EntityTag(
      kind: data.kind.present ? data.kind.value : this.kind,
      localId: data.localId.present ? data.localId.value : this.localId,
      tag: data.tag.present ? data.tag.value : this.tag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntityTag(')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('tag: $tag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, localId, tag);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntityTag &&
          other.kind == this.kind &&
          other.localId == this.localId &&
          other.tag == this.tag);
}

class EntityTagsCompanion extends UpdateCompanion<EntityTag> {
  final Value<String> kind;
  final Value<int> localId;
  final Value<String> tag;
  final Value<int> rowid;
  const EntityTagsCompanion({
    this.kind = const Value.absent(),
    this.localId = const Value.absent(),
    this.tag = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntityTagsCompanion.insert({
    required String kind,
    required int localId,
    required String tag,
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       localId = Value(localId),
       tag = Value(tag);
  static Insertable<EntityTag> custom({
    Expression<String>? kind,
    Expression<int>? localId,
    Expression<String>? tag,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (localId != null) 'local_id': localId,
      if (tag != null) 'tag': tag,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntityTagsCompanion copyWith({
    Value<String>? kind,
    Value<int>? localId,
    Value<String>? tag,
    Value<int>? rowid,
  }) {
    return EntityTagsCompanion(
      kind: kind ?? this.kind,
      localId: localId ?? this.localId,
      tag: tag ?? this.tag,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntityTagsCompanion(')
          ..write('kind: $kind, ')
          ..write('localId: $localId, ')
          ..write('tag: $tag, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FolderDefaultsTable extends FolderDefaults
    with TableInfo<$FolderDefaultsTable, FolderDefault> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FolderDefaultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _headersJsonMeta = const VerificationMeta(
    'headersJson',
  );
  @override
  late final GeneratedColumn<String> headersJson = GeneratedColumn<String>(
    'headers_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _variablesJsonMeta = const VerificationMeta(
    'variablesJson',
  );
  @override
  late final GeneratedColumn<String> variablesJson = GeneratedColumn<String>(
    'variables_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _authJsonMeta = const VerificationMeta(
    'authJson',
  );
  @override
  late final GeneratedColumn<String> authJson = GeneratedColumn<String>(
    'auth_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _scriptsJsonMeta = const VerificationMeta(
    'scriptsJson',
  );
  @override
  late final GeneratedColumn<String> scriptsJson = GeneratedColumn<String>(
    'scripts_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    folderId,
    headersJson,
    variablesJson,
    authJson,
    scriptsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folder_defaults';
  @override
  VerificationContext validateIntegrity(
    Insertable<FolderDefault> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('headers_json')) {
      context.handle(
        _headersJsonMeta,
        headersJson.isAcceptableOrUnknown(
          data['headers_json']!,
          _headersJsonMeta,
        ),
      );
    }
    if (data.containsKey('variables_json')) {
      context.handle(
        _variablesJsonMeta,
        variablesJson.isAcceptableOrUnknown(
          data['variables_json']!,
          _variablesJsonMeta,
        ),
      );
    }
    if (data.containsKey('auth_json')) {
      context.handle(
        _authJsonMeta,
        authJson.isAcceptableOrUnknown(data['auth_json']!, _authJsonMeta),
      );
    }
    if (data.containsKey('scripts_json')) {
      context.handle(
        _scriptsJsonMeta,
        scriptsJson.isAcceptableOrUnknown(
          data['scripts_json']!,
          _scriptsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {folderId};
  @override
  FolderDefault map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FolderDefault(
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      )!,
      headersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}headers_json'],
      )!,
      variablesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variables_json'],
      )!,
      authJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_json'],
      )!,
      scriptsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scripts_json'],
      )!,
    );
  }

  @override
  $FolderDefaultsTable createAlias(String alias) {
    return $FolderDefaultsTable(attachedDatabase, alias);
  }
}

class FolderDefault extends DataClass implements Insertable<FolderDefault> {
  final int folderId;
  final String headersJson;
  final String variablesJson;
  final String authJson;
  final String scriptsJson;
  const FolderDefault({
    required this.folderId,
    required this.headersJson,
    required this.variablesJson,
    required this.authJson,
    required this.scriptsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['folder_id'] = Variable<int>(folderId);
    map['headers_json'] = Variable<String>(headersJson);
    map['variables_json'] = Variable<String>(variablesJson);
    map['auth_json'] = Variable<String>(authJson);
    map['scripts_json'] = Variable<String>(scriptsJson);
    return map;
  }

  FolderDefaultsCompanion toCompanion(bool nullToAbsent) {
    return FolderDefaultsCompanion(
      folderId: Value(folderId),
      headersJson: Value(headersJson),
      variablesJson: Value(variablesJson),
      authJson: Value(authJson),
      scriptsJson: Value(scriptsJson),
    );
  }

  factory FolderDefault.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FolderDefault(
      folderId: serializer.fromJson<int>(json['folderId']),
      headersJson: serializer.fromJson<String>(json['headersJson']),
      variablesJson: serializer.fromJson<String>(json['variablesJson']),
      authJson: serializer.fromJson<String>(json['authJson']),
      scriptsJson: serializer.fromJson<String>(json['scriptsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'folderId': serializer.toJson<int>(folderId),
      'headersJson': serializer.toJson<String>(headersJson),
      'variablesJson': serializer.toJson<String>(variablesJson),
      'authJson': serializer.toJson<String>(authJson),
      'scriptsJson': serializer.toJson<String>(scriptsJson),
    };
  }

  FolderDefault copyWith({
    int? folderId,
    String? headersJson,
    String? variablesJson,
    String? authJson,
    String? scriptsJson,
  }) => FolderDefault(
    folderId: folderId ?? this.folderId,
    headersJson: headersJson ?? this.headersJson,
    variablesJson: variablesJson ?? this.variablesJson,
    authJson: authJson ?? this.authJson,
    scriptsJson: scriptsJson ?? this.scriptsJson,
  );
  FolderDefault copyWithCompanion(FolderDefaultsCompanion data) {
    return FolderDefault(
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      headersJson: data.headersJson.present
          ? data.headersJson.value
          : this.headersJson,
      variablesJson: data.variablesJson.present
          ? data.variablesJson.value
          : this.variablesJson,
      authJson: data.authJson.present ? data.authJson.value : this.authJson,
      scriptsJson: data.scriptsJson.present
          ? data.scriptsJson.value
          : this.scriptsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FolderDefault(')
          ..write('folderId: $folderId, ')
          ..write('headersJson: $headersJson, ')
          ..write('variablesJson: $variablesJson, ')
          ..write('authJson: $authJson, ')
          ..write('scriptsJson: $scriptsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(folderId, headersJson, variablesJson, authJson, scriptsJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderDefault &&
          other.folderId == this.folderId &&
          other.headersJson == this.headersJson &&
          other.variablesJson == this.variablesJson &&
          other.authJson == this.authJson &&
          other.scriptsJson == this.scriptsJson);
}

class FolderDefaultsCompanion extends UpdateCompanion<FolderDefault> {
  final Value<int> folderId;
  final Value<String> headersJson;
  final Value<String> variablesJson;
  final Value<String> authJson;
  final Value<String> scriptsJson;
  const FolderDefaultsCompanion({
    this.folderId = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.variablesJson = const Value.absent(),
    this.authJson = const Value.absent(),
    this.scriptsJson = const Value.absent(),
  });
  FolderDefaultsCompanion.insert({
    this.folderId = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.variablesJson = const Value.absent(),
    this.authJson = const Value.absent(),
    this.scriptsJson = const Value.absent(),
  });
  static Insertable<FolderDefault> custom({
    Expression<int>? folderId,
    Expression<String>? headersJson,
    Expression<String>? variablesJson,
    Expression<String>? authJson,
    Expression<String>? scriptsJson,
  }) {
    return RawValuesInsertable({
      if (folderId != null) 'folder_id': folderId,
      if (headersJson != null) 'headers_json': headersJson,
      if (variablesJson != null) 'variables_json': variablesJson,
      if (authJson != null) 'auth_json': authJson,
      if (scriptsJson != null) 'scripts_json': scriptsJson,
    });
  }

  FolderDefaultsCompanion copyWith({
    Value<int>? folderId,
    Value<String>? headersJson,
    Value<String>? variablesJson,
    Value<String>? authJson,
    Value<String>? scriptsJson,
  }) {
    return FolderDefaultsCompanion(
      folderId: folderId ?? this.folderId,
      headersJson: headersJson ?? this.headersJson,
      variablesJson: variablesJson ?? this.variablesJson,
      authJson: authJson ?? this.authJson,
      scriptsJson: scriptsJson ?? this.scriptsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (headersJson.present) {
      map['headers_json'] = Variable<String>(headersJson.value);
    }
    if (variablesJson.present) {
      map['variables_json'] = Variable<String>(variablesJson.value);
    }
    if (authJson.present) {
      map['auth_json'] = Variable<String>(authJson.value);
    }
    if (scriptsJson.present) {
      map['scripts_json'] = Variable<String>(scriptsJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FolderDefaultsCompanion(')
          ..write('folderId: $folderId, ')
          ..write('headersJson: $headersJson, ')
          ..write('variablesJson: $variablesJson, ')
          ..write('authJson: $authJson, ')
          ..write('scriptsJson: $scriptsJson')
          ..write(')'))
        .toString();
  }
}

class $CollectionDefaultsTable extends CollectionDefaults
    with TableInfo<$CollectionDefaultsTable, CollectionDefault> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionDefaultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<int> collectionId = GeneratedColumn<int>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _headersJsonMeta = const VerificationMeta(
    'headersJson',
  );
  @override
  late final GeneratedColumn<String> headersJson = GeneratedColumn<String>(
    'headers_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _scriptsJsonMeta = const VerificationMeta(
    'scriptsJson',
  );
  @override
  late final GeneratedColumn<String> scriptsJson = GeneratedColumn<String>(
    'scripts_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    collectionId,
    headersJson,
    scriptsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection_defaults';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionDefault> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    }
    if (data.containsKey('headers_json')) {
      context.handle(
        _headersJsonMeta,
        headersJson.isAcceptableOrUnknown(
          data['headers_json']!,
          _headersJsonMeta,
        ),
      );
    }
    if (data.containsKey('scripts_json')) {
      context.handle(
        _scriptsJsonMeta,
        scriptsJson.isAcceptableOrUnknown(
          data['scripts_json']!,
          _scriptsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {collectionId};
  @override
  CollectionDefault map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionDefault(
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}collection_id'],
      )!,
      headersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}headers_json'],
      )!,
      scriptsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scripts_json'],
      )!,
    );
  }

  @override
  $CollectionDefaultsTable createAlias(String alias) {
    return $CollectionDefaultsTable(attachedDatabase, alias);
  }
}

class CollectionDefault extends DataClass
    implements Insertable<CollectionDefault> {
  final int collectionId;
  final String headersJson;
  final String scriptsJson;
  const CollectionDefault({
    required this.collectionId,
    required this.headersJson,
    required this.scriptsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['collection_id'] = Variable<int>(collectionId);
    map['headers_json'] = Variable<String>(headersJson);
    map['scripts_json'] = Variable<String>(scriptsJson);
    return map;
  }

  CollectionDefaultsCompanion toCompanion(bool nullToAbsent) {
    return CollectionDefaultsCompanion(
      collectionId: Value(collectionId),
      headersJson: Value(headersJson),
      scriptsJson: Value(scriptsJson),
    );
  }

  factory CollectionDefault.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionDefault(
      collectionId: serializer.fromJson<int>(json['collectionId']),
      headersJson: serializer.fromJson<String>(json['headersJson']),
      scriptsJson: serializer.fromJson<String>(json['scriptsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'collectionId': serializer.toJson<int>(collectionId),
      'headersJson': serializer.toJson<String>(headersJson),
      'scriptsJson': serializer.toJson<String>(scriptsJson),
    };
  }

  CollectionDefault copyWith({
    int? collectionId,
    String? headersJson,
    String? scriptsJson,
  }) => CollectionDefault(
    collectionId: collectionId ?? this.collectionId,
    headersJson: headersJson ?? this.headersJson,
    scriptsJson: scriptsJson ?? this.scriptsJson,
  );
  CollectionDefault copyWithCompanion(CollectionDefaultsCompanion data) {
    return CollectionDefault(
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      headersJson: data.headersJson.present
          ? data.headersJson.value
          : this.headersJson,
      scriptsJson: data.scriptsJson.present
          ? data.scriptsJson.value
          : this.scriptsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionDefault(')
          ..write('collectionId: $collectionId, ')
          ..write('headersJson: $headersJson, ')
          ..write('scriptsJson: $scriptsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(collectionId, headersJson, scriptsJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionDefault &&
          other.collectionId == this.collectionId &&
          other.headersJson == this.headersJson &&
          other.scriptsJson == this.scriptsJson);
}

class CollectionDefaultsCompanion extends UpdateCompanion<CollectionDefault> {
  final Value<int> collectionId;
  final Value<String> headersJson;
  final Value<String> scriptsJson;
  const CollectionDefaultsCompanion({
    this.collectionId = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.scriptsJson = const Value.absent(),
  });
  CollectionDefaultsCompanion.insert({
    this.collectionId = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.scriptsJson = const Value.absent(),
  });
  static Insertable<CollectionDefault> custom({
    Expression<int>? collectionId,
    Expression<String>? headersJson,
    Expression<String>? scriptsJson,
  }) {
    return RawValuesInsertable({
      if (collectionId != null) 'collection_id': collectionId,
      if (headersJson != null) 'headers_json': headersJson,
      if (scriptsJson != null) 'scripts_json': scriptsJson,
    });
  }

  CollectionDefaultsCompanion copyWith({
    Value<int>? collectionId,
    Value<String>? headersJson,
    Value<String>? scriptsJson,
  }) {
    return CollectionDefaultsCompanion(
      collectionId: collectionId ?? this.collectionId,
      headersJson: headersJson ?? this.headersJson,
      scriptsJson: scriptsJson ?? this.scriptsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (collectionId.present) {
      map['collection_id'] = Variable<int>(collectionId.value);
    }
    if (headersJson.present) {
      map['headers_json'] = Variable<String>(headersJson.value);
    }
    if (scriptsJson.present) {
      map['scripts_json'] = Variable<String>(scriptsJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionDefaultsCompanion(')
          ..write('collectionId: $collectionId, ')
          ..write('headersJson: $headersJson, ')
          ..write('scriptsJson: $scriptsJson')
          ..write(')'))
        .toString();
  }
}

class $HistoryPayloadsTable extends HistoryPayloads
    with TableInfo<$HistoryPayloadsTable, HistoryPayload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryPayloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _historyIdMeta = const VerificationMeta(
    'historyId',
  );
  @override
  late final GeneratedColumn<int> historyId = GeneratedColumn<int>(
    'history_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES history_entries (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _requestJsonMeta = const VerificationMeta(
    'requestJson',
  );
  @override
  late final GeneratedColumn<String> requestJson = GeneratedColumn<String>(
    'request_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _responseTextMeta = const VerificationMeta(
    'responseText',
  );
  @override
  late final GeneratedColumn<String> responseText = GeneratedColumn<String>(
    'response_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _responseContentTypeMeta =
      const VerificationMeta('responseContentType');
  @override
  late final GeneratedColumn<String> responseContentType =
      GeneratedColumn<String>(
        'response_content_type',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _responseTruncatedMeta = const VerificationMeta(
    'responseTruncated',
  );
  @override
  late final GeneratedColumn<bool> responseTruncated = GeneratedColumn<bool>(
    'response_truncated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("response_truncated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    historyId,
    requestJson,
    responseText,
    responseContentType,
    responseTruncated,
    searchText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_payloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryPayload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('history_id')) {
      context.handle(
        _historyIdMeta,
        historyId.isAcceptableOrUnknown(data['history_id']!, _historyIdMeta),
      );
    }
    if (data.containsKey('request_json')) {
      context.handle(
        _requestJsonMeta,
        requestJson.isAcceptableOrUnknown(
          data['request_json']!,
          _requestJsonMeta,
        ),
      );
    }
    if (data.containsKey('response_text')) {
      context.handle(
        _responseTextMeta,
        responseText.isAcceptableOrUnknown(
          data['response_text']!,
          _responseTextMeta,
        ),
      );
    }
    if (data.containsKey('response_content_type')) {
      context.handle(
        _responseContentTypeMeta,
        responseContentType.isAcceptableOrUnknown(
          data['response_content_type']!,
          _responseContentTypeMeta,
        ),
      );
    }
    if (data.containsKey('response_truncated')) {
      context.handle(
        _responseTruncatedMeta,
        responseTruncated.isAcceptableOrUnknown(
          data['response_truncated']!,
          _responseTruncatedMeta,
        ),
      );
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {historyId};
  @override
  HistoryPayload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryPayload(
      historyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}history_id'],
      )!,
      requestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_json'],
      )!,
      responseText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}response_text'],
      ),
      responseContentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}response_content_type'],
      ),
      responseTruncated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}response_truncated'],
      )!,
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      )!,
    );
  }

  @override
  $HistoryPayloadsTable createAlias(String alias) {
    return $HistoryPayloadsTable(attachedDatabase, alias);
  }
}

class HistoryPayload extends DataClass implements Insertable<HistoryPayload> {
  final int historyId;

  /// The request snapshot (method, url, headers, params, body, auth type, name, collection).
  final String requestJson;
  final String? responseText;
  final String? responseContentType;

  /// The response was longer than what is kept.
  final bool responseTruncated;

  /// Lower-cased method, url, name, status and a body excerpt: what the search box matches.
  final String searchText;
  const HistoryPayload({
    required this.historyId,
    required this.requestJson,
    this.responseText,
    this.responseContentType,
    required this.responseTruncated,
    required this.searchText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['history_id'] = Variable<int>(historyId);
    map['request_json'] = Variable<String>(requestJson);
    if (!nullToAbsent || responseText != null) {
      map['response_text'] = Variable<String>(responseText);
    }
    if (!nullToAbsent || responseContentType != null) {
      map['response_content_type'] = Variable<String>(responseContentType);
    }
    map['response_truncated'] = Variable<bool>(responseTruncated);
    map['search_text'] = Variable<String>(searchText);
    return map;
  }

  HistoryPayloadsCompanion toCompanion(bool nullToAbsent) {
    return HistoryPayloadsCompanion(
      historyId: Value(historyId),
      requestJson: Value(requestJson),
      responseText: responseText == null && nullToAbsent
          ? const Value.absent()
          : Value(responseText),
      responseContentType: responseContentType == null && nullToAbsent
          ? const Value.absent()
          : Value(responseContentType),
      responseTruncated: Value(responseTruncated),
      searchText: Value(searchText),
    );
  }

  factory HistoryPayload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryPayload(
      historyId: serializer.fromJson<int>(json['historyId']),
      requestJson: serializer.fromJson<String>(json['requestJson']),
      responseText: serializer.fromJson<String?>(json['responseText']),
      responseContentType: serializer.fromJson<String?>(
        json['responseContentType'],
      ),
      responseTruncated: serializer.fromJson<bool>(json['responseTruncated']),
      searchText: serializer.fromJson<String>(json['searchText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'historyId': serializer.toJson<int>(historyId),
      'requestJson': serializer.toJson<String>(requestJson),
      'responseText': serializer.toJson<String?>(responseText),
      'responseContentType': serializer.toJson<String?>(responseContentType),
      'responseTruncated': serializer.toJson<bool>(responseTruncated),
      'searchText': serializer.toJson<String>(searchText),
    };
  }

  HistoryPayload copyWith({
    int? historyId,
    String? requestJson,
    Value<String?> responseText = const Value.absent(),
    Value<String?> responseContentType = const Value.absent(),
    bool? responseTruncated,
    String? searchText,
  }) => HistoryPayload(
    historyId: historyId ?? this.historyId,
    requestJson: requestJson ?? this.requestJson,
    responseText: responseText.present ? responseText.value : this.responseText,
    responseContentType: responseContentType.present
        ? responseContentType.value
        : this.responseContentType,
    responseTruncated: responseTruncated ?? this.responseTruncated,
    searchText: searchText ?? this.searchText,
  );
  HistoryPayload copyWithCompanion(HistoryPayloadsCompanion data) {
    return HistoryPayload(
      historyId: data.historyId.present ? data.historyId.value : this.historyId,
      requestJson: data.requestJson.present
          ? data.requestJson.value
          : this.requestJson,
      responseText: data.responseText.present
          ? data.responseText.value
          : this.responseText,
      responseContentType: data.responseContentType.present
          ? data.responseContentType.value
          : this.responseContentType,
      responseTruncated: data.responseTruncated.present
          ? data.responseTruncated.value
          : this.responseTruncated,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryPayload(')
          ..write('historyId: $historyId, ')
          ..write('requestJson: $requestJson, ')
          ..write('responseText: $responseText, ')
          ..write('responseContentType: $responseContentType, ')
          ..write('responseTruncated: $responseTruncated, ')
          ..write('searchText: $searchText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    historyId,
    requestJson,
    responseText,
    responseContentType,
    responseTruncated,
    searchText,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryPayload &&
          other.historyId == this.historyId &&
          other.requestJson == this.requestJson &&
          other.responseText == this.responseText &&
          other.responseContentType == this.responseContentType &&
          other.responseTruncated == this.responseTruncated &&
          other.searchText == this.searchText);
}

class HistoryPayloadsCompanion extends UpdateCompanion<HistoryPayload> {
  final Value<int> historyId;
  final Value<String> requestJson;
  final Value<String?> responseText;
  final Value<String?> responseContentType;
  final Value<bool> responseTruncated;
  final Value<String> searchText;
  const HistoryPayloadsCompanion({
    this.historyId = const Value.absent(),
    this.requestJson = const Value.absent(),
    this.responseText = const Value.absent(),
    this.responseContentType = const Value.absent(),
    this.responseTruncated = const Value.absent(),
    this.searchText = const Value.absent(),
  });
  HistoryPayloadsCompanion.insert({
    this.historyId = const Value.absent(),
    this.requestJson = const Value.absent(),
    this.responseText = const Value.absent(),
    this.responseContentType = const Value.absent(),
    this.responseTruncated = const Value.absent(),
    this.searchText = const Value.absent(),
  });
  static Insertable<HistoryPayload> custom({
    Expression<int>? historyId,
    Expression<String>? requestJson,
    Expression<String>? responseText,
    Expression<String>? responseContentType,
    Expression<bool>? responseTruncated,
    Expression<String>? searchText,
  }) {
    return RawValuesInsertable({
      if (historyId != null) 'history_id': historyId,
      if (requestJson != null) 'request_json': requestJson,
      if (responseText != null) 'response_text': responseText,
      if (responseContentType != null)
        'response_content_type': responseContentType,
      if (responseTruncated != null) 'response_truncated': responseTruncated,
      if (searchText != null) 'search_text': searchText,
    });
  }

  HistoryPayloadsCompanion copyWith({
    Value<int>? historyId,
    Value<String>? requestJson,
    Value<String?>? responseText,
    Value<String?>? responseContentType,
    Value<bool>? responseTruncated,
    Value<String>? searchText,
  }) {
    return HistoryPayloadsCompanion(
      historyId: historyId ?? this.historyId,
      requestJson: requestJson ?? this.requestJson,
      responseText: responseText ?? this.responseText,
      responseContentType: responseContentType ?? this.responseContentType,
      responseTruncated: responseTruncated ?? this.responseTruncated,
      searchText: searchText ?? this.searchText,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (historyId.present) {
      map['history_id'] = Variable<int>(historyId.value);
    }
    if (requestJson.present) {
      map['request_json'] = Variable<String>(requestJson.value);
    }
    if (responseText.present) {
      map['response_text'] = Variable<String>(responseText.value);
    }
    if (responseContentType.present) {
      map['response_content_type'] = Variable<String>(
        responseContentType.value,
      );
    }
    if (responseTruncated.present) {
      map['response_truncated'] = Variable<bool>(responseTruncated.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryPayloadsCompanion(')
          ..write('historyId: $historyId, ')
          ..write('requestJson: $requestJson, ')
          ..write('responseText: $responseText, ')
          ..write('responseContentType: $responseContentType, ')
          ..write('responseTruncated: $responseTruncated, ')
          ..write('searchText: $searchText')
          ..write(')'))
        .toString();
  }
}

class $RunRecordsTable extends RunRecords
    with TableInfo<$RunRecordsTable, RunRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RunRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<int> collectionId = GeneratedColumn<int>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _environmentNameMeta = const VerificationMeta(
    'environmentName',
  );
  @override
  late final GeneratedColumn<String> environmentName = GeneratedColumn<String>(
    'environment_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('app'),
  );
  static const VerificationMeta _passedMeta = const VerificationMeta('passed');
  @override
  late final GeneratedColumn<int> passed = GeneratedColumn<int>(
    'passed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _failedMeta = const VerificationMeta('failed');
  @override
  late final GeneratedColumn<int> failed = GeneratedColumn<int>(
    'failed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _skippedMeta = const VerificationMeta(
    'skipped',
  );
  @override
  late final GeneratedColumn<int> skipped = GeneratedColumn<int>(
    'skipped',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _summaryJsonMeta = const VerificationMeta(
    'summaryJson',
  );
  @override
  late final GeneratedColumn<String> summaryJson = GeneratedColumn<String>(
    'summary_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _resultsJsonMeta = const VerificationMeta(
    'resultsJson',
  );
  @override
  late final GeneratedColumn<String> resultsJson = GeneratedColumn<String>(
    'results_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    collectionId,
    environmentName,
    source,
    passed,
    failed,
    skipped,
    durationMs,
    summaryJson,
    resultsJson,
    startedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'run_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<RunRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('environment_name')) {
      context.handle(
        _environmentNameMeta,
        environmentName.isAcceptableOrUnknown(
          data['environment_name']!,
          _environmentNameMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('passed')) {
      context.handle(
        _passedMeta,
        passed.isAcceptableOrUnknown(data['passed']!, _passedMeta),
      );
    }
    if (data.containsKey('failed')) {
      context.handle(
        _failedMeta,
        failed.isAcceptableOrUnknown(data['failed']!, _failedMeta),
      );
    }
    if (data.containsKey('skipped')) {
      context.handle(
        _skippedMeta,
        skipped.isAcceptableOrUnknown(data['skipped']!, _skippedMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('summary_json')) {
      context.handle(
        _summaryJsonMeta,
        summaryJson.isAcceptableOrUnknown(
          data['summary_json']!,
          _summaryJsonMeta,
        ),
      );
    }
    if (data.containsKey('results_json')) {
      context.handle(
        _resultsJsonMeta,
        resultsJson.isAcceptableOrUnknown(
          data['results_json']!,
          _resultsJsonMeta,
        ),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RunRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RunRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}collection_id'],
      )!,
      environmentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}environment_name'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      passed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}passed'],
      )!,
      failed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failed'],
      )!,
      skipped: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}skipped'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      summaryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_json'],
      )!,
      resultsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}results_json'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
    );
  }

  @override
  $RunRecordsTable createAlias(String alias) {
    return $RunRecordsTable(attachedDatabase, alias);
  }
}

class RunRecord extends DataClass implements Insertable<RunRecord> {
  final int id;
  final int collectionId;
  final String environmentName;

  /// 'app' or 'cli'.
  final String source;
  final int passed;
  final int failed;
  final int skipped;
  final int durationMs;
  final String summaryJson;

  /// Per request/iteration results (name, method, url template, status, assertion messages, duration).
  final String resultsJson;
  final DateTime startedAt;
  const RunRecord({
    required this.id,
    required this.collectionId,
    required this.environmentName,
    required this.source,
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.durationMs,
    required this.summaryJson,
    required this.resultsJson,
    required this.startedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['collection_id'] = Variable<int>(collectionId);
    map['environment_name'] = Variable<String>(environmentName);
    map['source'] = Variable<String>(source);
    map['passed'] = Variable<int>(passed);
    map['failed'] = Variable<int>(failed);
    map['skipped'] = Variable<int>(skipped);
    map['duration_ms'] = Variable<int>(durationMs);
    map['summary_json'] = Variable<String>(summaryJson);
    map['results_json'] = Variable<String>(resultsJson);
    map['started_at'] = Variable<DateTime>(startedAt);
    return map;
  }

  RunRecordsCompanion toCompanion(bool nullToAbsent) {
    return RunRecordsCompanion(
      id: Value(id),
      collectionId: Value(collectionId),
      environmentName: Value(environmentName),
      source: Value(source),
      passed: Value(passed),
      failed: Value(failed),
      skipped: Value(skipped),
      durationMs: Value(durationMs),
      summaryJson: Value(summaryJson),
      resultsJson: Value(resultsJson),
      startedAt: Value(startedAt),
    );
  }

  factory RunRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RunRecord(
      id: serializer.fromJson<int>(json['id']),
      collectionId: serializer.fromJson<int>(json['collectionId']),
      environmentName: serializer.fromJson<String>(json['environmentName']),
      source: serializer.fromJson<String>(json['source']),
      passed: serializer.fromJson<int>(json['passed']),
      failed: serializer.fromJson<int>(json['failed']),
      skipped: serializer.fromJson<int>(json['skipped']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      summaryJson: serializer.fromJson<String>(json['summaryJson']),
      resultsJson: serializer.fromJson<String>(json['resultsJson']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'collectionId': serializer.toJson<int>(collectionId),
      'environmentName': serializer.toJson<String>(environmentName),
      'source': serializer.toJson<String>(source),
      'passed': serializer.toJson<int>(passed),
      'failed': serializer.toJson<int>(failed),
      'skipped': serializer.toJson<int>(skipped),
      'durationMs': serializer.toJson<int>(durationMs),
      'summaryJson': serializer.toJson<String>(summaryJson),
      'resultsJson': serializer.toJson<String>(resultsJson),
      'startedAt': serializer.toJson<DateTime>(startedAt),
    };
  }

  RunRecord copyWith({
    int? id,
    int? collectionId,
    String? environmentName,
    String? source,
    int? passed,
    int? failed,
    int? skipped,
    int? durationMs,
    String? summaryJson,
    String? resultsJson,
    DateTime? startedAt,
  }) => RunRecord(
    id: id ?? this.id,
    collectionId: collectionId ?? this.collectionId,
    environmentName: environmentName ?? this.environmentName,
    source: source ?? this.source,
    passed: passed ?? this.passed,
    failed: failed ?? this.failed,
    skipped: skipped ?? this.skipped,
    durationMs: durationMs ?? this.durationMs,
    summaryJson: summaryJson ?? this.summaryJson,
    resultsJson: resultsJson ?? this.resultsJson,
    startedAt: startedAt ?? this.startedAt,
  );
  RunRecord copyWithCompanion(RunRecordsCompanion data) {
    return RunRecord(
      id: data.id.present ? data.id.value : this.id,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      environmentName: data.environmentName.present
          ? data.environmentName.value
          : this.environmentName,
      source: data.source.present ? data.source.value : this.source,
      passed: data.passed.present ? data.passed.value : this.passed,
      failed: data.failed.present ? data.failed.value : this.failed,
      skipped: data.skipped.present ? data.skipped.value : this.skipped,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      summaryJson: data.summaryJson.present
          ? data.summaryJson.value
          : this.summaryJson,
      resultsJson: data.resultsJson.present
          ? data.resultsJson.value
          : this.resultsJson,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RunRecord(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('environmentName: $environmentName, ')
          ..write('source: $source, ')
          ..write('passed: $passed, ')
          ..write('failed: $failed, ')
          ..write('skipped: $skipped, ')
          ..write('durationMs: $durationMs, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('resultsJson: $resultsJson, ')
          ..write('startedAt: $startedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    collectionId,
    environmentName,
    source,
    passed,
    failed,
    skipped,
    durationMs,
    summaryJson,
    resultsJson,
    startedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RunRecord &&
          other.id == this.id &&
          other.collectionId == this.collectionId &&
          other.environmentName == this.environmentName &&
          other.source == this.source &&
          other.passed == this.passed &&
          other.failed == this.failed &&
          other.skipped == this.skipped &&
          other.durationMs == this.durationMs &&
          other.summaryJson == this.summaryJson &&
          other.resultsJson == this.resultsJson &&
          other.startedAt == this.startedAt);
}

class RunRecordsCompanion extends UpdateCompanion<RunRecord> {
  final Value<int> id;
  final Value<int> collectionId;
  final Value<String> environmentName;
  final Value<String> source;
  final Value<int> passed;
  final Value<int> failed;
  final Value<int> skipped;
  final Value<int> durationMs;
  final Value<String> summaryJson;
  final Value<String> resultsJson;
  final Value<DateTime> startedAt;
  const RunRecordsCompanion({
    this.id = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.environmentName = const Value.absent(),
    this.source = const Value.absent(),
    this.passed = const Value.absent(),
    this.failed = const Value.absent(),
    this.skipped = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.summaryJson = const Value.absent(),
    this.resultsJson = const Value.absent(),
    this.startedAt = const Value.absent(),
  });
  RunRecordsCompanion.insert({
    this.id = const Value.absent(),
    required int collectionId,
    this.environmentName = const Value.absent(),
    this.source = const Value.absent(),
    this.passed = const Value.absent(),
    this.failed = const Value.absent(),
    this.skipped = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.summaryJson = const Value.absent(),
    this.resultsJson = const Value.absent(),
    this.startedAt = const Value.absent(),
  }) : collectionId = Value(collectionId);
  static Insertable<RunRecord> custom({
    Expression<int>? id,
    Expression<int>? collectionId,
    Expression<String>? environmentName,
    Expression<String>? source,
    Expression<int>? passed,
    Expression<int>? failed,
    Expression<int>? skipped,
    Expression<int>? durationMs,
    Expression<String>? summaryJson,
    Expression<String>? resultsJson,
    Expression<DateTime>? startedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collectionId != null) 'collection_id': collectionId,
      if (environmentName != null) 'environment_name': environmentName,
      if (source != null) 'source': source,
      if (passed != null) 'passed': passed,
      if (failed != null) 'failed': failed,
      if (skipped != null) 'skipped': skipped,
      if (durationMs != null) 'duration_ms': durationMs,
      if (summaryJson != null) 'summary_json': summaryJson,
      if (resultsJson != null) 'results_json': resultsJson,
      if (startedAt != null) 'started_at': startedAt,
    });
  }

  RunRecordsCompanion copyWith({
    Value<int>? id,
    Value<int>? collectionId,
    Value<String>? environmentName,
    Value<String>? source,
    Value<int>? passed,
    Value<int>? failed,
    Value<int>? skipped,
    Value<int>? durationMs,
    Value<String>? summaryJson,
    Value<String>? resultsJson,
    Value<DateTime>? startedAt,
  }) {
    return RunRecordsCompanion(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      environmentName: environmentName ?? this.environmentName,
      source: source ?? this.source,
      passed: passed ?? this.passed,
      failed: failed ?? this.failed,
      skipped: skipped ?? this.skipped,
      durationMs: durationMs ?? this.durationMs,
      summaryJson: summaryJson ?? this.summaryJson,
      resultsJson: resultsJson ?? this.resultsJson,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<int>(collectionId.value);
    }
    if (environmentName.present) {
      map['environment_name'] = Variable<String>(environmentName.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (passed.present) {
      map['passed'] = Variable<int>(passed.value);
    }
    if (failed.present) {
      map['failed'] = Variable<int>(failed.value);
    }
    if (skipped.present) {
      map['skipped'] = Variable<int>(skipped.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (summaryJson.present) {
      map['summary_json'] = Variable<String>(summaryJson.value);
    }
    if (resultsJson.present) {
      map['results_json'] = Variable<String>(resultsJson.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RunRecordsCompanion(')
          ..write('id: $id, ')
          ..write('collectionId: $collectionId, ')
          ..write('environmentName: $environmentName, ')
          ..write('source: $source, ')
          ..write('passed: $passed, ')
          ..write('failed: $failed, ')
          ..write('skipped: $skipped, ')
          ..write('durationMs: $durationMs, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('resultsJson: $resultsJson, ')
          ..write('startedAt: $startedAt')
          ..write(')'))
        .toString();
  }
}

class $RequestBaselinesTable extends RequestBaselines
    with TableInfo<$RequestBaselinesTable, RequestBaseline> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RequestBaselinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<int> requestId = GeneratedColumn<int>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES requests (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _snapshotJsonMeta = const VerificationMeta(
    'snapshotJson',
  );
  @override
  late final GeneratedColumn<String> snapshotJson = GeneratedColumn<String>(
    'snapshot_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    requestId,
    snapshotJson,
    note,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'request_baselines';
  @override
  VerificationContext validateIntegrity(
    Insertable<RequestBaseline> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('snapshot_json')) {
      context.handle(
        _snapshotJsonMeta,
        snapshotJson.isAcceptableOrUnknown(
          data['snapshot_json']!,
          _snapshotJsonMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {requestId};
  @override
  RequestBaseline map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RequestBaseline(
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}request_id'],
      )!,
      snapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_json'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $RequestBaselinesTable createAlias(String alias) {
    return $RequestBaselinesTable(attachedDatabase, alias);
  }
}

class RequestBaseline extends DataClass implements Insertable<RequestBaseline> {
  final int requestId;
  final String snapshotJson;
  final String note;
  final DateTime recordedAt;
  const RequestBaseline({
    required this.requestId,
    required this.snapshotJson,
    required this.note,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['request_id'] = Variable<int>(requestId);
    map['snapshot_json'] = Variable<String>(snapshotJson);
    map['note'] = Variable<String>(note);
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    return map;
  }

  RequestBaselinesCompanion toCompanion(bool nullToAbsent) {
    return RequestBaselinesCompanion(
      requestId: Value(requestId),
      snapshotJson: Value(snapshotJson),
      note: Value(note),
      recordedAt: Value(recordedAt),
    );
  }

  factory RequestBaseline.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RequestBaseline(
      requestId: serializer.fromJson<int>(json['requestId']),
      snapshotJson: serializer.fromJson<String>(json['snapshotJson']),
      note: serializer.fromJson<String>(json['note']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'requestId': serializer.toJson<int>(requestId),
      'snapshotJson': serializer.toJson<String>(snapshotJson),
      'note': serializer.toJson<String>(note),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
    };
  }

  RequestBaseline copyWith({
    int? requestId,
    String? snapshotJson,
    String? note,
    DateTime? recordedAt,
  }) => RequestBaseline(
    requestId: requestId ?? this.requestId,
    snapshotJson: snapshotJson ?? this.snapshotJson,
    note: note ?? this.note,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  RequestBaseline copyWithCompanion(RequestBaselinesCompanion data) {
    return RequestBaseline(
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      snapshotJson: data.snapshotJson.present
          ? data.snapshotJson.value
          : this.snapshotJson,
      note: data.note.present ? data.note.value : this.note,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RequestBaseline(')
          ..write('requestId: $requestId, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('note: $note, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(requestId, snapshotJson, note, recordedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestBaseline &&
          other.requestId == this.requestId &&
          other.snapshotJson == this.snapshotJson &&
          other.note == this.note &&
          other.recordedAt == this.recordedAt);
}

class RequestBaselinesCompanion extends UpdateCompanion<RequestBaseline> {
  final Value<int> requestId;
  final Value<String> snapshotJson;
  final Value<String> note;
  final Value<DateTime> recordedAt;
  const RequestBaselinesCompanion({
    this.requestId = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.note = const Value.absent(),
    this.recordedAt = const Value.absent(),
  });
  RequestBaselinesCompanion.insert({
    this.requestId = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.note = const Value.absent(),
    this.recordedAt = const Value.absent(),
  });
  static Insertable<RequestBaseline> custom({
    Expression<int>? requestId,
    Expression<String>? snapshotJson,
    Expression<String>? note,
    Expression<DateTime>? recordedAt,
  }) {
    return RawValuesInsertable({
      if (requestId != null) 'request_id': requestId,
      if (snapshotJson != null) 'snapshot_json': snapshotJson,
      if (note != null) 'note': note,
      if (recordedAt != null) 'recorded_at': recordedAt,
    });
  }

  RequestBaselinesCompanion copyWith({
    Value<int>? requestId,
    Value<String>? snapshotJson,
    Value<String>? note,
    Value<DateTime>? recordedAt,
  }) {
    return RequestBaselinesCompanion(
      requestId: requestId ?? this.requestId,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      note: note ?? this.note,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (requestId.present) {
      map['request_id'] = Variable<int>(requestId.value);
    }
    if (snapshotJson.present) {
      map['snapshot_json'] = Variable<String>(snapshotJson.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RequestBaselinesCompanion(')
          ..write('requestId: $requestId, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('note: $note, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $RequestsTable requests = $RequestsTable(this);
  late final $EnvironmentsTable environments = $EnvironmentsTable(this);
  late final $EnvironmentVariablesTable environmentVariables =
      $EnvironmentVariablesTable(this);
  late final $HistoryEntriesTable historyEntries = $HistoryEntriesTable(this);
  late final $GlobalVariablesTable globalVariables = $GlobalVariablesTable(
    this,
  );
  late final $CollectionVariablesTable collectionVariables =
      $CollectionVariablesTable(this);
  late final $CollectionAuthTable collectionAuth = $CollectionAuthTable(this);
  late final $RequestScriptsTable requestScripts = $RequestScriptsTable(this);
  late final $ResponseExamplesTable responseExamples = $ResponseExamplesTable(
    this,
  );
  late final $EntityUidsTable entityUids = $EntityUidsTable(this);
  late final $GitLinksTable gitLinks = $GitLinksTable(this);
  late final $GitBaseEntriesTable gitBaseEntries = $GitBaseEntriesTable(this);
  late final $SettingEntriesTable settingEntries = $SettingEntriesTable(this);
  late final $RequestSettingEntriesTable requestSettingEntries =
      $RequestSettingEntriesTable(this);
  late final $EntityDocsTable entityDocs = $EntityDocsTable(this);
  late final $EntityTagsTable entityTags = $EntityTagsTable(this);
  late final $FolderDefaultsTable folderDefaults = $FolderDefaultsTable(this);
  late final $CollectionDefaultsTable collectionDefaults =
      $CollectionDefaultsTable(this);
  late final $HistoryPayloadsTable historyPayloads = $HistoryPayloadsTable(
    this,
  );
  late final $RunRecordsTable runRecords = $RunRecordsTable(this);
  late final $RequestBaselinesTable requestBaselines = $RequestBaselinesTable(
    this,
  );
  late final Index collectionVariablesCollectionId = Index(
    'collection_variables_collection_id',
    'CREATE INDEX collection_variables_collection_id ON collection_variables (collection_id)',
  );
  late final Index responseExamplesRequestId = Index(
    'response_examples_request_id',
    'CREATE INDEX response_examples_request_id ON response_examples (request_id)',
  );
  late final Index entityUidsUid = Index(
    'entity_uids_uid',
    'CREATE UNIQUE INDEX entity_uids_uid ON entity_uids (uid)',
  );
  late final Index entityTagsTag = Index(
    'entity_tags_tag',
    'CREATE INDEX entity_tags_tag ON entity_tags (tag)',
  );
  late final CollectionsDao collectionsDao = CollectionsDao(
    this as AppDatabase,
  );
  late final RequestsDao requestsDao = RequestsDao(this as AppDatabase);
  late final EnvironmentsDao environmentsDao = EnvironmentsDao(
    this as AppDatabase,
  );
  late final HistoryDao historyDao = HistoryDao(this as AppDatabase);
  late final GlobalVariablesDao globalVariablesDao = GlobalVariablesDao(
    this as AppDatabase,
  );
  late final CollectionVariablesDao collectionVariablesDao =
      CollectionVariablesDao(this as AppDatabase);
  late final CollectionAuthDao collectionAuthDao = CollectionAuthDao(
    this as AppDatabase,
  );
  late final RequestScriptsDao requestScriptsDao = RequestScriptsDao(
    this as AppDatabase,
  );
  late final ResponseExamplesDao responseExamplesDao = ResponseExamplesDao(
    this as AppDatabase,
  );
  late final EntityUidsDao entityUidsDao = EntityUidsDao(this as AppDatabase);
  late final GitLinksDao gitLinksDao = GitLinksDao(this as AppDatabase);
  late final SettingsDao settingsDao = SettingsDao(this as AppDatabase);
  late final RequestSettingsDao requestSettingsDao = RequestSettingsDao(
    this as AppDatabase,
  );
  late final EntityDocsDao entityDocsDao = EntityDocsDao(this as AppDatabase);
  late final EntityTagsDao entityTagsDao = EntityTagsDao(this as AppDatabase);
  late final FolderDefaultsDao folderDefaultsDao = FolderDefaultsDao(
    this as AppDatabase,
  );
  late final CollectionDefaultsDao collectionDefaultsDao =
      CollectionDefaultsDao(this as AppDatabase);
  late final HistoryPayloadsDao historyPayloadsDao = HistoryPayloadsDao(
    this as AppDatabase,
  );
  late final RunRecordsDao runRecordsDao = RunRecordsDao(this as AppDatabase);
  late final RequestBaselinesDao requestBaselinesDao = RequestBaselinesDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    collections,
    folders,
    requests,
    environments,
    environmentVariables,
    historyEntries,
    globalVariables,
    collectionVariables,
    collectionAuth,
    requestScripts,
    responseExamples,
    entityUids,
    gitLinks,
    gitBaseEntries,
    settingEntries,
    requestSettingEntries,
    entityDocs,
    entityTags,
    folderDefaults,
    collectionDefaults,
    historyPayloads,
    runRecords,
    requestBaselines,
    collectionVariablesCollectionId,
    responseExamplesRequestId,
    entityUidsUid,
    entityTagsTag,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('folders', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'folders',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('folders', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('requests', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'folders',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('requests', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'environments',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('environment_variables', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('collection_variables', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('collection_auth', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'requests',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('request_scripts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'requests',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('response_examples', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('git_links', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'git_links',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('git_base_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'requests',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('request_setting_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'folders',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('folder_defaults', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('collection_defaults', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'history_entries',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('history_payloads', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('run_records', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'requests',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('request_baselines', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$CollectionsTableCreateCompanionBuilder =
    CollectionsCompanion Function({
      Value<int> id,
      required String name,
      Value<int?> forkedFromId,
      Value<DateTime> createdAt,
    });
typedef $$CollectionsTableUpdateCompanionBuilder =
    CollectionsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int?> forkedFromId,
      Value<DateTime> createdAt,
    });

final class $$CollectionsTableReferences
    extends BaseReferences<_$AppDatabase, $CollectionsTable, Collection> {
  $$CollectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FoldersTable, List<Folder>> _foldersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.folders,
    aliasName: 'collections__id__folders__collection_id',
  );

  $$FoldersTableProcessedTableManager get foldersRefs {
    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_foldersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RequestsTable, List<Request>> _requestsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.requests,
    aliasName: 'collections__id__requests__collection_id',
  );

  $$RequestsTableProcessedTableManager get requestsRefs {
    final manager = $$RequestsTableTableManager(
      $_db,
      $_db.requests,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_requestsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $CollectionVariablesTable,
    List<CollectionVariable>
  >
  _collectionVariablesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.collectionVariables,
        aliasName: 'collections__id__collection_variables__collection_id',
      );

  $$CollectionVariablesTableProcessedTableManager get collectionVariablesRefs {
    final manager = $$CollectionVariablesTableTableManager(
      $_db,
      $_db.collectionVariables,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _collectionVariablesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CollectionAuthTable, List<CollectionAuthData>>
  _collectionAuthRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.collectionAuth,
    aliasName: 'collections__id__collection_auth__collection_id',
  );

  $$CollectionAuthTableProcessedTableManager get collectionAuthRefs {
    final manager = $$CollectionAuthTableTableManager(
      $_db,
      $_db.collectionAuth,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_collectionAuthRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$GitLinksTable, List<GitLinkRow>>
  _gitLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.gitLinks,
    aliasName: 'collections__id__git_links__collection_id',
  );

  $$GitLinksTableProcessedTableManager get gitLinksRefs {
    final manager = $$GitLinksTableTableManager(
      $_db,
      $_db.gitLinks,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_gitLinksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CollectionDefaultsTable, List<CollectionDefault>>
  _collectionDefaultsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.collectionDefaults,
        aliasName: 'collections__id__collection_defaults__collection_id',
      );

  $$CollectionDefaultsTableProcessedTableManager get collectionDefaultsRefs {
    final manager = $$CollectionDefaultsTableTableManager(
      $_db,
      $_db.collectionDefaults,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _collectionDefaultsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RunRecordsTable, List<RunRecord>>
  _runRecordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.runRecords,
    aliasName: 'collections__id__run_records__collection_id',
  );

  $$RunRecordsTableProcessedTableManager get runRecordsRefs {
    final manager = $$RunRecordsTableTableManager(
      $_db,
      $_db.runRecords,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_runRecordsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CollectionsTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get forkedFromId => $composableBuilder(
    column: $table.forkedFromId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> foldersRefs(
    Expression<bool> Function($$FoldersTableFilterComposer f) f,
  ) {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> requestsRefs(
    Expression<bool> Function($$RequestsTableFilterComposer f) f,
  ) {
    final $$RequestsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableFilterComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> collectionVariablesRefs(
    Expression<bool> Function($$CollectionVariablesTableFilterComposer f) f,
  ) {
    final $$CollectionVariablesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.collectionVariables,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionVariablesTableFilterComposer(
            $db: $db,
            $table: $db.collectionVariables,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> collectionAuthRefs(
    Expression<bool> Function($$CollectionAuthTableFilterComposer f) f,
  ) {
    final $$CollectionAuthTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.collectionAuth,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionAuthTableFilterComposer(
            $db: $db,
            $table: $db.collectionAuth,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> gitLinksRefs(
    Expression<bool> Function($$GitLinksTableFilterComposer f) f,
  ) {
    final $$GitLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gitLinks,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitLinksTableFilterComposer(
            $db: $db,
            $table: $db.gitLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> collectionDefaultsRefs(
    Expression<bool> Function($$CollectionDefaultsTableFilterComposer f) f,
  ) {
    final $$CollectionDefaultsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.collectionDefaults,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionDefaultsTableFilterComposer(
            $db: $db,
            $table: $db.collectionDefaults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> runRecordsRefs(
    Expression<bool> Function($$RunRecordsTableFilterComposer f) f,
  ) {
    final $$RunRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.runRecords,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunRecordsTableFilterComposer(
            $db: $db,
            $table: $db.runRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CollectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get forkedFromId => $composableBuilder(
    column: $table.forkedFromId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get forkedFromId => $composableBuilder(
    column: $table.forkedFromId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> foldersRefs<T extends Object>(
    Expression<T> Function($$FoldersTableAnnotationComposer a) f,
  ) {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> requestsRefs<T extends Object>(
    Expression<T> Function($$RequestsTableAnnotationComposer a) f,
  ) {
    final $$RequestsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableAnnotationComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> collectionVariablesRefs<T extends Object>(
    Expression<T> Function($$CollectionVariablesTableAnnotationComposer a) f,
  ) {
    final $$CollectionVariablesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.collectionVariables,
          getReferencedColumn: (t) => t.collectionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CollectionVariablesTableAnnotationComposer(
                $db: $db,
                $table: $db.collectionVariables,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> collectionAuthRefs<T extends Object>(
    Expression<T> Function($$CollectionAuthTableAnnotationComposer a) f,
  ) {
    final $$CollectionAuthTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.collectionAuth,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionAuthTableAnnotationComposer(
            $db: $db,
            $table: $db.collectionAuth,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> gitLinksRefs<T extends Object>(
    Expression<T> Function($$GitLinksTableAnnotationComposer a) f,
  ) {
    final $$GitLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gitLinks,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.gitLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> collectionDefaultsRefs<T extends Object>(
    Expression<T> Function($$CollectionDefaultsTableAnnotationComposer a) f,
  ) {
    final $$CollectionDefaultsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.collectionDefaults,
          getReferencedColumn: (t) => t.collectionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CollectionDefaultsTableAnnotationComposer(
                $db: $db,
                $table: $db.collectionDefaults,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> runRecordsRefs<T extends Object>(
    Expression<T> Function($$RunRecordsTableAnnotationComposer a) f,
  ) {
    final $$RunRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.runRecords,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.runRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CollectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionsTable,
          Collection,
          $$CollectionsTableFilterComposer,
          $$CollectionsTableOrderingComposer,
          $$CollectionsTableAnnotationComposer,
          $$CollectionsTableCreateCompanionBuilder,
          $$CollectionsTableUpdateCompanionBuilder,
          (Collection, $$CollectionsTableReferences),
          Collection,
          PrefetchHooks Function({
            bool foldersRefs,
            bool requestsRefs,
            bool collectionVariablesRefs,
            bool collectionAuthRefs,
            bool gitLinksRefs,
            bool collectionDefaultsRefs,
            bool runRecordsRefs,
          })
        > {
  $$CollectionsTableTableManager(_$AppDatabase db, $CollectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> forkedFromId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => CollectionsCompanion(
                id: id,
                name: name,
                forkedFromId: forkedFromId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<int?> forkedFromId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => CollectionsCompanion.insert(
                id: id,
                name: name,
                forkedFromId: forkedFromId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CollectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                foldersRefs = false,
                requestsRefs = false,
                collectionVariablesRefs = false,
                collectionAuthRefs = false,
                gitLinksRefs = false,
                collectionDefaultsRefs = false,
                runRecordsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (foldersRefs) db.folders,
                    if (requestsRefs) db.requests,
                    if (collectionVariablesRefs) db.collectionVariables,
                    if (collectionAuthRefs) db.collectionAuth,
                    if (gitLinksRefs) db.gitLinks,
                    if (collectionDefaultsRefs) db.collectionDefaults,
                    if (runRecordsRefs) db.runRecords,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (foldersRefs)
                        await $_getPrefetchedData<
                          Collection,
                          $CollectionsTable,
                          Folder
                        >(
                          currentTable: table,
                          referencedTable: $$CollectionsTableReferences
                              ._foldersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CollectionsTableReferences(
                                db,
                                table,
                                p0,
                              ).foldersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.collectionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (requestsRefs)
                        await $_getPrefetchedData<
                          Collection,
                          $CollectionsTable,
                          Request
                        >(
                          currentTable: table,
                          referencedTable: $$CollectionsTableReferences
                              ._requestsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CollectionsTableReferences(
                                db,
                                table,
                                p0,
                              ).requestsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.collectionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (collectionVariablesRefs)
                        await $_getPrefetchedData<
                          Collection,
                          $CollectionsTable,
                          CollectionVariable
                        >(
                          currentTable: table,
                          referencedTable: $$CollectionsTableReferences
                              ._collectionVariablesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CollectionsTableReferences(
                                db,
                                table,
                                p0,
                              ).collectionVariablesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.collectionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (collectionAuthRefs)
                        await $_getPrefetchedData<
                          Collection,
                          $CollectionsTable,
                          CollectionAuthData
                        >(
                          currentTable: table,
                          referencedTable: $$CollectionsTableReferences
                              ._collectionAuthRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CollectionsTableReferences(
                                db,
                                table,
                                p0,
                              ).collectionAuthRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.collectionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (gitLinksRefs)
                        await $_getPrefetchedData<
                          Collection,
                          $CollectionsTable,
                          GitLinkRow
                        >(
                          currentTable: table,
                          referencedTable: $$CollectionsTableReferences
                              ._gitLinksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CollectionsTableReferences(
                                db,
                                table,
                                p0,
                              ).gitLinksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.collectionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (collectionDefaultsRefs)
                        await $_getPrefetchedData<
                          Collection,
                          $CollectionsTable,
                          CollectionDefault
                        >(
                          currentTable: table,
                          referencedTable: $$CollectionsTableReferences
                              ._collectionDefaultsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CollectionsTableReferences(
                                db,
                                table,
                                p0,
                              ).collectionDefaultsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.collectionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (runRecordsRefs)
                        await $_getPrefetchedData<
                          Collection,
                          $CollectionsTable,
                          RunRecord
                        >(
                          currentTable: table,
                          referencedTable: $$CollectionsTableReferences
                              ._runRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CollectionsTableReferences(
                                db,
                                table,
                                p0,
                              ).runRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.collectionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionsTable,
      Collection,
      $$CollectionsTableFilterComposer,
      $$CollectionsTableOrderingComposer,
      $$CollectionsTableAnnotationComposer,
      $$CollectionsTableCreateCompanionBuilder,
      $$CollectionsTableUpdateCompanionBuilder,
      (Collection, $$CollectionsTableReferences),
      Collection,
      PrefetchHooks Function({
        bool foldersRefs,
        bool requestsRefs,
        bool collectionVariablesRefs,
        bool collectionAuthRefs,
        bool gitLinksRefs,
        bool collectionDefaultsRefs,
        bool runRecordsRefs,
      })
    >;
typedef $$FoldersTableCreateCompanionBuilder =
    FoldersCompanion Function({
      Value<int> id,
      required int collectionId,
      Value<int?> parentFolderId,
      required String name,
      Value<int> orderIndex,
    });
typedef $$FoldersTableUpdateCompanionBuilder =
    FoldersCompanion Function({
      Value<int> id,
      Value<int> collectionId,
      Value<int?> parentFolderId,
      Value<String> name,
      Value<int> orderIndex,
    });

final class $$FoldersTableReferences
    extends BaseReferences<_$AppDatabase, $FoldersTable, Folder> {
  $$FoldersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) =>
      db.collections.createAlias('folders__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<int>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $FoldersTable _parentFolderIdTable(_$AppDatabase db) =>
      db.folders.createAlias('folders__parent_folder_id__folders__id');

  $$FoldersTableProcessedTableManager? get parentFolderId {
    final $_column = $_itemColumn<int>('parent_folder_id');
    if ($_column == null) return null;
    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentFolderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$RequestsTable, List<Request>> _requestsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.requests,
    aliasName: 'folders__id__requests__folder_id',
  );

  $$RequestsTableProcessedTableManager get requestsRefs {
    final manager = $$RequestsTableTableManager(
      $_db,
      $_db.requests,
    ).filter((f) => f.folderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_requestsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FolderDefaultsTable, List<FolderDefault>>
  _folderDefaultsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.folderDefaults,
    aliasName: 'folders__id__folder_defaults__folder_id',
  );

  $$FolderDefaultsTableProcessedTableManager get folderDefaultsRefs {
    final manager = $$FolderDefaultsTableTableManager(
      $_db,
      $_db.folderDefaults,
    ).filter((f) => f.folderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_folderDefaultsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FoldersTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableFilterComposer get parentFolderId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentFolderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> requestsRefs(
    Expression<bool> Function($$RequestsTableFilterComposer f) f,
  ) {
    final $$RequestsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableFilterComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> folderDefaultsRefs(
    Expression<bool> Function($$FolderDefaultsTableFilterComposer f) f,
  ) {
    final $$FolderDefaultsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.folderDefaults,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FolderDefaultsTableFilterComposer(
            $db: $db,
            $table: $db.folderDefaults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableOrderingComposer get parentFolderId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentFolderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableAnnotationComposer get parentFolderId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentFolderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> requestsRefs<T extends Object>(
    Expression<T> Function($$RequestsTableAnnotationComposer a) f,
  ) {
    final $$RequestsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableAnnotationComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> folderDefaultsRefs<T extends Object>(
    Expression<T> Function($$FolderDefaultsTableAnnotationComposer a) f,
  ) {
    final $$FolderDefaultsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.folderDefaults,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FolderDefaultsTableAnnotationComposer(
            $db: $db,
            $table: $db.folderDefaults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoldersTable,
          Folder,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (Folder, $$FoldersTableReferences),
          Folder,
          PrefetchHooks Function({
            bool collectionId,
            bool parentFolderId,
            bool requestsRefs,
            bool folderDefaultsRefs,
          })
        > {
  $$FoldersTableTableManager(_$AppDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> collectionId = const Value.absent(),
                Value<int?> parentFolderId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                collectionId: collectionId,
                parentFolderId: parentFolderId,
                name: name,
                orderIndex: orderIndex,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int collectionId,
                Value<int?> parentFolderId = const Value.absent(),
                required String name,
                Value<int> orderIndex = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                collectionId: collectionId,
                parentFolderId: parentFolderId,
                name: name,
                orderIndex: orderIndex,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FoldersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                collectionId = false,
                parentFolderId = false,
                requestsRefs = false,
                folderDefaultsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (requestsRefs) db.requests,
                    if (folderDefaultsRefs) db.folderDefaults,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (collectionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.collectionId,
                                    referencedTable: $$FoldersTableReferences
                                        ._collectionIdTable(db),
                                    referencedColumn: $$FoldersTableReferences
                                        ._collectionIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (parentFolderId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.parentFolderId,
                                    referencedTable: $$FoldersTableReferences
                                        ._parentFolderIdTable(db),
                                    referencedColumn: $$FoldersTableReferences
                                        ._parentFolderIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (requestsRefs)
                        await $_getPrefetchedData<
                          Folder,
                          $FoldersTable,
                          Request
                        >(
                          currentTable: table,
                          referencedTable: $$FoldersTableReferences
                              ._requestsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FoldersTableReferences(
                                db,
                                table,
                                p0,
                              ).requestsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.folderId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (folderDefaultsRefs)
                        await $_getPrefetchedData<
                          Folder,
                          $FoldersTable,
                          FolderDefault
                        >(
                          currentTable: table,
                          referencedTable: $$FoldersTableReferences
                              ._folderDefaultsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FoldersTableReferences(
                                db,
                                table,
                                p0,
                              ).folderDefaultsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.folderId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoldersTable,
      Folder,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (Folder, $$FoldersTableReferences),
      Folder,
      PrefetchHooks Function({
        bool collectionId,
        bool parentFolderId,
        bool requestsRefs,
        bool folderDefaultsRefs,
      })
    >;
typedef $$RequestsTableCreateCompanionBuilder =
    RequestsCompanion Function({
      Value<int> id,
      required int collectionId,
      Value<int?> folderId,
      required String name,
      Value<String> method,
      Value<String> url,
      Value<String> headersJson,
      Value<String> queryParamsJson,
      Value<String> bodyType,
      Value<String> rawContentType,
      Value<String> bodyText,
      Value<String> formFieldsJson,
      Value<String> urlEncodedFieldsJson,
      Value<String> graphqlQuery,
      Value<String> graphqlVariables,
      Value<String> authType,
      Value<String> authConfigJson,
      Value<int> orderIndex,
      Value<DateTime> updatedAt,
    });
typedef $$RequestsTableUpdateCompanionBuilder =
    RequestsCompanion Function({
      Value<int> id,
      Value<int> collectionId,
      Value<int?> folderId,
      Value<String> name,
      Value<String> method,
      Value<String> url,
      Value<String> headersJson,
      Value<String> queryParamsJson,
      Value<String> bodyType,
      Value<String> rawContentType,
      Value<String> bodyText,
      Value<String> formFieldsJson,
      Value<String> urlEncodedFieldsJson,
      Value<String> graphqlQuery,
      Value<String> graphqlVariables,
      Value<String> authType,
      Value<String> authConfigJson,
      Value<int> orderIndex,
      Value<DateTime> updatedAt,
    });

final class $$RequestsTableReferences
    extends BaseReferences<_$AppDatabase, $RequestsTable, Request> {
  $$RequestsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) =>
      db.collections.createAlias('requests__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<int>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $FoldersTable _folderIdTable(_$AppDatabase db) =>
      db.folders.createAlias('requests__folder_id__folders__id');

  $$FoldersTableProcessedTableManager? get folderId {
    final $_column = $_itemColumn<int>('folder_id');
    if ($_column == null) return null;
    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_folderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$RequestScriptsTable, List<RequestScript>>
  _requestScriptsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.requestScripts,
    aliasName: 'requests__id__request_scripts__request_id',
  );

  $$RequestScriptsTableProcessedTableManager get requestScriptsRefs {
    final manager = $$RequestScriptsTableTableManager(
      $_db,
      $_db.requestScripts,
    ).filter((f) => f.requestId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_requestScriptsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ResponseExamplesTable, List<ResponseExample>>
  _responseExamplesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.responseExamples,
    aliasName: 'requests__id__response_examples__request_id',
  );

  $$ResponseExamplesTableProcessedTableManager get responseExamplesRefs {
    final manager = $$ResponseExamplesTableTableManager(
      $_db,
      $_db.responseExamples,
    ).filter((f) => f.requestId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _responseExamplesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $RequestSettingEntriesTable,
    List<RequestSettingEntry>
  >
  _requestSettingEntriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.requestSettingEntries,
        aliasName: 'requests__id__request_setting_entries__request_id',
      );

  $$RequestSettingEntriesTableProcessedTableManager
  get requestSettingEntriesRefs {
    final manager = $$RequestSettingEntriesTableTableManager(
      $_db,
      $_db.requestSettingEntries,
    ).filter((f) => f.requestId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _requestSettingEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RequestBaselinesTable, List<RequestBaseline>>
  _requestBaselinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.requestBaselines,
    aliasName: 'requests__id__request_baselines__request_id',
  );

  $$RequestBaselinesTableProcessedTableManager get requestBaselinesRefs {
    final manager = $$RequestBaselinesTableTableManager(
      $_db,
      $_db.requestBaselines,
    ).filter((f) => f.requestId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _requestBaselinesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RequestsTableFilterComposer
    extends Composer<_$AppDatabase, $RequestsTable> {
  $$RequestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queryParamsJson => $composableBuilder(
    column: $table.queryParamsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyType => $composableBuilder(
    column: $table.bodyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawContentType => $composableBuilder(
    column: $table.rawContentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyText => $composableBuilder(
    column: $table.bodyText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get formFieldsJson => $composableBuilder(
    column: $table.formFieldsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get urlEncodedFieldsJson => $composableBuilder(
    column: $table.urlEncodedFieldsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get graphqlQuery => $composableBuilder(
    column: $table.graphqlQuery,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get graphqlVariables => $composableBuilder(
    column: $table.graphqlVariables,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authConfigJson => $composableBuilder(
    column: $table.authConfigJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableFilterComposer get folderId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> requestScriptsRefs(
    Expression<bool> Function($$RequestScriptsTableFilterComposer f) f,
  ) {
    final $$RequestScriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.requestScripts,
      getReferencedColumn: (t) => t.requestId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestScriptsTableFilterComposer(
            $db: $db,
            $table: $db.requestScripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> responseExamplesRefs(
    Expression<bool> Function($$ResponseExamplesTableFilterComposer f) f,
  ) {
    final $$ResponseExamplesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.responseExamples,
      getReferencedColumn: (t) => t.requestId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ResponseExamplesTableFilterComposer(
            $db: $db,
            $table: $db.responseExamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> requestSettingEntriesRefs(
    Expression<bool> Function($$RequestSettingEntriesTableFilterComposer f) f,
  ) {
    final $$RequestSettingEntriesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.requestSettingEntries,
          getReferencedColumn: (t) => t.requestId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RequestSettingEntriesTableFilterComposer(
                $db: $db,
                $table: $db.requestSettingEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> requestBaselinesRefs(
    Expression<bool> Function($$RequestBaselinesTableFilterComposer f) f,
  ) {
    final $$RequestBaselinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.requestBaselines,
      getReferencedColumn: (t) => t.requestId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestBaselinesTableFilterComposer(
            $db: $db,
            $table: $db.requestBaselines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RequestsTableOrderingComposer
    extends Composer<_$AppDatabase, $RequestsTable> {
  $$RequestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queryParamsJson => $composableBuilder(
    column: $table.queryParamsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyType => $composableBuilder(
    column: $table.bodyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawContentType => $composableBuilder(
    column: $table.rawContentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyText => $composableBuilder(
    column: $table.bodyText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formFieldsJson => $composableBuilder(
    column: $table.formFieldsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urlEncodedFieldsJson => $composableBuilder(
    column: $table.urlEncodedFieldsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get graphqlQuery => $composableBuilder(
    column: $table.graphqlQuery,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get graphqlVariables => $composableBuilder(
    column: $table.graphqlVariables,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authConfigJson => $composableBuilder(
    column: $table.authConfigJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableOrderingComposer get folderId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RequestsTable> {
  $$RequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get queryParamsJson => $composableBuilder(
    column: $table.queryParamsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bodyType =>
      $composableBuilder(column: $table.bodyType, builder: (column) => column);

  GeneratedColumn<String> get rawContentType => $composableBuilder(
    column: $table.rawContentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bodyText =>
      $composableBuilder(column: $table.bodyText, builder: (column) => column);

  GeneratedColumn<String> get formFieldsJson => $composableBuilder(
    column: $table.formFieldsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get urlEncodedFieldsJson => $composableBuilder(
    column: $table.urlEncodedFieldsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get graphqlQuery => $composableBuilder(
    column: $table.graphqlQuery,
    builder: (column) => column,
  );

  GeneratedColumn<String> get graphqlVariables => $composableBuilder(
    column: $table.graphqlVariables,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authType =>
      $composableBuilder(column: $table.authType, builder: (column) => column);

  GeneratedColumn<String> get authConfigJson => $composableBuilder(
    column: $table.authConfigJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableAnnotationComposer get folderId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> requestScriptsRefs<T extends Object>(
    Expression<T> Function($$RequestScriptsTableAnnotationComposer a) f,
  ) {
    final $$RequestScriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.requestScripts,
      getReferencedColumn: (t) => t.requestId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestScriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.requestScripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> responseExamplesRefs<T extends Object>(
    Expression<T> Function($$ResponseExamplesTableAnnotationComposer a) f,
  ) {
    final $$ResponseExamplesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.responseExamples,
      getReferencedColumn: (t) => t.requestId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ResponseExamplesTableAnnotationComposer(
            $db: $db,
            $table: $db.responseExamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> requestSettingEntriesRefs<T extends Object>(
    Expression<T> Function($$RequestSettingEntriesTableAnnotationComposer a) f,
  ) {
    final $$RequestSettingEntriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.requestSettingEntries,
          getReferencedColumn: (t) => t.requestId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RequestSettingEntriesTableAnnotationComposer(
                $db: $db,
                $table: $db.requestSettingEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> requestBaselinesRefs<T extends Object>(
    Expression<T> Function($$RequestBaselinesTableAnnotationComposer a) f,
  ) {
    final $$RequestBaselinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.requestBaselines,
      getReferencedColumn: (t) => t.requestId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestBaselinesTableAnnotationComposer(
            $db: $db,
            $table: $db.requestBaselines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RequestsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RequestsTable,
          Request,
          $$RequestsTableFilterComposer,
          $$RequestsTableOrderingComposer,
          $$RequestsTableAnnotationComposer,
          $$RequestsTableCreateCompanionBuilder,
          $$RequestsTableUpdateCompanionBuilder,
          (Request, $$RequestsTableReferences),
          Request,
          PrefetchHooks Function({
            bool collectionId,
            bool folderId,
            bool requestScriptsRefs,
            bool responseExamplesRefs,
            bool requestSettingEntriesRefs,
            bool requestBaselinesRefs,
          })
        > {
  $$RequestsTableTableManager(_$AppDatabase db, $RequestsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RequestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RequestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RequestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> collectionId = const Value.absent(),
                Value<int?> folderId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> headersJson = const Value.absent(),
                Value<String> queryParamsJson = const Value.absent(),
                Value<String> bodyType = const Value.absent(),
                Value<String> rawContentType = const Value.absent(),
                Value<String> bodyText = const Value.absent(),
                Value<String> formFieldsJson = const Value.absent(),
                Value<String> urlEncodedFieldsJson = const Value.absent(),
                Value<String> graphqlQuery = const Value.absent(),
                Value<String> graphqlVariables = const Value.absent(),
                Value<String> authType = const Value.absent(),
                Value<String> authConfigJson = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => RequestsCompanion(
                id: id,
                collectionId: collectionId,
                folderId: folderId,
                name: name,
                method: method,
                url: url,
                headersJson: headersJson,
                queryParamsJson: queryParamsJson,
                bodyType: bodyType,
                rawContentType: rawContentType,
                bodyText: bodyText,
                formFieldsJson: formFieldsJson,
                urlEncodedFieldsJson: urlEncodedFieldsJson,
                graphqlQuery: graphqlQuery,
                graphqlVariables: graphqlVariables,
                authType: authType,
                authConfigJson: authConfigJson,
                orderIndex: orderIndex,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int collectionId,
                Value<int?> folderId = const Value.absent(),
                required String name,
                Value<String> method = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> headersJson = const Value.absent(),
                Value<String> queryParamsJson = const Value.absent(),
                Value<String> bodyType = const Value.absent(),
                Value<String> rawContentType = const Value.absent(),
                Value<String> bodyText = const Value.absent(),
                Value<String> formFieldsJson = const Value.absent(),
                Value<String> urlEncodedFieldsJson = const Value.absent(),
                Value<String> graphqlQuery = const Value.absent(),
                Value<String> graphqlVariables = const Value.absent(),
                Value<String> authType = const Value.absent(),
                Value<String> authConfigJson = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => RequestsCompanion.insert(
                id: id,
                collectionId: collectionId,
                folderId: folderId,
                name: name,
                method: method,
                url: url,
                headersJson: headersJson,
                queryParamsJson: queryParamsJson,
                bodyType: bodyType,
                rawContentType: rawContentType,
                bodyText: bodyText,
                formFieldsJson: formFieldsJson,
                urlEncodedFieldsJson: urlEncodedFieldsJson,
                graphqlQuery: graphqlQuery,
                graphqlVariables: graphqlVariables,
                authType: authType,
                authConfigJson: authConfigJson,
                orderIndex: orderIndex,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RequestsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                collectionId = false,
                folderId = false,
                requestScriptsRefs = false,
                responseExamplesRefs = false,
                requestSettingEntriesRefs = false,
                requestBaselinesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (requestScriptsRefs) db.requestScripts,
                    if (responseExamplesRefs) db.responseExamples,
                    if (requestSettingEntriesRefs) db.requestSettingEntries,
                    if (requestBaselinesRefs) db.requestBaselines,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (collectionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.collectionId,
                                    referencedTable: $$RequestsTableReferences
                                        ._collectionIdTable(db),
                                    referencedColumn: $$RequestsTableReferences
                                        ._collectionIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (folderId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.folderId,
                                    referencedTable: $$RequestsTableReferences
                                        ._folderIdTable(db),
                                    referencedColumn: $$RequestsTableReferences
                                        ._folderIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (requestScriptsRefs)
                        await $_getPrefetchedData<
                          Request,
                          $RequestsTable,
                          RequestScript
                        >(
                          currentTable: table,
                          referencedTable: $$RequestsTableReferences
                              ._requestScriptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RequestsTableReferences(
                                db,
                                table,
                                p0,
                              ).requestScriptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.requestId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (responseExamplesRefs)
                        await $_getPrefetchedData<
                          Request,
                          $RequestsTable,
                          ResponseExample
                        >(
                          currentTable: table,
                          referencedTable: $$RequestsTableReferences
                              ._responseExamplesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RequestsTableReferences(
                                db,
                                table,
                                p0,
                              ).responseExamplesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.requestId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (requestSettingEntriesRefs)
                        await $_getPrefetchedData<
                          Request,
                          $RequestsTable,
                          RequestSettingEntry
                        >(
                          currentTable: table,
                          referencedTable: $$RequestsTableReferences
                              ._requestSettingEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RequestsTableReferences(
                                db,
                                table,
                                p0,
                              ).requestSettingEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.requestId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (requestBaselinesRefs)
                        await $_getPrefetchedData<
                          Request,
                          $RequestsTable,
                          RequestBaseline
                        >(
                          currentTable: table,
                          referencedTable: $$RequestsTableReferences
                              ._requestBaselinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RequestsTableReferences(
                                db,
                                table,
                                p0,
                              ).requestBaselinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.requestId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$RequestsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RequestsTable,
      Request,
      $$RequestsTableFilterComposer,
      $$RequestsTableOrderingComposer,
      $$RequestsTableAnnotationComposer,
      $$RequestsTableCreateCompanionBuilder,
      $$RequestsTableUpdateCompanionBuilder,
      (Request, $$RequestsTableReferences),
      Request,
      PrefetchHooks Function({
        bool collectionId,
        bool folderId,
        bool requestScriptsRefs,
        bool responseExamplesRefs,
        bool requestSettingEntriesRefs,
        bool requestBaselinesRefs,
      })
    >;
typedef $$EnvironmentsTableCreateCompanionBuilder =
    EnvironmentsCompanion Function({
      Value<int> id,
      required String name,
      Value<bool> isActive,
    });
typedef $$EnvironmentsTableUpdateCompanionBuilder =
    EnvironmentsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<bool> isActive,
    });

final class $$EnvironmentsTableReferences
    extends BaseReferences<_$AppDatabase, $EnvironmentsTable, Environment> {
  $$EnvironmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $EnvironmentVariablesTable,
    List<EnvironmentVariable>
  >
  _environmentVariablesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.environmentVariables,
        aliasName: 'environments__id__environment_variables__environment_id',
      );

  $$EnvironmentVariablesTableProcessedTableManager
  get environmentVariablesRefs {
    final manager = $$EnvironmentVariablesTableTableManager(
      $_db,
      $_db.environmentVariables,
    ).filter((f) => f.environmentId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _environmentVariablesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$EnvironmentsTableFilterComposer
    extends Composer<_$AppDatabase, $EnvironmentsTable> {
  $$EnvironmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> environmentVariablesRefs(
    Expression<bool> Function($$EnvironmentVariablesTableFilterComposer f) f,
  ) {
    final $$EnvironmentVariablesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.environmentVariables,
      getReferencedColumn: (t) => t.environmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EnvironmentVariablesTableFilterComposer(
            $db: $db,
            $table: $db.environmentVariables,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EnvironmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $EnvironmentsTable> {
  $$EnvironmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EnvironmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EnvironmentsTable> {
  $$EnvironmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  Expression<T> environmentVariablesRefs<T extends Object>(
    Expression<T> Function($$EnvironmentVariablesTableAnnotationComposer a) f,
  ) {
    final $$EnvironmentVariablesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.environmentVariables,
          getReferencedColumn: (t) => t.environmentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$EnvironmentVariablesTableAnnotationComposer(
                $db: $db,
                $table: $db.environmentVariables,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$EnvironmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EnvironmentsTable,
          Environment,
          $$EnvironmentsTableFilterComposer,
          $$EnvironmentsTableOrderingComposer,
          $$EnvironmentsTableAnnotationComposer,
          $$EnvironmentsTableCreateCompanionBuilder,
          $$EnvironmentsTableUpdateCompanionBuilder,
          (Environment, $$EnvironmentsTableReferences),
          Environment,
          PrefetchHooks Function({bool environmentVariablesRefs})
        > {
  $$EnvironmentsTableTableManager(_$AppDatabase db, $EnvironmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EnvironmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EnvironmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EnvironmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
              }) =>
                  EnvironmentsCompanion(id: id, name: name, isActive: isActive),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<bool> isActive = const Value.absent(),
              }) => EnvironmentsCompanion.insert(
                id: id,
                name: name,
                isActive: isActive,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EnvironmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({environmentVariablesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (environmentVariablesRefs) db.environmentVariables,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (environmentVariablesRefs)
                    await $_getPrefetchedData<
                      Environment,
                      $EnvironmentsTable,
                      EnvironmentVariable
                    >(
                      currentTable: table,
                      referencedTable: $$EnvironmentsTableReferences
                          ._environmentVariablesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$EnvironmentsTableReferences(
                            db,
                            table,
                            p0,
                          ).environmentVariablesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.environmentId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$EnvironmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EnvironmentsTable,
      Environment,
      $$EnvironmentsTableFilterComposer,
      $$EnvironmentsTableOrderingComposer,
      $$EnvironmentsTableAnnotationComposer,
      $$EnvironmentsTableCreateCompanionBuilder,
      $$EnvironmentsTableUpdateCompanionBuilder,
      (Environment, $$EnvironmentsTableReferences),
      Environment,
      PrefetchHooks Function({bool environmentVariablesRefs})
    >;
typedef $$EnvironmentVariablesTableCreateCompanionBuilder =
    EnvironmentVariablesCompanion Function({
      Value<int> id,
      required int environmentId,
      required String key,
      Value<String> value,
      Value<bool> isSecret,
      Value<bool> enabled,
      Value<int> orderIndex,
    });
typedef $$EnvironmentVariablesTableUpdateCompanionBuilder =
    EnvironmentVariablesCompanion Function({
      Value<int> id,
      Value<int> environmentId,
      Value<String> key,
      Value<String> value,
      Value<bool> isSecret,
      Value<bool> enabled,
      Value<int> orderIndex,
    });

final class $$EnvironmentVariablesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $EnvironmentVariablesTable,
          EnvironmentVariable
        > {
  $$EnvironmentVariablesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $EnvironmentsTable _environmentIdTable(_$AppDatabase db) => db
      .environments
      .createAlias('environment_variables__environment_id__environments__id');

  $$EnvironmentsTableProcessedTableManager get environmentId {
    final $_column = $_itemColumn<int>('environment_id')!;

    final manager = $$EnvironmentsTableTableManager(
      $_db,
      $_db.environments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_environmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EnvironmentVariablesTableFilterComposer
    extends Composer<_$AppDatabase, $EnvironmentVariablesTable> {
  $$EnvironmentVariablesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSecret => $composableBuilder(
    column: $table.isSecret,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  $$EnvironmentsTableFilterComposer get environmentId {
    final $$EnvironmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.environmentId,
      referencedTable: $db.environments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EnvironmentsTableFilterComposer(
            $db: $db,
            $table: $db.environments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EnvironmentVariablesTableOrderingComposer
    extends Composer<_$AppDatabase, $EnvironmentVariablesTable> {
  $$EnvironmentVariablesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSecret => $composableBuilder(
    column: $table.isSecret,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  $$EnvironmentsTableOrderingComposer get environmentId {
    final $$EnvironmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.environmentId,
      referencedTable: $db.environments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EnvironmentsTableOrderingComposer(
            $db: $db,
            $table: $db.environments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EnvironmentVariablesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EnvironmentVariablesTable> {
  $$EnvironmentVariablesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<bool> get isSecret =>
      $composableBuilder(column: $table.isSecret, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  $$EnvironmentsTableAnnotationComposer get environmentId {
    final $$EnvironmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.environmentId,
      referencedTable: $db.environments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EnvironmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.environments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EnvironmentVariablesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EnvironmentVariablesTable,
          EnvironmentVariable,
          $$EnvironmentVariablesTableFilterComposer,
          $$EnvironmentVariablesTableOrderingComposer,
          $$EnvironmentVariablesTableAnnotationComposer,
          $$EnvironmentVariablesTableCreateCompanionBuilder,
          $$EnvironmentVariablesTableUpdateCompanionBuilder,
          (EnvironmentVariable, $$EnvironmentVariablesTableReferences),
          EnvironmentVariable,
          PrefetchHooks Function({bool environmentId})
        > {
  $$EnvironmentVariablesTableTableManager(
    _$AppDatabase db,
    $EnvironmentVariablesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EnvironmentVariablesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EnvironmentVariablesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EnvironmentVariablesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> environmentId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<bool> isSecret = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
              }) => EnvironmentVariablesCompanion(
                id: id,
                environmentId: environmentId,
                key: key,
                value: value,
                isSecret: isSecret,
                enabled: enabled,
                orderIndex: orderIndex,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int environmentId,
                required String key,
                Value<String> value = const Value.absent(),
                Value<bool> isSecret = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
              }) => EnvironmentVariablesCompanion.insert(
                id: id,
                environmentId: environmentId,
                key: key,
                value: value,
                isSecret: isSecret,
                enabled: enabled,
                orderIndex: orderIndex,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EnvironmentVariablesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({environmentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (environmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.environmentId,
                                referencedTable:
                                    $$EnvironmentVariablesTableReferences
                                        ._environmentIdTable(db),
                                referencedColumn:
                                    $$EnvironmentVariablesTableReferences
                                        ._environmentIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EnvironmentVariablesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EnvironmentVariablesTable,
      EnvironmentVariable,
      $$EnvironmentVariablesTableFilterComposer,
      $$EnvironmentVariablesTableOrderingComposer,
      $$EnvironmentVariablesTableAnnotationComposer,
      $$EnvironmentVariablesTableCreateCompanionBuilder,
      $$EnvironmentVariablesTableUpdateCompanionBuilder,
      (EnvironmentVariable, $$EnvironmentVariablesTableReferences),
      EnvironmentVariable,
      PrefetchHooks Function({bool environmentId})
    >;
typedef $$HistoryEntriesTableCreateCompanionBuilder =
    HistoryEntriesCompanion Function({
      Value<int> id,
      Value<int?> requestId,
      required String method,
      required String url,
      Value<int?> statusCode,
      Value<int?> durationMs,
      Value<String> responseHeadersJson,
      Value<Uint8List?> responseBody,
      Value<DateTime> sentAt,
    });
typedef $$HistoryEntriesTableUpdateCompanionBuilder =
    HistoryEntriesCompanion Function({
      Value<int> id,
      Value<int?> requestId,
      Value<String> method,
      Value<String> url,
      Value<int?> statusCode,
      Value<int?> durationMs,
      Value<String> responseHeadersJson,
      Value<Uint8List?> responseBody,
      Value<DateTime> sentAt,
    });

final class $$HistoryEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $HistoryEntriesTable, HistoryEntry> {
  $$HistoryEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$HistoryPayloadsTable, List<HistoryPayload>>
  _historyPayloadsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.historyPayloads,
    aliasName: 'history_entries__id__history_payloads__history_id',
  );

  $$HistoryPayloadsTableProcessedTableManager get historyPayloadsRefs {
    final manager = $$HistoryPayloadsTableTableManager(
      $_db,
      $_db.historyPayloads,
    ).filter((f) => f.historyId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _historyPayloadsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$HistoryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get responseHeadersJson => $composableBuilder(
    column: $table.responseHeadersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get responseBody => $composableBuilder(
    column: $table.responseBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> historyPayloadsRefs(
    Expression<bool> Function($$HistoryPayloadsTableFilterComposer f) f,
  ) {
    final $$HistoryPayloadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.historyPayloads,
      getReferencedColumn: (t) => t.historyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryPayloadsTableFilterComposer(
            $db: $db,
            $table: $db.historyPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HistoryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get responseHeadersJson => $composableBuilder(
    column: $table.responseHeadersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get responseBody => $composableBuilder(
    column: $table.responseBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get responseHeadersJson => $composableBuilder(
    column: $table.responseHeadersJson,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get responseBody => $composableBuilder(
    column: $table.responseBody,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  Expression<T> historyPayloadsRefs<T extends Object>(
    Expression<T> Function($$HistoryPayloadsTableAnnotationComposer a) f,
  ) {
    final $$HistoryPayloadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.historyPayloads,
      getReferencedColumn: (t) => t.historyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryPayloadsTableAnnotationComposer(
            $db: $db,
            $table: $db.historyPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HistoryEntriesTable,
          HistoryEntry,
          $$HistoryEntriesTableFilterComposer,
          $$HistoryEntriesTableOrderingComposer,
          $$HistoryEntriesTableAnnotationComposer,
          $$HistoryEntriesTableCreateCompanionBuilder,
          $$HistoryEntriesTableUpdateCompanionBuilder,
          (HistoryEntry, $$HistoryEntriesTableReferences),
          HistoryEntry,
          PrefetchHooks Function({bool historyPayloadsRefs})
        > {
  $$HistoryEntriesTableTableManager(
    _$AppDatabase db,
    $HistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> requestId = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<int?> statusCode = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String> responseHeadersJson = const Value.absent(),
                Value<Uint8List?> responseBody = const Value.absent(),
                Value<DateTime> sentAt = const Value.absent(),
              }) => HistoryEntriesCompanion(
                id: id,
                requestId: requestId,
                method: method,
                url: url,
                statusCode: statusCode,
                durationMs: durationMs,
                responseHeadersJson: responseHeadersJson,
                responseBody: responseBody,
                sentAt: sentAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> requestId = const Value.absent(),
                required String method,
                required String url,
                Value<int?> statusCode = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String> responseHeadersJson = const Value.absent(),
                Value<Uint8List?> responseBody = const Value.absent(),
                Value<DateTime> sentAt = const Value.absent(),
              }) => HistoryEntriesCompanion.insert(
                id: id,
                requestId: requestId,
                method: method,
                url: url,
                statusCode: statusCode,
                durationMs: durationMs,
                responseHeadersJson: responseHeadersJson,
                responseBody: responseBody,
                sentAt: sentAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HistoryEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({historyPayloadsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (historyPayloadsRefs) db.historyPayloads,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (historyPayloadsRefs)
                    await $_getPrefetchedData<
                      HistoryEntry,
                      $HistoryEntriesTable,
                      HistoryPayload
                    >(
                      currentTable: table,
                      referencedTable: $$HistoryEntriesTableReferences
                          ._historyPayloadsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$HistoryEntriesTableReferences(
                            db,
                            table,
                            p0,
                          ).historyPayloadsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.historyId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$HistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HistoryEntriesTable,
      HistoryEntry,
      $$HistoryEntriesTableFilterComposer,
      $$HistoryEntriesTableOrderingComposer,
      $$HistoryEntriesTableAnnotationComposer,
      $$HistoryEntriesTableCreateCompanionBuilder,
      $$HistoryEntriesTableUpdateCompanionBuilder,
      (HistoryEntry, $$HistoryEntriesTableReferences),
      HistoryEntry,
      PrefetchHooks Function({bool historyPayloadsRefs})
    >;
typedef $$GlobalVariablesTableCreateCompanionBuilder =
    GlobalVariablesCompanion Function({
      Value<int> id,
      required String key,
      Value<String> value,
      Value<bool> isSecret,
      Value<bool> enabled,
    });
typedef $$GlobalVariablesTableUpdateCompanionBuilder =
    GlobalVariablesCompanion Function({
      Value<int> id,
      Value<String> key,
      Value<String> value,
      Value<bool> isSecret,
      Value<bool> enabled,
    });

class $$GlobalVariablesTableFilterComposer
    extends Composer<_$AppDatabase, $GlobalVariablesTable> {
  $$GlobalVariablesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSecret => $composableBuilder(
    column: $table.isSecret,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GlobalVariablesTableOrderingComposer
    extends Composer<_$AppDatabase, $GlobalVariablesTable> {
  $$GlobalVariablesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSecret => $composableBuilder(
    column: $table.isSecret,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GlobalVariablesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GlobalVariablesTable> {
  $$GlobalVariablesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<bool> get isSecret =>
      $composableBuilder(column: $table.isSecret, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$GlobalVariablesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GlobalVariablesTable,
          GlobalVariable,
          $$GlobalVariablesTableFilterComposer,
          $$GlobalVariablesTableOrderingComposer,
          $$GlobalVariablesTableAnnotationComposer,
          $$GlobalVariablesTableCreateCompanionBuilder,
          $$GlobalVariablesTableUpdateCompanionBuilder,
          (
            GlobalVariable,
            BaseReferences<
              _$AppDatabase,
              $GlobalVariablesTable,
              GlobalVariable
            >,
          ),
          GlobalVariable,
          PrefetchHooks Function()
        > {
  $$GlobalVariablesTableTableManager(
    _$AppDatabase db,
    $GlobalVariablesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GlobalVariablesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GlobalVariablesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GlobalVariablesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<bool> isSecret = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => GlobalVariablesCompanion(
                id: id,
                key: key,
                value: value,
                isSecret: isSecret,
                enabled: enabled,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String key,
                Value<String> value = const Value.absent(),
                Value<bool> isSecret = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => GlobalVariablesCompanion.insert(
                id: id,
                key: key,
                value: value,
                isSecret: isSecret,
                enabled: enabled,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GlobalVariablesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GlobalVariablesTable,
      GlobalVariable,
      $$GlobalVariablesTableFilterComposer,
      $$GlobalVariablesTableOrderingComposer,
      $$GlobalVariablesTableAnnotationComposer,
      $$GlobalVariablesTableCreateCompanionBuilder,
      $$GlobalVariablesTableUpdateCompanionBuilder,
      (
        GlobalVariable,
        BaseReferences<_$AppDatabase, $GlobalVariablesTable, GlobalVariable>,
      ),
      GlobalVariable,
      PrefetchHooks Function()
    >;
typedef $$CollectionVariablesTableCreateCompanionBuilder =
    CollectionVariablesCompanion Function({
      Value<int> id,
      required int collectionId,
      required String key,
      Value<String> value,
      Value<bool> enabled,
    });
typedef $$CollectionVariablesTableUpdateCompanionBuilder =
    CollectionVariablesCompanion Function({
      Value<int> id,
      Value<int> collectionId,
      Value<String> key,
      Value<String> value,
      Value<bool> enabled,
    });

final class $$CollectionVariablesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CollectionVariablesTable,
          CollectionVariable
        > {
  $$CollectionVariablesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) => db
      .collections
      .createAlias('collection_variables__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<int>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CollectionVariablesTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionVariablesTable> {
  $$CollectionVariablesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionVariablesTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionVariablesTable> {
  $$CollectionVariablesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionVariablesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionVariablesTable> {
  $$CollectionVariablesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionVariablesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionVariablesTable,
          CollectionVariable,
          $$CollectionVariablesTableFilterComposer,
          $$CollectionVariablesTableOrderingComposer,
          $$CollectionVariablesTableAnnotationComposer,
          $$CollectionVariablesTableCreateCompanionBuilder,
          $$CollectionVariablesTableUpdateCompanionBuilder,
          (CollectionVariable, $$CollectionVariablesTableReferences),
          CollectionVariable,
          PrefetchHooks Function({bool collectionId})
        > {
  $$CollectionVariablesTableTableManager(
    _$AppDatabase db,
    $CollectionVariablesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionVariablesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionVariablesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CollectionVariablesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> collectionId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => CollectionVariablesCompanion(
                id: id,
                collectionId: collectionId,
                key: key,
                value: value,
                enabled: enabled,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int collectionId,
                required String key,
                Value<String> value = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => CollectionVariablesCompanion.insert(
                id: id,
                collectionId: collectionId,
                key: key,
                value: value,
                enabled: enabled,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CollectionVariablesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({collectionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (collectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.collectionId,
                                referencedTable:
                                    $$CollectionVariablesTableReferences
                                        ._collectionIdTable(db),
                                referencedColumn:
                                    $$CollectionVariablesTableReferences
                                        ._collectionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CollectionVariablesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionVariablesTable,
      CollectionVariable,
      $$CollectionVariablesTableFilterComposer,
      $$CollectionVariablesTableOrderingComposer,
      $$CollectionVariablesTableAnnotationComposer,
      $$CollectionVariablesTableCreateCompanionBuilder,
      $$CollectionVariablesTableUpdateCompanionBuilder,
      (CollectionVariable, $$CollectionVariablesTableReferences),
      CollectionVariable,
      PrefetchHooks Function({bool collectionId})
    >;
typedef $$CollectionAuthTableCreateCompanionBuilder =
    CollectionAuthCompanion Function({
      Value<int> collectionId,
      Value<String> authJson,
    });
typedef $$CollectionAuthTableUpdateCompanionBuilder =
    CollectionAuthCompanion Function({
      Value<int> collectionId,
      Value<String> authJson,
    });

final class $$CollectionAuthTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CollectionAuthTable,
          CollectionAuthData
        > {
  $$CollectionAuthTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) => db
      .collections
      .createAlias('collection_auth__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<int>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CollectionAuthTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionAuthTable> {
  $$CollectionAuthTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get authJson => $composableBuilder(
    column: $table.authJson,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionAuthTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionAuthTable> {
  $$CollectionAuthTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get authJson => $composableBuilder(
    column: $table.authJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionAuthTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionAuthTable> {
  $$CollectionAuthTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get authJson =>
      $composableBuilder(column: $table.authJson, builder: (column) => column);

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionAuthTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionAuthTable,
          CollectionAuthData,
          $$CollectionAuthTableFilterComposer,
          $$CollectionAuthTableOrderingComposer,
          $$CollectionAuthTableAnnotationComposer,
          $$CollectionAuthTableCreateCompanionBuilder,
          $$CollectionAuthTableUpdateCompanionBuilder,
          (CollectionAuthData, $$CollectionAuthTableReferences),
          CollectionAuthData,
          PrefetchHooks Function({bool collectionId})
        > {
  $$CollectionAuthTableTableManager(
    _$AppDatabase db,
    $CollectionAuthTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionAuthTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionAuthTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionAuthTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> collectionId = const Value.absent(),
                Value<String> authJson = const Value.absent(),
              }) => CollectionAuthCompanion(
                collectionId: collectionId,
                authJson: authJson,
              ),
          createCompanionCallback:
              ({
                Value<int> collectionId = const Value.absent(),
                Value<String> authJson = const Value.absent(),
              }) => CollectionAuthCompanion.insert(
                collectionId: collectionId,
                authJson: authJson,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CollectionAuthTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({collectionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (collectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.collectionId,
                                referencedTable: $$CollectionAuthTableReferences
                                    ._collectionIdTable(db),
                                referencedColumn:
                                    $$CollectionAuthTableReferences
                                        ._collectionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CollectionAuthTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionAuthTable,
      CollectionAuthData,
      $$CollectionAuthTableFilterComposer,
      $$CollectionAuthTableOrderingComposer,
      $$CollectionAuthTableAnnotationComposer,
      $$CollectionAuthTableCreateCompanionBuilder,
      $$CollectionAuthTableUpdateCompanionBuilder,
      (CollectionAuthData, $$CollectionAuthTableReferences),
      CollectionAuthData,
      PrefetchHooks Function({bool collectionId})
    >;
typedef $$RequestScriptsTableCreateCompanionBuilder =
    RequestScriptsCompanion Function({
      Value<int> requestId,
      Value<String> assertionsJson,
      Value<String> extractorsJson,
    });
typedef $$RequestScriptsTableUpdateCompanionBuilder =
    RequestScriptsCompanion Function({
      Value<int> requestId,
      Value<String> assertionsJson,
      Value<String> extractorsJson,
    });

final class $$RequestScriptsTableReferences
    extends BaseReferences<_$AppDatabase, $RequestScriptsTable, RequestScript> {
  $$RequestScriptsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RequestsTable _requestIdTable(_$AppDatabase db) =>
      db.requests.createAlias('request_scripts__request_id__requests__id');

  $$RequestsTableProcessedTableManager get requestId {
    final $_column = $_itemColumn<int>('request_id')!;

    final manager = $$RequestsTableTableManager(
      $_db,
      $_db.requests,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_requestIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RequestScriptsTableFilterComposer
    extends Composer<_$AppDatabase, $RequestScriptsTable> {
  $$RequestScriptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get assertionsJson => $composableBuilder(
    column: $table.assertionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractorsJson => $composableBuilder(
    column: $table.extractorsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$RequestsTableFilterComposer get requestId {
    final $$RequestsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableFilterComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestScriptsTableOrderingComposer
    extends Composer<_$AppDatabase, $RequestScriptsTable> {
  $$RequestScriptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get assertionsJson => $composableBuilder(
    column: $table.assertionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractorsJson => $composableBuilder(
    column: $table.extractorsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$RequestsTableOrderingComposer get requestId {
    final $$RequestsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableOrderingComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestScriptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RequestScriptsTable> {
  $$RequestScriptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get assertionsJson => $composableBuilder(
    column: $table.assertionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extractorsJson => $composableBuilder(
    column: $table.extractorsJson,
    builder: (column) => column,
  );

  $$RequestsTableAnnotationComposer get requestId {
    final $$RequestsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableAnnotationComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestScriptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RequestScriptsTable,
          RequestScript,
          $$RequestScriptsTableFilterComposer,
          $$RequestScriptsTableOrderingComposer,
          $$RequestScriptsTableAnnotationComposer,
          $$RequestScriptsTableCreateCompanionBuilder,
          $$RequestScriptsTableUpdateCompanionBuilder,
          (RequestScript, $$RequestScriptsTableReferences),
          RequestScript,
          PrefetchHooks Function({bool requestId})
        > {
  $$RequestScriptsTableTableManager(
    _$AppDatabase db,
    $RequestScriptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RequestScriptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RequestScriptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RequestScriptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> requestId = const Value.absent(),
                Value<String> assertionsJson = const Value.absent(),
                Value<String> extractorsJson = const Value.absent(),
              }) => RequestScriptsCompanion(
                requestId: requestId,
                assertionsJson: assertionsJson,
                extractorsJson: extractorsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> requestId = const Value.absent(),
                Value<String> assertionsJson = const Value.absent(),
                Value<String> extractorsJson = const Value.absent(),
              }) => RequestScriptsCompanion.insert(
                requestId: requestId,
                assertionsJson: assertionsJson,
                extractorsJson: extractorsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RequestScriptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({requestId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (requestId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.requestId,
                                referencedTable: $$RequestScriptsTableReferences
                                    ._requestIdTable(db),
                                referencedColumn:
                                    $$RequestScriptsTableReferences
                                        ._requestIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RequestScriptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RequestScriptsTable,
      RequestScript,
      $$RequestScriptsTableFilterComposer,
      $$RequestScriptsTableOrderingComposer,
      $$RequestScriptsTableAnnotationComposer,
      $$RequestScriptsTableCreateCompanionBuilder,
      $$RequestScriptsTableUpdateCompanionBuilder,
      (RequestScript, $$RequestScriptsTableReferences),
      RequestScript,
      PrefetchHooks Function({bool requestId})
    >;
typedef $$ResponseExamplesTableCreateCompanionBuilder =
    ResponseExamplesCompanion Function({
      Value<int> id,
      required int requestId,
      required String name,
      required int statusCode,
      Value<String> headersJson,
      Value<String> body,
      Value<DateTime> savedAt,
    });
typedef $$ResponseExamplesTableUpdateCompanionBuilder =
    ResponseExamplesCompanion Function({
      Value<int> id,
      Value<int> requestId,
      Value<String> name,
      Value<int> statusCode,
      Value<String> headersJson,
      Value<String> body,
      Value<DateTime> savedAt,
    });

final class $$ResponseExamplesTableReferences
    extends
        BaseReferences<_$AppDatabase, $ResponseExamplesTable, ResponseExample> {
  $$ResponseExamplesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RequestsTable _requestIdTable(_$AppDatabase db) =>
      db.requests.createAlias('response_examples__request_id__requests__id');

  $$RequestsTableProcessedTableManager get requestId {
    final $_column = $_itemColumn<int>('request_id')!;

    final manager = $$RequestsTableTableManager(
      $_db,
      $_db.requests,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_requestIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ResponseExamplesTableFilterComposer
    extends Composer<_$AppDatabase, $ResponseExamplesTable> {
  $$ResponseExamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RequestsTableFilterComposer get requestId {
    final $$RequestsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableFilterComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResponseExamplesTableOrderingComposer
    extends Composer<_$AppDatabase, $ResponseExamplesTable> {
  $$ResponseExamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RequestsTableOrderingComposer get requestId {
    final $$RequestsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableOrderingComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResponseExamplesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ResponseExamplesTable> {
  $$ResponseExamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  $$RequestsTableAnnotationComposer get requestId {
    final $$RequestsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableAnnotationComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResponseExamplesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ResponseExamplesTable,
          ResponseExample,
          $$ResponseExamplesTableFilterComposer,
          $$ResponseExamplesTableOrderingComposer,
          $$ResponseExamplesTableAnnotationComposer,
          $$ResponseExamplesTableCreateCompanionBuilder,
          $$ResponseExamplesTableUpdateCompanionBuilder,
          (ResponseExample, $$ResponseExamplesTableReferences),
          ResponseExample,
          PrefetchHooks Function({bool requestId})
        > {
  $$ResponseExamplesTableTableManager(
    _$AppDatabase db,
    $ResponseExamplesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResponseExamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResponseExamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResponseExamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> requestId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> statusCode = const Value.absent(),
                Value<String> headersJson = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
              }) => ResponseExamplesCompanion(
                id: id,
                requestId: requestId,
                name: name,
                statusCode: statusCode,
                headersJson: headersJson,
                body: body,
                savedAt: savedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int requestId,
                required String name,
                required int statusCode,
                Value<String> headersJson = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
              }) => ResponseExamplesCompanion.insert(
                id: id,
                requestId: requestId,
                name: name,
                statusCode: statusCode,
                headersJson: headersJson,
                body: body,
                savedAt: savedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ResponseExamplesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({requestId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (requestId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.requestId,
                                referencedTable:
                                    $$ResponseExamplesTableReferences
                                        ._requestIdTable(db),
                                referencedColumn:
                                    $$ResponseExamplesTableReferences
                                        ._requestIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ResponseExamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ResponseExamplesTable,
      ResponseExample,
      $$ResponseExamplesTableFilterComposer,
      $$ResponseExamplesTableOrderingComposer,
      $$ResponseExamplesTableAnnotationComposer,
      $$ResponseExamplesTableCreateCompanionBuilder,
      $$ResponseExamplesTableUpdateCompanionBuilder,
      (ResponseExample, $$ResponseExamplesTableReferences),
      ResponseExample,
      PrefetchHooks Function({bool requestId})
    >;
typedef $$EntityUidsTableCreateCompanionBuilder =
    EntityUidsCompanion Function({
      required String kind,
      required int localId,
      required String uid,
      Value<int> rowid,
    });
typedef $$EntityUidsTableUpdateCompanionBuilder =
    EntityUidsCompanion Function({
      Value<String> kind,
      Value<int> localId,
      Value<String> uid,
      Value<int> rowid,
    });

class $$EntityUidsTableFilterComposer
    extends Composer<_$AppDatabase, $EntityUidsTable> {
  $$EntityUidsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntityUidsTableOrderingComposer
    extends Composer<_$AppDatabase, $EntityUidsTable> {
  $$EntityUidsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntityUidsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntityUidsTable> {
  $$EntityUidsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);
}

class $$EntityUidsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntityUidsTable,
          EntityUid,
          $$EntityUidsTableFilterComposer,
          $$EntityUidsTableOrderingComposer,
          $$EntityUidsTableAnnotationComposer,
          $$EntityUidsTableCreateCompanionBuilder,
          $$EntityUidsTableUpdateCompanionBuilder,
          (
            EntityUid,
            BaseReferences<_$AppDatabase, $EntityUidsTable, EntityUid>,
          ),
          EntityUid,
          PrefetchHooks Function()
        > {
  $$EntityUidsTableTableManager(_$AppDatabase db, $EntityUidsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntityUidsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntityUidsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntityUidsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<int> localId = const Value.absent(),
                Value<String> uid = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntityUidsCompanion(
                kind: kind,
                localId: localId,
                uid: uid,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required int localId,
                required String uid,
                Value<int> rowid = const Value.absent(),
              }) => EntityUidsCompanion.insert(
                kind: kind,
                localId: localId,
                uid: uid,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntityUidsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntityUidsTable,
      EntityUid,
      $$EntityUidsTableFilterComposer,
      $$EntityUidsTableOrderingComposer,
      $$EntityUidsTableAnnotationComposer,
      $$EntityUidsTableCreateCompanionBuilder,
      $$EntityUidsTableUpdateCompanionBuilder,
      (EntityUid, BaseReferences<_$AppDatabase, $EntityUidsTable, EntityUid>),
      EntityUid,
      PrefetchHooks Function()
    >;
typedef $$GitLinksTableCreateCompanionBuilder =
    GitLinksCompanion Function({
      Value<int> id,
      required int collectionId,
      required String provider,
      required String owner,
      required String repo,
      required String branch,
      Value<String> basePath,
      Value<String?> lastSyncedSha,
      Value<DateTime?> lastSyncedAt,
      Value<bool> includeSecrets,
    });
typedef $$GitLinksTableUpdateCompanionBuilder =
    GitLinksCompanion Function({
      Value<int> id,
      Value<int> collectionId,
      Value<String> provider,
      Value<String> owner,
      Value<String> repo,
      Value<String> branch,
      Value<String> basePath,
      Value<String?> lastSyncedSha,
      Value<DateTime?> lastSyncedAt,
      Value<bool> includeSecrets,
    });

final class $$GitLinksTableReferences
    extends BaseReferences<_$AppDatabase, $GitLinksTable, GitLinkRow> {
  $$GitLinksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) =>
      db.collections.createAlias('git_links__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<int>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$GitBaseEntriesTable, List<GitBaseEntry>>
  _gitBaseEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.gitBaseEntries,
    aliasName: 'git_links__id__git_base_entries__link_id',
  );

  $$GitBaseEntriesTableProcessedTableManager get gitBaseEntriesRefs {
    final manager = $$GitBaseEntriesTableTableManager(
      $_db,
      $_db.gitBaseEntries,
    ).filter((f) => f.linkId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_gitBaseEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GitLinksTableFilterComposer
    extends Composer<_$AppDatabase, $GitLinksTable> {
  $$GitLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repo => $composableBuilder(
    column: $table.repo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get basePath => $composableBuilder(
    column: $table.basePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSyncedSha => $composableBuilder(
    column: $table.lastSyncedSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includeSecrets => $composableBuilder(
    column: $table.includeSecrets,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> gitBaseEntriesRefs(
    Expression<bool> Function($$GitBaseEntriesTableFilterComposer f) f,
  ) {
    final $$GitBaseEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gitBaseEntries,
      getReferencedColumn: (t) => t.linkId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitBaseEntriesTableFilterComposer(
            $db: $db,
            $table: $db.gitBaseEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GitLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $GitLinksTable> {
  $$GitLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repo => $composableBuilder(
    column: $table.repo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get basePath => $composableBuilder(
    column: $table.basePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSyncedSha => $composableBuilder(
    column: $table.lastSyncedSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includeSecrets => $composableBuilder(
    column: $table.includeSecrets,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GitLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $GitLinksTable> {
  $$GitLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get repo =>
      $composableBuilder(column: $table.repo, builder: (column) => column);

  GeneratedColumn<String> get branch =>
      $composableBuilder(column: $table.branch, builder: (column) => column);

  GeneratedColumn<String> get basePath =>
      $composableBuilder(column: $table.basePath, builder: (column) => column);

  GeneratedColumn<String> get lastSyncedSha => $composableBuilder(
    column: $table.lastSyncedSha,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get includeSecrets => $composableBuilder(
    column: $table.includeSecrets,
    builder: (column) => column,
  );

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> gitBaseEntriesRefs<T extends Object>(
    Expression<T> Function($$GitBaseEntriesTableAnnotationComposer a) f,
  ) {
    final $$GitBaseEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gitBaseEntries,
      getReferencedColumn: (t) => t.linkId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitBaseEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.gitBaseEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GitLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GitLinksTable,
          GitLinkRow,
          $$GitLinksTableFilterComposer,
          $$GitLinksTableOrderingComposer,
          $$GitLinksTableAnnotationComposer,
          $$GitLinksTableCreateCompanionBuilder,
          $$GitLinksTableUpdateCompanionBuilder,
          (GitLinkRow, $$GitLinksTableReferences),
          GitLinkRow,
          PrefetchHooks Function({bool collectionId, bool gitBaseEntriesRefs})
        > {
  $$GitLinksTableTableManager(_$AppDatabase db, $GitLinksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GitLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GitLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GitLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> collectionId = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> owner = const Value.absent(),
                Value<String> repo = const Value.absent(),
                Value<String> branch = const Value.absent(),
                Value<String> basePath = const Value.absent(),
                Value<String?> lastSyncedSha = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<bool> includeSecrets = const Value.absent(),
              }) => GitLinksCompanion(
                id: id,
                collectionId: collectionId,
                provider: provider,
                owner: owner,
                repo: repo,
                branch: branch,
                basePath: basePath,
                lastSyncedSha: lastSyncedSha,
                lastSyncedAt: lastSyncedAt,
                includeSecrets: includeSecrets,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int collectionId,
                required String provider,
                required String owner,
                required String repo,
                required String branch,
                Value<String> basePath = const Value.absent(),
                Value<String?> lastSyncedSha = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<bool> includeSecrets = const Value.absent(),
              }) => GitLinksCompanion.insert(
                id: id,
                collectionId: collectionId,
                provider: provider,
                owner: owner,
                repo: repo,
                branch: branch,
                basePath: basePath,
                lastSyncedSha: lastSyncedSha,
                lastSyncedAt: lastSyncedAt,
                includeSecrets: includeSecrets,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GitLinksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({collectionId = false, gitBaseEntriesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (gitBaseEntriesRefs) db.gitBaseEntries,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (collectionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.collectionId,
                                    referencedTable: $$GitLinksTableReferences
                                        ._collectionIdTable(db),
                                    referencedColumn: $$GitLinksTableReferences
                                        ._collectionIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (gitBaseEntriesRefs)
                        await $_getPrefetchedData<
                          GitLinkRow,
                          $GitLinksTable,
                          GitBaseEntry
                        >(
                          currentTable: table,
                          referencedTable: $$GitLinksTableReferences
                              ._gitBaseEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GitLinksTableReferences(
                                db,
                                table,
                                p0,
                              ).gitBaseEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.linkId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$GitLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GitLinksTable,
      GitLinkRow,
      $$GitLinksTableFilterComposer,
      $$GitLinksTableOrderingComposer,
      $$GitLinksTableAnnotationComposer,
      $$GitLinksTableCreateCompanionBuilder,
      $$GitLinksTableUpdateCompanionBuilder,
      (GitLinkRow, $$GitLinksTableReferences),
      GitLinkRow,
      PrefetchHooks Function({bool collectionId, bool gitBaseEntriesRefs})
    >;
typedef $$GitBaseEntriesTableCreateCompanionBuilder =
    GitBaseEntriesCompanion Function({
      required int linkId,
      required String uid,
      required String path,
      required String blobSha,
      required String docJson,
      Value<int> rowid,
    });
typedef $$GitBaseEntriesTableUpdateCompanionBuilder =
    GitBaseEntriesCompanion Function({
      Value<int> linkId,
      Value<String> uid,
      Value<String> path,
      Value<String> blobSha,
      Value<String> docJson,
      Value<int> rowid,
    });

final class $$GitBaseEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $GitBaseEntriesTable, GitBaseEntry> {
  $$GitBaseEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $GitLinksTable _linkIdTable(_$AppDatabase db) =>
      db.gitLinks.createAlias('git_base_entries__link_id__git_links__id');

  $$GitLinksTableProcessedTableManager get linkId {
    final $_column = $_itemColumn<int>('link_id')!;

    final manager = $$GitLinksTableTableManager(
      $_db,
      $_db.gitLinks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_linkIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GitBaseEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $GitBaseEntriesTable> {
  $$GitBaseEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blobSha => $composableBuilder(
    column: $table.blobSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get docJson => $composableBuilder(
    column: $table.docJson,
    builder: (column) => ColumnFilters(column),
  );

  $$GitLinksTableFilterComposer get linkId {
    final $$GitLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.linkId,
      referencedTable: $db.gitLinks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitLinksTableFilterComposer(
            $db: $db,
            $table: $db.gitLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GitBaseEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $GitBaseEntriesTable> {
  $$GitBaseEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blobSha => $composableBuilder(
    column: $table.blobSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get docJson => $composableBuilder(
    column: $table.docJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$GitLinksTableOrderingComposer get linkId {
    final $$GitLinksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.linkId,
      referencedTable: $db.gitLinks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitLinksTableOrderingComposer(
            $db: $db,
            $table: $db.gitLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GitBaseEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GitBaseEntriesTable> {
  $$GitBaseEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get blobSha =>
      $composableBuilder(column: $table.blobSha, builder: (column) => column);

  GeneratedColumn<String> get docJson =>
      $composableBuilder(column: $table.docJson, builder: (column) => column);

  $$GitLinksTableAnnotationComposer get linkId {
    final $$GitLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.linkId,
      referencedTable: $db.gitLinks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GitLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.gitLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GitBaseEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GitBaseEntriesTable,
          GitBaseEntry,
          $$GitBaseEntriesTableFilterComposer,
          $$GitBaseEntriesTableOrderingComposer,
          $$GitBaseEntriesTableAnnotationComposer,
          $$GitBaseEntriesTableCreateCompanionBuilder,
          $$GitBaseEntriesTableUpdateCompanionBuilder,
          (GitBaseEntry, $$GitBaseEntriesTableReferences),
          GitBaseEntry,
          PrefetchHooks Function({bool linkId})
        > {
  $$GitBaseEntriesTableTableManager(
    _$AppDatabase db,
    $GitBaseEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GitBaseEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GitBaseEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GitBaseEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> linkId = const Value.absent(),
                Value<String> uid = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> blobSha = const Value.absent(),
                Value<String> docJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GitBaseEntriesCompanion(
                linkId: linkId,
                uid: uid,
                path: path,
                blobSha: blobSha,
                docJson: docJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int linkId,
                required String uid,
                required String path,
                required String blobSha,
                required String docJson,
                Value<int> rowid = const Value.absent(),
              }) => GitBaseEntriesCompanion.insert(
                linkId: linkId,
                uid: uid,
                path: path,
                blobSha: blobSha,
                docJson: docJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GitBaseEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({linkId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (linkId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.linkId,
                                referencedTable: $$GitBaseEntriesTableReferences
                                    ._linkIdTable(db),
                                referencedColumn:
                                    $$GitBaseEntriesTableReferences
                                        ._linkIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GitBaseEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GitBaseEntriesTable,
      GitBaseEntry,
      $$GitBaseEntriesTableFilterComposer,
      $$GitBaseEntriesTableOrderingComposer,
      $$GitBaseEntriesTableAnnotationComposer,
      $$GitBaseEntriesTableCreateCompanionBuilder,
      $$GitBaseEntriesTableUpdateCompanionBuilder,
      (GitBaseEntry, $$GitBaseEntriesTableReferences),
      GitBaseEntry,
      PrefetchHooks Function({bool linkId})
    >;
typedef $$SettingEntriesTableCreateCompanionBuilder =
    SettingEntriesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingEntriesTableUpdateCompanionBuilder =
    SettingEntriesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingEntriesTable> {
  $$SettingEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingEntriesTable,
          SettingEntry,
          $$SettingEntriesTableFilterComposer,
          $$SettingEntriesTableOrderingComposer,
          $$SettingEntriesTableAnnotationComposer,
          $$SettingEntriesTableCreateCompanionBuilder,
          $$SettingEntriesTableUpdateCompanionBuilder,
          (
            SettingEntry,
            BaseReferences<_$AppDatabase, $SettingEntriesTable, SettingEntry>,
          ),
          SettingEntry,
          PrefetchHooks Function()
        > {
  $$SettingEntriesTableTableManager(
    _$AppDatabase db,
    $SettingEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  SettingEntriesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingEntriesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingEntriesTable,
      SettingEntry,
      $$SettingEntriesTableFilterComposer,
      $$SettingEntriesTableOrderingComposer,
      $$SettingEntriesTableAnnotationComposer,
      $$SettingEntriesTableCreateCompanionBuilder,
      $$SettingEntriesTableUpdateCompanionBuilder,
      (
        SettingEntry,
        BaseReferences<_$AppDatabase, $SettingEntriesTable, SettingEntry>,
      ),
      SettingEntry,
      PrefetchHooks Function()
    >;
typedef $$RequestSettingEntriesTableCreateCompanionBuilder =
    RequestSettingEntriesCompanion Function({
      Value<int> requestId,
      Value<String> settingsJson,
    });
typedef $$RequestSettingEntriesTableUpdateCompanionBuilder =
    RequestSettingEntriesCompanion Function({
      Value<int> requestId,
      Value<String> settingsJson,
    });

final class $$RequestSettingEntriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RequestSettingEntriesTable,
          RequestSettingEntry
        > {
  $$RequestSettingEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RequestsTable _requestIdTable(_$AppDatabase db) => db.requests
      .createAlias('request_setting_entries__request_id__requests__id');

  $$RequestsTableProcessedTableManager get requestId {
    final $_column = $_itemColumn<int>('request_id')!;

    final manager = $$RequestsTableTableManager(
      $_db,
      $_db.requests,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_requestIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RequestSettingEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $RequestSettingEntriesTable> {
  $$RequestSettingEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$RequestsTableFilterComposer get requestId {
    final $$RequestsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableFilterComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestSettingEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RequestSettingEntriesTable> {
  $$RequestSettingEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$RequestsTableOrderingComposer get requestId {
    final $$RequestsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableOrderingComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestSettingEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RequestSettingEntriesTable> {
  $$RequestSettingEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => column,
  );

  $$RequestsTableAnnotationComposer get requestId {
    final $$RequestsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableAnnotationComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestSettingEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RequestSettingEntriesTable,
          RequestSettingEntry,
          $$RequestSettingEntriesTableFilterComposer,
          $$RequestSettingEntriesTableOrderingComposer,
          $$RequestSettingEntriesTableAnnotationComposer,
          $$RequestSettingEntriesTableCreateCompanionBuilder,
          $$RequestSettingEntriesTableUpdateCompanionBuilder,
          (RequestSettingEntry, $$RequestSettingEntriesTableReferences),
          RequestSettingEntry,
          PrefetchHooks Function({bool requestId})
        > {
  $$RequestSettingEntriesTableTableManager(
    _$AppDatabase db,
    $RequestSettingEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RequestSettingEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RequestSettingEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RequestSettingEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> requestId = const Value.absent(),
                Value<String> settingsJson = const Value.absent(),
              }) => RequestSettingEntriesCompanion(
                requestId: requestId,
                settingsJson: settingsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> requestId = const Value.absent(),
                Value<String> settingsJson = const Value.absent(),
              }) => RequestSettingEntriesCompanion.insert(
                requestId: requestId,
                settingsJson: settingsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RequestSettingEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({requestId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (requestId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.requestId,
                                referencedTable:
                                    $$RequestSettingEntriesTableReferences
                                        ._requestIdTable(db),
                                referencedColumn:
                                    $$RequestSettingEntriesTableReferences
                                        ._requestIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RequestSettingEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RequestSettingEntriesTable,
      RequestSettingEntry,
      $$RequestSettingEntriesTableFilterComposer,
      $$RequestSettingEntriesTableOrderingComposer,
      $$RequestSettingEntriesTableAnnotationComposer,
      $$RequestSettingEntriesTableCreateCompanionBuilder,
      $$RequestSettingEntriesTableUpdateCompanionBuilder,
      (RequestSettingEntry, $$RequestSettingEntriesTableReferences),
      RequestSettingEntry,
      PrefetchHooks Function({bool requestId})
    >;
typedef $$EntityDocsTableCreateCompanionBuilder =
    EntityDocsCompanion Function({
      required String kind,
      required int localId,
      Value<String> markdown,
      Value<int> rowid,
    });
typedef $$EntityDocsTableUpdateCompanionBuilder =
    EntityDocsCompanion Function({
      Value<String> kind,
      Value<int> localId,
      Value<String> markdown,
      Value<int> rowid,
    });

class $$EntityDocsTableFilterComposer
    extends Composer<_$AppDatabase, $EntityDocsTable> {
  $$EntityDocsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get markdown => $composableBuilder(
    column: $table.markdown,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntityDocsTableOrderingComposer
    extends Composer<_$AppDatabase, $EntityDocsTable> {
  $$EntityDocsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get markdown => $composableBuilder(
    column: $table.markdown,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntityDocsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntityDocsTable> {
  $$EntityDocsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get markdown =>
      $composableBuilder(column: $table.markdown, builder: (column) => column);
}

class $$EntityDocsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntityDocsTable,
          EntityDoc,
          $$EntityDocsTableFilterComposer,
          $$EntityDocsTableOrderingComposer,
          $$EntityDocsTableAnnotationComposer,
          $$EntityDocsTableCreateCompanionBuilder,
          $$EntityDocsTableUpdateCompanionBuilder,
          (
            EntityDoc,
            BaseReferences<_$AppDatabase, $EntityDocsTable, EntityDoc>,
          ),
          EntityDoc,
          PrefetchHooks Function()
        > {
  $$EntityDocsTableTableManager(_$AppDatabase db, $EntityDocsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntityDocsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntityDocsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntityDocsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<int> localId = const Value.absent(),
                Value<String> markdown = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntityDocsCompanion(
                kind: kind,
                localId: localId,
                markdown: markdown,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required int localId,
                Value<String> markdown = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntityDocsCompanion.insert(
                kind: kind,
                localId: localId,
                markdown: markdown,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntityDocsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntityDocsTable,
      EntityDoc,
      $$EntityDocsTableFilterComposer,
      $$EntityDocsTableOrderingComposer,
      $$EntityDocsTableAnnotationComposer,
      $$EntityDocsTableCreateCompanionBuilder,
      $$EntityDocsTableUpdateCompanionBuilder,
      (EntityDoc, BaseReferences<_$AppDatabase, $EntityDocsTable, EntityDoc>),
      EntityDoc,
      PrefetchHooks Function()
    >;
typedef $$EntityTagsTableCreateCompanionBuilder =
    EntityTagsCompanion Function({
      required String kind,
      required int localId,
      required String tag,
      Value<int> rowid,
    });
typedef $$EntityTagsTableUpdateCompanionBuilder =
    EntityTagsCompanion Function({
      Value<String> kind,
      Value<int> localId,
      Value<String> tag,
      Value<int> rowid,
    });

class $$EntityTagsTableFilterComposer
    extends Composer<_$AppDatabase, $EntityTagsTable> {
  $$EntityTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntityTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $EntityTagsTable> {
  $$EntityTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntityTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntityTagsTable> {
  $$EntityTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);
}

class $$EntityTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntityTagsTable,
          EntityTag,
          $$EntityTagsTableFilterComposer,
          $$EntityTagsTableOrderingComposer,
          $$EntityTagsTableAnnotationComposer,
          $$EntityTagsTableCreateCompanionBuilder,
          $$EntityTagsTableUpdateCompanionBuilder,
          (
            EntityTag,
            BaseReferences<_$AppDatabase, $EntityTagsTable, EntityTag>,
          ),
          EntityTag,
          PrefetchHooks Function()
        > {
  $$EntityTagsTableTableManager(_$AppDatabase db, $EntityTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntityTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntityTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntityTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<int> localId = const Value.absent(),
                Value<String> tag = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntityTagsCompanion(
                kind: kind,
                localId: localId,
                tag: tag,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required int localId,
                required String tag,
                Value<int> rowid = const Value.absent(),
              }) => EntityTagsCompanion.insert(
                kind: kind,
                localId: localId,
                tag: tag,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntityTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntityTagsTable,
      EntityTag,
      $$EntityTagsTableFilterComposer,
      $$EntityTagsTableOrderingComposer,
      $$EntityTagsTableAnnotationComposer,
      $$EntityTagsTableCreateCompanionBuilder,
      $$EntityTagsTableUpdateCompanionBuilder,
      (EntityTag, BaseReferences<_$AppDatabase, $EntityTagsTable, EntityTag>),
      EntityTag,
      PrefetchHooks Function()
    >;
typedef $$FolderDefaultsTableCreateCompanionBuilder =
    FolderDefaultsCompanion Function({
      Value<int> folderId,
      Value<String> headersJson,
      Value<String> variablesJson,
      Value<String> authJson,
      Value<String> scriptsJson,
    });
typedef $$FolderDefaultsTableUpdateCompanionBuilder =
    FolderDefaultsCompanion Function({
      Value<int> folderId,
      Value<String> headersJson,
      Value<String> variablesJson,
      Value<String> authJson,
      Value<String> scriptsJson,
    });

final class $$FolderDefaultsTableReferences
    extends BaseReferences<_$AppDatabase, $FolderDefaultsTable, FolderDefault> {
  $$FolderDefaultsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FoldersTable _folderIdTable(_$AppDatabase db) =>
      db.folders.createAlias('folder_defaults__folder_id__folders__id');

  $$FoldersTableProcessedTableManager get folderId {
    final $_column = $_itemColumn<int>('folder_id')!;

    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_folderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FolderDefaultsTableFilterComposer
    extends Composer<_$AppDatabase, $FolderDefaultsTable> {
  $$FolderDefaultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variablesJson => $composableBuilder(
    column: $table.variablesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authJson => $composableBuilder(
    column: $table.authJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scriptsJson => $composableBuilder(
    column: $table.scriptsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$FoldersTableFilterComposer get folderId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FolderDefaultsTableOrderingComposer
    extends Composer<_$AppDatabase, $FolderDefaultsTable> {
  $$FolderDefaultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variablesJson => $composableBuilder(
    column: $table.variablesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authJson => $composableBuilder(
    column: $table.authJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scriptsJson => $composableBuilder(
    column: $table.scriptsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoldersTableOrderingComposer get folderId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FolderDefaultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FolderDefaultsTable> {
  $$FolderDefaultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get variablesJson => $composableBuilder(
    column: $table.variablesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authJson =>
      $composableBuilder(column: $table.authJson, builder: (column) => column);

  GeneratedColumn<String> get scriptsJson => $composableBuilder(
    column: $table.scriptsJson,
    builder: (column) => column,
  );

  $$FoldersTableAnnotationComposer get folderId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FolderDefaultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FolderDefaultsTable,
          FolderDefault,
          $$FolderDefaultsTableFilterComposer,
          $$FolderDefaultsTableOrderingComposer,
          $$FolderDefaultsTableAnnotationComposer,
          $$FolderDefaultsTableCreateCompanionBuilder,
          $$FolderDefaultsTableUpdateCompanionBuilder,
          (FolderDefault, $$FolderDefaultsTableReferences),
          FolderDefault,
          PrefetchHooks Function({bool folderId})
        > {
  $$FolderDefaultsTableTableManager(
    _$AppDatabase db,
    $FolderDefaultsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FolderDefaultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FolderDefaultsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FolderDefaultsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> folderId = const Value.absent(),
                Value<String> headersJson = const Value.absent(),
                Value<String> variablesJson = const Value.absent(),
                Value<String> authJson = const Value.absent(),
                Value<String> scriptsJson = const Value.absent(),
              }) => FolderDefaultsCompanion(
                folderId: folderId,
                headersJson: headersJson,
                variablesJson: variablesJson,
                authJson: authJson,
                scriptsJson: scriptsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> folderId = const Value.absent(),
                Value<String> headersJson = const Value.absent(),
                Value<String> variablesJson = const Value.absent(),
                Value<String> authJson = const Value.absent(),
                Value<String> scriptsJson = const Value.absent(),
              }) => FolderDefaultsCompanion.insert(
                folderId: folderId,
                headersJson: headersJson,
                variablesJson: variablesJson,
                authJson: authJson,
                scriptsJson: scriptsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FolderDefaultsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({folderId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (folderId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.folderId,
                                referencedTable: $$FolderDefaultsTableReferences
                                    ._folderIdTable(db),
                                referencedColumn:
                                    $$FolderDefaultsTableReferences
                                        ._folderIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FolderDefaultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FolderDefaultsTable,
      FolderDefault,
      $$FolderDefaultsTableFilterComposer,
      $$FolderDefaultsTableOrderingComposer,
      $$FolderDefaultsTableAnnotationComposer,
      $$FolderDefaultsTableCreateCompanionBuilder,
      $$FolderDefaultsTableUpdateCompanionBuilder,
      (FolderDefault, $$FolderDefaultsTableReferences),
      FolderDefault,
      PrefetchHooks Function({bool folderId})
    >;
typedef $$CollectionDefaultsTableCreateCompanionBuilder =
    CollectionDefaultsCompanion Function({
      Value<int> collectionId,
      Value<String> headersJson,
      Value<String> scriptsJson,
    });
typedef $$CollectionDefaultsTableUpdateCompanionBuilder =
    CollectionDefaultsCompanion Function({
      Value<int> collectionId,
      Value<String> headersJson,
      Value<String> scriptsJson,
    });

final class $$CollectionDefaultsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CollectionDefaultsTable,
          CollectionDefault
        > {
  $$CollectionDefaultsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) => db
      .collections
      .createAlias('collection_defaults__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<int>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CollectionDefaultsTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionDefaultsTable> {
  $$CollectionDefaultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scriptsJson => $composableBuilder(
    column: $table.scriptsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionDefaultsTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionDefaultsTable> {
  $$CollectionDefaultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scriptsJson => $composableBuilder(
    column: $table.scriptsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionDefaultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionDefaultsTable> {
  $$CollectionDefaultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get headersJson => $composableBuilder(
    column: $table.headersJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scriptsJson => $composableBuilder(
    column: $table.scriptsJson,
    builder: (column) => column,
  );

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionDefaultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionDefaultsTable,
          CollectionDefault,
          $$CollectionDefaultsTableFilterComposer,
          $$CollectionDefaultsTableOrderingComposer,
          $$CollectionDefaultsTableAnnotationComposer,
          $$CollectionDefaultsTableCreateCompanionBuilder,
          $$CollectionDefaultsTableUpdateCompanionBuilder,
          (CollectionDefault, $$CollectionDefaultsTableReferences),
          CollectionDefault,
          PrefetchHooks Function({bool collectionId})
        > {
  $$CollectionDefaultsTableTableManager(
    _$AppDatabase db,
    $CollectionDefaultsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionDefaultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionDefaultsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionDefaultsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> collectionId = const Value.absent(),
                Value<String> headersJson = const Value.absent(),
                Value<String> scriptsJson = const Value.absent(),
              }) => CollectionDefaultsCompanion(
                collectionId: collectionId,
                headersJson: headersJson,
                scriptsJson: scriptsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> collectionId = const Value.absent(),
                Value<String> headersJson = const Value.absent(),
                Value<String> scriptsJson = const Value.absent(),
              }) => CollectionDefaultsCompanion.insert(
                collectionId: collectionId,
                headersJson: headersJson,
                scriptsJson: scriptsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CollectionDefaultsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({collectionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (collectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.collectionId,
                                referencedTable:
                                    $$CollectionDefaultsTableReferences
                                        ._collectionIdTable(db),
                                referencedColumn:
                                    $$CollectionDefaultsTableReferences
                                        ._collectionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CollectionDefaultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionDefaultsTable,
      CollectionDefault,
      $$CollectionDefaultsTableFilterComposer,
      $$CollectionDefaultsTableOrderingComposer,
      $$CollectionDefaultsTableAnnotationComposer,
      $$CollectionDefaultsTableCreateCompanionBuilder,
      $$CollectionDefaultsTableUpdateCompanionBuilder,
      (CollectionDefault, $$CollectionDefaultsTableReferences),
      CollectionDefault,
      PrefetchHooks Function({bool collectionId})
    >;
typedef $$HistoryPayloadsTableCreateCompanionBuilder =
    HistoryPayloadsCompanion Function({
      Value<int> historyId,
      Value<String> requestJson,
      Value<String?> responseText,
      Value<String?> responseContentType,
      Value<bool> responseTruncated,
      Value<String> searchText,
    });
typedef $$HistoryPayloadsTableUpdateCompanionBuilder =
    HistoryPayloadsCompanion Function({
      Value<int> historyId,
      Value<String> requestJson,
      Value<String?> responseText,
      Value<String?> responseContentType,
      Value<bool> responseTruncated,
      Value<String> searchText,
    });

final class $$HistoryPayloadsTableReferences
    extends
        BaseReferences<_$AppDatabase, $HistoryPayloadsTable, HistoryPayload> {
  $$HistoryPayloadsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $HistoryEntriesTable _historyIdTable(_$AppDatabase db) => db
      .historyEntries
      .createAlias('history_payloads__history_id__history_entries__id');

  $$HistoryEntriesTableProcessedTableManager get historyId {
    final $_column = $_itemColumn<int>('history_id')!;

    final manager = $$HistoryEntriesTableTableManager(
      $_db,
      $_db.historyEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_historyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$HistoryPayloadsTableFilterComposer
    extends Composer<_$AppDatabase, $HistoryPayloadsTable> {
  $$HistoryPayloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get responseText => $composableBuilder(
    column: $table.responseText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get responseContentType => $composableBuilder(
    column: $table.responseContentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get responseTruncated => $composableBuilder(
    column: $table.responseTruncated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );

  $$HistoryEntriesTableFilterComposer get historyId {
    final $$HistoryEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.historyId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableFilterComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HistoryPayloadsTableOrderingComposer
    extends Composer<_$AppDatabase, $HistoryPayloadsTable> {
  $$HistoryPayloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get responseText => $composableBuilder(
    column: $table.responseText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get responseContentType => $composableBuilder(
    column: $table.responseContentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get responseTruncated => $composableBuilder(
    column: $table.responseTruncated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );

  $$HistoryEntriesTableOrderingComposer get historyId {
    final $$HistoryEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.historyId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HistoryPayloadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HistoryPayloadsTable> {
  $$HistoryPayloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get responseText => $composableBuilder(
    column: $table.responseText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get responseContentType => $composableBuilder(
    column: $table.responseContentType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get responseTruncated => $composableBuilder(
    column: $table.responseTruncated,
    builder: (column) => column,
  );

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );

  $$HistoryEntriesTableAnnotationComposer get historyId {
    final $$HistoryEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.historyId,
      referencedTable: $db.historyEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HistoryEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.historyEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HistoryPayloadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HistoryPayloadsTable,
          HistoryPayload,
          $$HistoryPayloadsTableFilterComposer,
          $$HistoryPayloadsTableOrderingComposer,
          $$HistoryPayloadsTableAnnotationComposer,
          $$HistoryPayloadsTableCreateCompanionBuilder,
          $$HistoryPayloadsTableUpdateCompanionBuilder,
          (HistoryPayload, $$HistoryPayloadsTableReferences),
          HistoryPayload,
          PrefetchHooks Function({bool historyId})
        > {
  $$HistoryPayloadsTableTableManager(
    _$AppDatabase db,
    $HistoryPayloadsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryPayloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryPayloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryPayloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> historyId = const Value.absent(),
                Value<String> requestJson = const Value.absent(),
                Value<String?> responseText = const Value.absent(),
                Value<String?> responseContentType = const Value.absent(),
                Value<bool> responseTruncated = const Value.absent(),
                Value<String> searchText = const Value.absent(),
              }) => HistoryPayloadsCompanion(
                historyId: historyId,
                requestJson: requestJson,
                responseText: responseText,
                responseContentType: responseContentType,
                responseTruncated: responseTruncated,
                searchText: searchText,
              ),
          createCompanionCallback:
              ({
                Value<int> historyId = const Value.absent(),
                Value<String> requestJson = const Value.absent(),
                Value<String?> responseText = const Value.absent(),
                Value<String?> responseContentType = const Value.absent(),
                Value<bool> responseTruncated = const Value.absent(),
                Value<String> searchText = const Value.absent(),
              }) => HistoryPayloadsCompanion.insert(
                historyId: historyId,
                requestJson: requestJson,
                responseText: responseText,
                responseContentType: responseContentType,
                responseTruncated: responseTruncated,
                searchText: searchText,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HistoryPayloadsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({historyId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (historyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.historyId,
                                referencedTable:
                                    $$HistoryPayloadsTableReferences
                                        ._historyIdTable(db),
                                referencedColumn:
                                    $$HistoryPayloadsTableReferences
                                        ._historyIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$HistoryPayloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HistoryPayloadsTable,
      HistoryPayload,
      $$HistoryPayloadsTableFilterComposer,
      $$HistoryPayloadsTableOrderingComposer,
      $$HistoryPayloadsTableAnnotationComposer,
      $$HistoryPayloadsTableCreateCompanionBuilder,
      $$HistoryPayloadsTableUpdateCompanionBuilder,
      (HistoryPayload, $$HistoryPayloadsTableReferences),
      HistoryPayload,
      PrefetchHooks Function({bool historyId})
    >;
typedef $$RunRecordsTableCreateCompanionBuilder =
    RunRecordsCompanion Function({
      Value<int> id,
      required int collectionId,
      Value<String> environmentName,
      Value<String> source,
      Value<int> passed,
      Value<int> failed,
      Value<int> skipped,
      Value<int> durationMs,
      Value<String> summaryJson,
      Value<String> resultsJson,
      Value<DateTime> startedAt,
    });
typedef $$RunRecordsTableUpdateCompanionBuilder =
    RunRecordsCompanion Function({
      Value<int> id,
      Value<int> collectionId,
      Value<String> environmentName,
      Value<String> source,
      Value<int> passed,
      Value<int> failed,
      Value<int> skipped,
      Value<int> durationMs,
      Value<String> summaryJson,
      Value<String> resultsJson,
      Value<DateTime> startedAt,
    });

final class $$RunRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $RunRecordsTable, RunRecord> {
  $$RunRecordsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) =>
      db.collections.createAlias('run_records__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<int>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RunRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $RunRecordsTable> {
  $$RunRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get environmentName => $composableBuilder(
    column: $table.environmentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get passed => $composableBuilder(
    column: $table.passed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failed => $composableBuilder(
    column: $table.failed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get skipped => $composableBuilder(
    column: $table.skipped,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultsJson => $composableBuilder(
    column: $table.resultsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RunRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $RunRecordsTable> {
  $$RunRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get environmentName => $composableBuilder(
    column: $table.environmentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get passed => $composableBuilder(
    column: $table.passed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failed => $composableBuilder(
    column: $table.failed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get skipped => $composableBuilder(
    column: $table.skipped,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultsJson => $composableBuilder(
    column: $table.resultsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RunRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RunRecordsTable> {
  $$RunRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get environmentName => $composableBuilder(
    column: $table.environmentName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get passed =>
      $composableBuilder(column: $table.passed, builder: (column) => column);

  GeneratedColumn<int> get failed =>
      $composableBuilder(column: $table.failed, builder: (column) => column);

  GeneratedColumn<int> get skipped =>
      $composableBuilder(column: $table.skipped, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultsJson => $composableBuilder(
    column: $table.resultsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RunRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RunRecordsTable,
          RunRecord,
          $$RunRecordsTableFilterComposer,
          $$RunRecordsTableOrderingComposer,
          $$RunRecordsTableAnnotationComposer,
          $$RunRecordsTableCreateCompanionBuilder,
          $$RunRecordsTableUpdateCompanionBuilder,
          (RunRecord, $$RunRecordsTableReferences),
          RunRecord,
          PrefetchHooks Function({bool collectionId})
        > {
  $$RunRecordsTableTableManager(_$AppDatabase db, $RunRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RunRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RunRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RunRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> collectionId = const Value.absent(),
                Value<String> environmentName = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> passed = const Value.absent(),
                Value<int> failed = const Value.absent(),
                Value<int> skipped = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> summaryJson = const Value.absent(),
                Value<String> resultsJson = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
              }) => RunRecordsCompanion(
                id: id,
                collectionId: collectionId,
                environmentName: environmentName,
                source: source,
                passed: passed,
                failed: failed,
                skipped: skipped,
                durationMs: durationMs,
                summaryJson: summaryJson,
                resultsJson: resultsJson,
                startedAt: startedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int collectionId,
                Value<String> environmentName = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> passed = const Value.absent(),
                Value<int> failed = const Value.absent(),
                Value<int> skipped = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> summaryJson = const Value.absent(),
                Value<String> resultsJson = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
              }) => RunRecordsCompanion.insert(
                id: id,
                collectionId: collectionId,
                environmentName: environmentName,
                source: source,
                passed: passed,
                failed: failed,
                skipped: skipped,
                durationMs: durationMs,
                summaryJson: summaryJson,
                resultsJson: resultsJson,
                startedAt: startedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RunRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({collectionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (collectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.collectionId,
                                referencedTable: $$RunRecordsTableReferences
                                    ._collectionIdTable(db),
                                referencedColumn: $$RunRecordsTableReferences
                                    ._collectionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RunRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RunRecordsTable,
      RunRecord,
      $$RunRecordsTableFilterComposer,
      $$RunRecordsTableOrderingComposer,
      $$RunRecordsTableAnnotationComposer,
      $$RunRecordsTableCreateCompanionBuilder,
      $$RunRecordsTableUpdateCompanionBuilder,
      (RunRecord, $$RunRecordsTableReferences),
      RunRecord,
      PrefetchHooks Function({bool collectionId})
    >;
typedef $$RequestBaselinesTableCreateCompanionBuilder =
    RequestBaselinesCompanion Function({
      Value<int> requestId,
      Value<String> snapshotJson,
      Value<String> note,
      Value<DateTime> recordedAt,
    });
typedef $$RequestBaselinesTableUpdateCompanionBuilder =
    RequestBaselinesCompanion Function({
      Value<int> requestId,
      Value<String> snapshotJson,
      Value<String> note,
      Value<DateTime> recordedAt,
    });

final class $$RequestBaselinesTableReferences
    extends
        BaseReferences<_$AppDatabase, $RequestBaselinesTable, RequestBaseline> {
  $$RequestBaselinesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RequestsTable _requestIdTable(_$AppDatabase db) =>
      db.requests.createAlias('request_baselines__request_id__requests__id');

  $$RequestsTableProcessedTableManager get requestId {
    final $_column = $_itemColumn<int>('request_id')!;

    final manager = $$RequestsTableTableManager(
      $_db,
      $_db.requests,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_requestIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RequestBaselinesTableFilterComposer
    extends Composer<_$AppDatabase, $RequestBaselinesTable> {
  $$RequestBaselinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RequestsTableFilterComposer get requestId {
    final $$RequestsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableFilterComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestBaselinesTableOrderingComposer
    extends Composer<_$AppDatabase, $RequestBaselinesTable> {
  $$RequestBaselinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RequestsTableOrderingComposer get requestId {
    final $$RequestsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableOrderingComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestBaselinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RequestBaselinesTable> {
  $$RequestBaselinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );

  $$RequestsTableAnnotationComposer get requestId {
    final $$RequestsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.requestId,
      referencedTable: $db.requests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RequestsTableAnnotationComposer(
            $db: $db,
            $table: $db.requests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RequestBaselinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RequestBaselinesTable,
          RequestBaseline,
          $$RequestBaselinesTableFilterComposer,
          $$RequestBaselinesTableOrderingComposer,
          $$RequestBaselinesTableAnnotationComposer,
          $$RequestBaselinesTableCreateCompanionBuilder,
          $$RequestBaselinesTableUpdateCompanionBuilder,
          (RequestBaseline, $$RequestBaselinesTableReferences),
          RequestBaseline,
          PrefetchHooks Function({bool requestId})
        > {
  $$RequestBaselinesTableTableManager(
    _$AppDatabase db,
    $RequestBaselinesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RequestBaselinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RequestBaselinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RequestBaselinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> requestId = const Value.absent(),
                Value<String> snapshotJson = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
              }) => RequestBaselinesCompanion(
                requestId: requestId,
                snapshotJson: snapshotJson,
                note: note,
                recordedAt: recordedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> requestId = const Value.absent(),
                Value<String> snapshotJson = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
              }) => RequestBaselinesCompanion.insert(
                requestId: requestId,
                snapshotJson: snapshotJson,
                note: note,
                recordedAt: recordedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RequestBaselinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({requestId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (requestId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.requestId,
                                referencedTable:
                                    $$RequestBaselinesTableReferences
                                        ._requestIdTable(db),
                                referencedColumn:
                                    $$RequestBaselinesTableReferences
                                        ._requestIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RequestBaselinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RequestBaselinesTable,
      RequestBaseline,
      $$RequestBaselinesTableFilterComposer,
      $$RequestBaselinesTableOrderingComposer,
      $$RequestBaselinesTableAnnotationComposer,
      $$RequestBaselinesTableCreateCompanionBuilder,
      $$RequestBaselinesTableUpdateCompanionBuilder,
      (RequestBaseline, $$RequestBaselinesTableReferences),
      RequestBaseline,
      PrefetchHooks Function({bool requestId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db, _db.collections);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$RequestsTableTableManager get requests =>
      $$RequestsTableTableManager(_db, _db.requests);
  $$EnvironmentsTableTableManager get environments =>
      $$EnvironmentsTableTableManager(_db, _db.environments);
  $$EnvironmentVariablesTableTableManager get environmentVariables =>
      $$EnvironmentVariablesTableTableManager(_db, _db.environmentVariables);
  $$HistoryEntriesTableTableManager get historyEntries =>
      $$HistoryEntriesTableTableManager(_db, _db.historyEntries);
  $$GlobalVariablesTableTableManager get globalVariables =>
      $$GlobalVariablesTableTableManager(_db, _db.globalVariables);
  $$CollectionVariablesTableTableManager get collectionVariables =>
      $$CollectionVariablesTableTableManager(_db, _db.collectionVariables);
  $$CollectionAuthTableTableManager get collectionAuth =>
      $$CollectionAuthTableTableManager(_db, _db.collectionAuth);
  $$RequestScriptsTableTableManager get requestScripts =>
      $$RequestScriptsTableTableManager(_db, _db.requestScripts);
  $$ResponseExamplesTableTableManager get responseExamples =>
      $$ResponseExamplesTableTableManager(_db, _db.responseExamples);
  $$EntityUidsTableTableManager get entityUids =>
      $$EntityUidsTableTableManager(_db, _db.entityUids);
  $$GitLinksTableTableManager get gitLinks =>
      $$GitLinksTableTableManager(_db, _db.gitLinks);
  $$GitBaseEntriesTableTableManager get gitBaseEntries =>
      $$GitBaseEntriesTableTableManager(_db, _db.gitBaseEntries);
  $$SettingEntriesTableTableManager get settingEntries =>
      $$SettingEntriesTableTableManager(_db, _db.settingEntries);
  $$RequestSettingEntriesTableTableManager get requestSettingEntries =>
      $$RequestSettingEntriesTableTableManager(_db, _db.requestSettingEntries);
  $$EntityDocsTableTableManager get entityDocs =>
      $$EntityDocsTableTableManager(_db, _db.entityDocs);
  $$EntityTagsTableTableManager get entityTags =>
      $$EntityTagsTableTableManager(_db, _db.entityTags);
  $$FolderDefaultsTableTableManager get folderDefaults =>
      $$FolderDefaultsTableTableManager(_db, _db.folderDefaults);
  $$CollectionDefaultsTableTableManager get collectionDefaults =>
      $$CollectionDefaultsTableTableManager(_db, _db.collectionDefaults);
  $$HistoryPayloadsTableTableManager get historyPayloads =>
      $$HistoryPayloadsTableTableManager(_db, _db.historyPayloads);
  $$RunRecordsTableTableManager get runRecords =>
      $$RunRecordsTableTableManager(_db, _db.runRecords);
  $$RequestBaselinesTableTableManager get requestBaselines =>
      $$RequestBaselinesTableTableManager(_db, _db.requestBaselines);
}
