import 'dart:convert';

/// The standard introspection query: everything a schema explorer needs.
const graphqlIntrospectionQuery = r'''
query IntrospectionQuery {
  __schema {
    queryType { name }
    mutationType { name }
    subscriptionType { name }
    types {
      kind name description
      fields(includeDeprecated: true) {
        name description isDeprecated deprecationReason
        args { name description defaultValue type { ...TypeRef } }
        type { ...TypeRef }
      }
      inputFields { name description defaultValue type { ...TypeRef } }
      interfaces { ...TypeRef }
      enumValues(includeDeprecated: true) { name description isDeprecated }
      possibleTypes { ...TypeRef }
    }
  }
}
fragment TypeRef on __Type {
  kind name
  ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } }
}
''';

/// A reference to a type with its wrappers: `[User!]!` is NON_NULL(LIST(NON_NULL(User))).
final class GqlTypeRef {
  final String kind;
  final String? name;
  final GqlTypeRef? ofType;
  const GqlTypeRef(this.kind, this.name, this.ofType);

  factory GqlTypeRef.fromJson(Map<String, dynamic> json) => GqlTypeRef(
        '${json['kind']}',
        json['name'] as String?,
        json['ofType'] is Map<String, dynamic> ? GqlTypeRef.fromJson(json['ofType'] as Map<String, dynamic>) : null,
      );

  /// The type with every NON_NULL / LIST wrapper removed.
  String get namedType => name ?? ofType?.namedType ?? '';

  bool get isNonNull => kind == 'NON_NULL';
  bool get isList => kind == 'LIST' || (isNonNull && (ofType?.isList ?? false));

  @override
  String toString() => switch (kind) {
        'NON_NULL' => '${ofType ?? ''}!',
        'LIST' => '[${ofType ?? ''}]',
        _ => name ?? '',
      };
}

final class GqlArgument {
  final String name;
  final String description;
  final String? defaultValue;
  final GqlTypeRef type;
  const GqlArgument(this.name, this.description, this.defaultValue, this.type);

  bool get isRequired => type.isNonNull && defaultValue == null;
}

final class GqlField {
  final String name;
  final String description;
  final bool isDeprecated;
  final List<GqlArgument> args;
  final GqlTypeRef type;
  const GqlField(this.name, this.description, this.isDeprecated, this.args, this.type);
}

final class GqlEnumValue {
  final String name;
  final String description;
  final bool isDeprecated;
  const GqlEnumValue(this.name, this.description, this.isDeprecated);
}

final class GqlType {
  final String kind;
  final String name;
  final String description;
  final List<GqlField> fields;
  final List<GqlArgument> inputFields;
  final List<GqlEnumValue> enumValues;
  final List<String> interfaces;
  final List<String> possibleTypes;

  const GqlType({
    required this.kind,
    required this.name,
    this.description = '',
    this.fields = const [],
    this.inputFields = const [],
    this.enumValues = const [],
    this.interfaces = const [],
    this.possibleTypes = const [],
  });

  bool get isScalarLike => kind == 'SCALAR' || kind == 'ENUM';
  bool get isComposite => kind == 'OBJECT' || kind == 'INTERFACE' || kind == 'UNION';
}

final class GqlSchema {
  final String? queryType;
  final String? mutationType;
  final String? subscriptionType;
  final Map<String, GqlType> types;

  const GqlSchema({this.queryType, this.mutationType, this.subscriptionType, required this.types});

  GqlType? type(String name) => types[name];

  /// The fields of the root type for [operation] (`query`, `mutation`, `subscription`).
  List<GqlField> rootFields(String operation) {
    final name = switch (operation) {
      'mutation' => mutationType,
      'subscription' => subscriptionType,
      _ => queryType,
    };
    return name == null ? const [] : (types[name]?.fields ?? const []);
  }

  /// Types a person would browse: no `__Schema`-style internals, no built-in scalars.
  List<GqlType> get userTypes {
    const builtIn = {'String', 'Int', 'Float', 'Boolean', 'ID'};
    final list = [
      for (final t in types.values)
        if (!t.name.startsWith('__') && !builtIn.contains(t.name)) t,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Reads an introspection response: `{"data": {"__schema": ...}}`, or just the `__schema` object.
  /// Returns null when [text] is not one.
  static GqlSchema? parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    final data = json['data'] is Map<String, dynamic> ? json['data'] as Map<String, dynamic> : json;
    final schema = data['__schema'] is Map<String, dynamic> ? data['__schema'] as Map<String, dynamic> : null;
    if (schema == null || schema['types'] is! List) return null;

    String? root(String key) => (schema[key] is Map ? (schema[key] as Map)['name'] : null) as String?;
    final types = <String, GqlType>{};
    for (final raw in (schema['types'] as List).whereType<Map<String, dynamic>>()) {
      final name = raw['name'] as String?;
      if (name == null) continue;
      types[name] = GqlType(
        kind: '${raw['kind']}',
        name: name,
        description: (raw['description'] as String?) ?? '',
        fields: [for (final f in _maps(raw['fields'])) _field(f)],
        inputFields: [for (final f in _maps(raw['inputFields'])) _arg(f)],
        enumValues: [
          for (final e in _maps(raw['enumValues']))
            GqlEnumValue('${e['name']}', (e['description'] as String?) ?? '', e['isDeprecated'] == true),
        ],
        interfaces: [for (final i in _maps(raw['interfaces'])) GqlTypeRef.fromJson(i).namedType],
        possibleTypes: [for (final i in _maps(raw['possibleTypes'])) GqlTypeRef.fromJson(i).namedType],
      );
    }
    return GqlSchema(queryType: root('queryType'), mutationType: root('mutationType'), subscriptionType: root('subscriptionType'), types: types);
  }

  static Iterable<Map<String, dynamic>> _maps(Object? v) => v is List ? v.whereType<Map<String, dynamic>>() : const [];

  static GqlArgument _arg(Map<String, dynamic> j) => GqlArgument(
        '${j['name']}',
        (j['description'] as String?) ?? '',
        j['defaultValue'] as String?,
        GqlTypeRef.fromJson(j['type'] as Map<String, dynamic>),
      );

  static GqlField _field(Map<String, dynamic> j) => GqlField(
        '${j['name']}',
        (j['description'] as String?) ?? '',
        j['isDeprecated'] == true,
        [for (final a in _maps(j['args'])) _arg(a)],
        GqlTypeRef.fromJson(j['type'] as Map<String, dynamic>),
      );
}
