import 'dart:convert';
import 'mock_faker.dart';
import 'mock_spec.dart';

/// The wrapper an API puts around its answers: `{"data": [...], "total": 42}` for a list, `{"data": {...}}` for one
/// item. [payloadKey] is where the data is, [meta] the other properties (with their schemas).
final class MockEnvelope {
  final String payloadKey;
  final Map<String, Map<String, dynamic>> meta;
  const MockEnvelope(this.payloadKey, this.meta);
}

/// The operations on one kind of resource: a collection (`/users`) and, usually, its items (`/users/{id}`).
final class MockResourceFamily {
  /// A collection under another resource has a different list for each parent (`/users/{userId}/orders`).
  final String collectionTemplate;
  final List<String> collectionSegments;
  final String? itemTemplate;

  /// The name of the item path's last parameter (`id`).
  final String? idParam;
  final SpecOperation? list;
  final SpecOperation? create;
  final SpecOperation? read;
  final SpecOperation? replace;
  final SpecOperation? update;
  final SpecOperation? remove;

  /// What one item looks like, resolved.
  final Map<String, dynamic> itemSchema;
  final MockEnvelope? listEnvelope;
  final MockEnvelope? itemEnvelope;

  /// The property holding the id, and whether it is a number (else text).
  final String idField;
  final bool integerIds;

  const MockResourceFamily({
    required this.collectionTemplate,
    required this.collectionSegments,
    required this.itemTemplate,
    required this.idParam,
    required this.list,
    required this.create,
    required this.read,
    required this.replace,
    required this.update,
    required this.remove,
    required this.itemSchema,
    required this.listEnvelope,
    required this.itemEnvelope,
    required this.idField,
    required this.integerIds,
  });

  /// The last static segment of the collection: `users`.
  String get name => collectionSegments.lastWhere((s) => !SpecOperation.isParam(s), orElse: () => 'items');

  Iterable<SpecOperation> get operations => [?list, ?create, ?read, ?replace, ?update, ?remove];

  /// The role [op] plays in this family, or null when it is not one of its operations.
  MockResourceRole? roleOf(SpecOperation op) {
    if (identical(op, list)) return MockResourceRole.list;
    if (identical(op, create)) return MockResourceRole.create;
    if (identical(op, read)) return MockResourceRole.read;
    if (identical(op, replace)) return MockResourceRole.replace;
    if (identical(op, update)) return MockResourceRole.update;
    if (identical(op, remove)) return MockResourceRole.remove;
    return null;
  }
}

enum MockResourceRole { list, create, read, replace, update, remove }

/// Finds the resource families of a document: every collection path that has a list or create operation, with the
/// item path under it when there is one.
abstract final class MockResources {
  static const _listKeys = ['data', 'items', 'results', 'content', 'records', 'rows', 'list', 'entries', 'values'];
  static const _itemKeys = ['data', 'result', 'item', 'resource', 'payload', 'record', 'content', 'entity'];

  static List<MockResourceFamily> detect(MockSpec spec) {
    final byTemplate = <String, Map<String, SpecOperation>>{};
    for (final op in spec.operations) {
      byTemplate.putIfAbsent(op.template, () => {})[op.method] = op;
    }
    final families = <MockResourceFamily>[];
    final used = <String>{};

    // An item path, `/users/{id}`, names its collection.
    for (final entry in byTemplate.entries) {
      final segments = entry.value.values.first.segments;
      if (segments.length < 2 || !SpecOperation.isParam(segments.last)) continue;
      final item = entry.value;
      if (!(item.containsKey('GET') || item.containsKey('PUT') || item.containsKey('PATCH') || item.containsKey('DELETE'))) continue;
      final collection = _find(byTemplate, segments.sublist(0, segments.length - 1));
      if (collection == null) continue;
      final ops = collection.value;
      if (!(ops.containsKey('GET') || ops.containsKey('POST'))) continue;
      if (!used.add(collection.key)) continue;
      families.add(_family(spec, collection.key, ops.values.first.segments, ops, entry.key, item, segments.last));
    }

    // A collection with no item path still keeps its list, as long as the list looks like one.
    for (final entry in byTemplate.entries) {
      final segments = entry.value.values.first.segments;
      if (used.contains(entry.key) || segments.isEmpty || SpecOperation.isParam(segments.last)) continue;
      final ops = entry.value;
      final get = ops['GET'];
      // Only a recognisable list counts here: an object that merely has an array field (`/users/me` with its tags) is not one.
      final listLike = get != null && _listPayload(spec.resolver, get, name: segments.last, strict: true) != null;
      if (!listLike) continue;
      used.add(entry.key);
      families.add(_family(spec, entry.key, segments, ops, null, const {}, null));
    }
    return families;
  }

  static MapEntry<String, Map<String, SpecOperation>>? _find(Map<String, Map<String, SpecOperation>> byTemplate, List<String> segments) {
    for (final entry in byTemplate.entries) {
      final other = entry.value.values.first.segments;
      if (other.length != segments.length) continue;
      var same = true;
      for (var i = 0; i < segments.length; i++) {
        final a = other[i];
        final b = segments[i];
        // `/users/{id}/orders` and `/users/{userId}/orders` are the same path.
        if (SpecOperation.isParam(a) && SpecOperation.isParam(b)) continue;
        if (a != b) {
          same = false;
          break;
        }
      }
      if (same) return entry;
    }
    return null;
  }

  static MockResourceFamily _family(
    MockSpec spec,
    String collectionTemplate,
    List<String> collectionSegments,
    Map<String, SpecOperation> collection,
    String? itemTemplate,
    Map<String, SpecOperation> item,
    String? idSegment,
  ) {
    final resolver = spec.resolver;
    final name = collectionSegments.lastWhere((s) => !SpecOperation.isParam(s), orElse: () => 'items');
    final list = collection['GET'];
    final read = item['GET'];

    // The item's schema: what GET one answers, else what the list holds, else what a create sends.
    MockEnvelope? itemEnvelope;
    Map<String, dynamic>? itemSchema;
    final readSchema = read?.success?.schema;
    if (readSchema != null) {
      final enveloped = _itemPayload(resolver, readSchema, name);
      if (enveloped != null) {
        itemEnvelope = enveloped.envelope;
        itemSchema = enveloped.schema;
      } else if (MockFaker.typeOf(resolver.flatten(readSchema)) == 'object') {
        itemSchema = readSchema;
      }
    }
    MockEnvelope? listEnvelope;
    if (list != null) {
      final payload = _listPayload(resolver, list, name: name);
      if (payload != null) {
        listEnvelope = payload.envelope;
        itemSchema ??= payload.items;
      }
    }
    itemSchema ??= _bodySchema(collection['POST']) ?? _bodySchema(item['PUT']) ?? _bodySchema(item['PATCH']);
    final schema = itemSchema ?? const {'type': 'object', 'properties': {'id': {'type': 'integer'}}};

    final flat = resolver.flatten(schema);
    final properties = flat['properties'] is Map ? (flat['properties'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final idParam = idSegment == null ? null : SpecOperation.paramName(idSegment);
    final idField = _idField(properties, idParam, name);
    final idProperty = properties[idField];
    final integerIds = idProperty is Map ? MockFaker.typeOf(resolver.flatten(idProperty.cast<String, dynamic>())) != 'string' : _idParamIsInteger(item, idParam);

    return MockResourceFamily(
      collectionTemplate: collectionTemplate,
      collectionSegments: collectionSegments,
      itemTemplate: itemTemplate,
      idParam: idParam,
      list: list,
      create: collection['POST'],
      read: read,
      replace: item['PUT'],
      update: item['PATCH'],
      remove: item['DELETE'],
      itemSchema: schema,
      listEnvelope: listEnvelope,
      itemEnvelope: itemEnvelope,
      idField: idField,
      integerIds: integerIds,
    );
  }

  static bool _idParamIsInteger(Map<String, SpecOperation> item, String? idParam) {
    if (idParam == null) return true;
    for (final op in item.values) {
      final p = op.parameter(idParam, 'path');
      if (p != null) return p.schema['type'] != 'string';
    }
    return true;
  }

  static Map<String, dynamic>? _bodySchema(SpecOperation? op) => op?.requestBody?.schema;

  /// `id`, else the item path's parameter (`userId`), else the property that ends in `Id` and names the resource.
  static String _idField(Map<String, dynamic> properties, String? idParam, String resource) {
    if (properties.containsKey('id')) return 'id';
    if (idParam != null && properties.containsKey(idParam)) return idParam;
    final singular = resource.endsWith('s') && resource.length > 1 ? resource.substring(0, resource.length - 1) : resource;
    for (final key in properties.keys) {
      final normal = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normal == '${singular.toLowerCase()}id') return key;
    }
    if (properties.containsKey('_id')) return '_id';
    return 'id';
  }

  /// The items and envelope of a list operation's answer, or null when it does not answer with a list.
  static ({Map<String, dynamic> items, MockEnvelope? envelope})? _listPayload(MockSchemaResolver resolver, SpecOperation op, {required String name, bool strict = false}) {
    final schema = op.success?.schema;
    if (schema == null) return null;
    final flat = resolver.flatten(schema);
    final type = MockFaker.typeOf(flat);
    if (type == 'array') {
      final items = flat['items'];
      return (items: items is Map ? items.cast<String, dynamic>() : const {'type': 'object'}, envelope: null);
    }
    if (type != 'object' || flat['properties'] is! Map) return null;
    final properties = (flat['properties'] as Map).cast<String, dynamic>();
    final arrays = [
      for (final e in properties.entries)
        if (e.value is Map && MockFaker.typeOf(resolver.flatten((e.value as Map).cast<String, dynamic>())) == 'array') e.key,
    ];
    if (arrays.isEmpty) return null;
    String? key;
    for (final preferred in [..._listKeys, name]) {
      if (arrays.contains(preferred)) {
        key = preferred;
        break;
      }
    }
    if (!strict) key ??= arrays.length == 1 ? arrays.single : null;
    if (key == null) return null;
    final payload = resolver.flatten((properties[key] as Map).cast<String, dynamic>());
    final items = payload['items'];
    return (
      items: items is Map ? items.cast<String, dynamic>() : const {'type': 'object'},
      envelope: MockEnvelope(key, {
        for (final e in properties.entries)
          if (e.key != key && e.value is Map) e.key: (e.value as Map).cast<String, dynamic>(),
      }),
    );
  }

  /// The item inside `{"data": {...}}`, or null when the schema is the item itself.
  static ({Map<String, dynamic> schema, MockEnvelope envelope})? _itemPayload(MockSchemaResolver resolver, Map<String, dynamic> schema, String resource) {
    final flat = resolver.flatten(schema);
    if (MockFaker.typeOf(flat) != 'object' || flat['properties'] is! Map) return null;
    final properties = (flat['properties'] as Map).cast<String, dynamic>();
    final singular = resource.endsWith('s') && resource.length > 1 ? resource.substring(0, resource.length - 1) : resource;
    for (final key in [..._itemKeys, singular]) {
      final property = properties[key];
      if (property is! Map) continue;
      final inner = resolver.flatten(property.cast<String, dynamic>());
      if (MockFaker.typeOf(inner) != 'object') continue;
      // A resource whose own field happens to be called `data` is not an envelope: the id would be missing from the wrapper.
      if (properties.length > 1 && properties.containsKey('id')) continue;
      return (
        schema: property.cast<String, dynamic>(),
        envelope: MockEnvelope(key, {
          for (final e in properties.entries)
            if (e.key != key && e.value is Map) e.key: (e.value as Map).cast<String, dynamic>(),
        }),
      );
    }
    return null;
  }
}

/// The in-memory data behind the resource families: seeded with fake items on first use, changed by the calls,
/// emptied back to its seed by [reset].
final class MockStore {
  final MockFaker faker;

  /// Items each collection starts with.
  final int seedCount;

  final _collections = <String, List<Map<String, dynamic>>>{};
  final _created = <String, int>{};

  MockStore({required this.faker, this.seedCount = 10});

  /// The items of the collection at [scope] (a concrete path such as `/users/5/orders`), seeded on first use.
  List<Map<String, dynamic>> items(MockResourceFamily family, String scope) =>
      _collections.putIfAbsent(scope, () => _seed(family, scope));

  Map<String, dynamic>? find(MockResourceFamily family, String scope, String id) {
    for (final item in items(family, scope)) {
      if ('${item[family.idField]}' == id) return item;
    }
    return null;
  }

  /// A new item: fake data, then [body] on top, with an id of its own (a client does not choose it).
  Map<String, dynamic> create(MockResourceFamily family, String scope, Map<String, dynamic> body) {
    final list = items(family, scope);
    final n = _created.update(scope, (c) => c + 1, ifAbsent: () => 1);
    final item = _fake(family, '$scope#new$n', list.length + n);
    final generatedId = item[family.idField];
    item.addAll(body);
    item[family.idField] = family.integerIds ? _nextNumber(family, list) : _stringId(family, generatedId, '$scope#new$n', list);
    list.add(item);
    return item;
  }

  /// The item at [id] replaced by [body] (its id kept), or null when there is none.
  Map<String, dynamic>? replace(MockResourceFamily family, String scope, String id, Map<String, dynamic> body) {
    final list = items(family, scope);
    final at = list.indexWhere((i) => '${i[family.idField]}' == id);
    if (at < 0) return null;
    final id0 = list[at][family.idField];
    // Whatever the schema requires and the body leaves out is filled in, as a real server would answer a full resource.
    final item = _fake(family, '$scope#put$id', at)..addAll(body);
    item[family.idField] = id0;
    list[at] = item;
    return item;
  }

  /// [body] merged into the item at [id], or null when there is none.
  Map<String, dynamic>? merge(MockResourceFamily family, String scope, String id, Map<String, dynamic> body) {
    final item = find(family, scope, id);
    if (item == null) return null;
    final keep = item[family.idField];
    item.addAll(body);
    item[family.idField] = keep;
    return item;
  }

  Map<String, dynamic>? remove(MockResourceFamily family, String scope, String id) {
    final list = items(family, scope);
    final at = list.indexWhere((i) => '${i[family.idField]}' == id);
    return at < 0 ? null : list.removeAt(at);
  }

  /// Forgets every change: the next call seeds each collection again.
  void reset() {
    _collections.clear();
    _created.clear();
  }

  /// How many collections hold data now (for the dialog's "data in memory" line).
  int get collectionCount => _collections.length;

  int get itemCount => _collections.values.fold(0, (sum, list) => sum + list.length);

  List<Map<String, dynamic>> _seed(MockResourceFamily family, String scope) {
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < seedCount; i++) {
      final item = _fake(family, '$scope[$i]', i);
      item[family.idField] = family.integerIds ? i + 1 : _stringId(family, item[family.idField], '$scope#$i', list);
      list.add(item);
    }
    return list;
  }

  Map<String, dynamic> _fake(MockResourceFamily family, String path, int index) {
    final value = faker.generate(family.itemSchema, name: family.name, path: path, index: index);
    return value is Map ? jsonDecode(jsonEncode(value)) as Map<String, dynamic> : <String, dynamic>{};
  }

  /// A text id: what the schema's own fake gives for the id property (so a `pattern` or `format` is respected) when that is a
  /// string no other item has, else a UUID made from [seedText].
  Object _stringId(MockResourceFamily family, Object? generated, String seedText, List<Map<String, dynamic>> existing) {
    if (generated is String && generated.isNotEmpty && !existing.any((e) => e[family.idField] == generated)) return generated;
    return MockFaker.uuidFor(seedText);
  }

  int _nextNumber(MockResourceFamily family, List<Map<String, dynamic>> list) {
    var highest = 0;
    for (final item in list) {
      final v = item[family.idField];
      if (v is num && v > highest) highest = v.toInt();
    }
    return highest + 1;
  }
}
