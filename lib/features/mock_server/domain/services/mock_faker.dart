import 'dart:convert';
import 'dart:math';
import 'mock_pattern.dart';

/// Reads a schema node the way the document says: follows a `$ref` and merges `allOf`. The OpenAPI importer's own
/// resolver does it (see `OpenApiDocumentView`); tests may pass [identity] for a schema without references.
abstract interface class MockSchemaResolver {
  Map<String, dynamic> flatten(Map<String, dynamic> node);

  static const MockSchemaResolver identity = _IdentityResolver();
}

final class _IdentityResolver implements MockSchemaResolver {
  const _IdentityResolver();

  @override
  Map<String, dynamic> flatten(Map<String, dynamic> node) => node;
}

/// Which side of an exchange a fake object is for: a response leaves out `writeOnly` properties (a password), a
/// request leaves out `readOnly` ones (an id the server assigns).
enum MockSide { response, request }

/// Makes believable data from a JSON schema, deterministically: the same seed and the same position in the
/// document always give the same value, whatever else was asked for before.
///
/// An `example`, a `default` or an `enum` always wins. Otherwise the value follows the schema's `format`
/// (email, uuid, date-time, uri...), then the name of the field (`email`, `phone`, `price`, `firstName`,
/// `created_at`...), then the type with its limits (`minimum`, `maxLength`, `pattern`, `minItems`...). Arrays have
/// three items unless the limits say otherwise.
final class MockFaker {
  final int seed;
  final MockSchemaResolver resolver;

  /// Items in an array without limits.
  final int arrayLength;
  static const _maxDepth = 6;

  /// 2026-01-01T00:00:00Z: fake dates are spread over the year after it, so the output never depends on today.
  static final _epoch = DateTime.utc(2026);

  const MockFaker({this.seed = 1, this.resolver = MockSchemaResolver.identity, this.arrayLength = 3});

  /// A value for [schema]. [path] names the position (it seeds the randomness), [name] is the property it sits in,
  /// [index] the position in an array (ids and enums step through it, so a list of three is not three copies).
  Object? generate(
    Map<String, dynamic> schema, {
    String name = '',
    String path = r'$',
    int index = 0,
    MockSide side = MockSide.response,
    int depth = 0,
  }) {
    if (depth > _maxDepth) return null;
    final node = resolver.flatten(schema);
    if (node.containsKey('example')) return _copy(node['example']);
    final examples = node['examples'];
    if (examples is List && examples.isNotEmpty) return _copy(examples.first);
    if (node['default'] != null) return _copy(node['default']);
    if (node.containsKey('const')) return _copy(node['const']);
    final values = node['enum'];
    if (values is List && values.isNotEmpty) {
      // The position inside an array is left out of the hash, so consecutive items step through the enum.
      return _copy(values[(index + _hash(path.replaceFirst(RegExp(r'\[\d+\]$'), ''))) % values.length]);
    }
    for (final key in const ['oneOf', 'anyOf']) {
      final options = node[key];
      if (options is List && options.isNotEmpty && options.first is Map) {
        final first = (options.first as Map).cast<String, dynamic>();
        // `anyOf: [{type: string}, {type: 'null'}]` is a nullable string: take the first that is not null.
        final real = options.whereType<Map>().map((m) => m.cast<String, dynamic>()).firstWhere(
              (m) => resolver.flatten(m)['type'] != 'null',
              orElse: () => first,
            );
        return generate(real, name: name, path: path, index: index, side: side, depth: depth + 1);
      }
    }
    final type = typeOf(node);
    final random = Random(_hash('$seed|$path'));
    switch (type) {
      case 'object':
        return _object(node, path, side, depth, index);
      case 'array':
        return _array(node, name, path, side, depth);
      case 'string':
        return _string(node, name, path, index, random);
      case 'integer':
        return _number(node, name, index, random, integer: true);
      case 'number':
        return _number(node, name, index, random, integer: false);
      case 'boolean':
        return _boolean(name, random);
    }
    return null;
  }

  /// The schema's type; a list of types (`[string, 'null']`) gives the first that is not null, and a schema that
  /// only has `properties` or `items` is an object or an array.
  static String? typeOf(Map<String, dynamic> node) {
    final type = node['type'];
    if (type is List) return type.map((t) => '$t').where((t) => t != 'null').firstOrNull;
    if (type is String) return type;
    if (node['properties'] is Map || node['additionalProperties'] is Map) return 'object';
    if (node['items'] is Map) return 'array';
    return null;
  }

  /// Whether the schema allows null (OpenAPI 3.0 `nullable`, 3.1 `type: [x, null]`).
  static bool isNullable(Map<String, dynamic> node) {
    if (node['nullable'] == true) return true;
    final type = node['type'];
    return type is List && type.contains('null');
  }

  // --- objects and arrays ------------------------------------------------------

  Object? _object(Map<String, dynamic> node, String path, MockSide side, int depth, int index) {
    final properties = node['properties'];
    final required = <String>{...(node['required'] is List ? (node['required'] as List).map((e) => '$e') : const <String>[])};
    final result = <String, dynamic>{};
    if (properties is Map) {
      for (final entry in properties.entries) {
        final key = '${entry.key}';
        if (entry.value is! Map) continue;
        final property = (entry.value as Map).cast<String, dynamic>();
        final flat = resolver.flatten(property);
        if (side == MockSide.response && flat['writeOnly'] == true) continue;
        if (side == MockSide.request && flat['readOnly'] == true) continue;
        final here = '$path.$key';
        // A nullable property that is not required is null now and then, so the client's null handling is exercised.
        if (!required.contains(key) && isNullable(flat) && _hash('$seed|$here|null') % 5 == 0) {
          result[key] = null;
          continue;
        }
        result[key] = generate(property, name: key, path: here, index: index, side: side, depth: depth + 1);
      }
    }
    final extra = node['additionalProperties'];
    if (extra is Map && (properties is! Map || properties.isEmpty)) {
      final valueSchema = extra.cast<String, dynamic>();
      for (var i = 1; i <= 2; i++) {
        result['key$i'] = generate(valueSchema, name: 'value', path: '$path.key$i', index: i - 1, side: side, depth: depth + 1);
      }
    }
    return result;
  }

  Object? _array(Map<String, dynamic> node, String name, String path, MockSide side, int depth) {
    final items = node['items'];
    if (items is! Map) return <dynamic>[];
    final minItems = (node['minItems'] as num?)?.toInt() ?? 0;
    final maxItems = (node['maxItems'] as num?)?.toInt();
    var count = arrayLength;
    if (count < minItems) count = minItems;
    if (maxItems != null && count > maxItems) count = maxItems;
    return [
      for (var i = 0; i < count; i++)
        generate(items.cast<String, dynamic>(), name: _singular(name), path: '$path[$i]', index: i, side: side, depth: depth + 1),
    ];
  }

  // --- strings ---------------------------------------------------------------------

  Object? _string(Map<String, dynamic> node, String name, String path, int index, Random random) {
    final format = '${node['format'] ?? ''}'.toLowerCase();
    final key = _key(name);
    final minLength = (node['minLength'] as num?)?.toInt();
    final maxLength = (node['maxLength'] as num?)?.toInt();
    String? text;

    final pattern = node['pattern'];
    if (pattern is String && format.isEmpty) text = MockPattern.generate(pattern, random);

    text ??= switch (format) {
      'email' => _email(random),
      'uuid' || 'guid' => _uuid(random),
      'date-time' || 'datetime' => _dateTime(random).toIso8601String(),
      'date' => _date(random),
      'time' => _time(random),
      'uri' || 'url' || 'iri' => _url(key, random),
      'hostname' => '${_pick(_words, random)}.example.com',
      'ipv4' => '${10 + random.nextInt(200)}.${random.nextInt(256)}.${random.nextInt(256)}.${1 + random.nextInt(254)}',
      'ipv6' => '2001:db8::${random.nextInt(0xffff).toRadixString(16)}',
      'password' => 'Mock-${random.nextInt(900000) + 100000}',
      'byte' => base64Encode(utf8.encode('mock-${random.nextInt(9999)}')),
      'binary' => '',
      'phone' => _phone(random),
      _ => null,
    };
    text ??= _byName(key, name, index, random);
    text ??= _words2(random);

    if (minLength != null && text.length < minLength) text = text.padRight(minLength, 'x');
    if (maxLength != null && text.length > maxLength) text = text.substring(0, maxLength);
    return text;
  }

  /// A string chosen from what the field is called; null when its name says nothing.
  String? _byName(String key, String name, int index, Random random) {
    bool has(String part) => key.contains(part);
    bool isAny(Iterable<String> parts) => parts.any(has);
    if (_isIdName(name)) return _uuid(random);
    if (has('email') || key == 'mail') return _email(random);
    if (has('uuid') || has('guid')) return _uuid(random);
    if (has('firstname') || has('givenname') || key == 'forename') return _pick(_firstNames, random);
    if (has('lastname') || has('surname') || has('familyname')) return _pick(_lastNames, random);
    if (has('username') || key == 'login' || has('handle') || has('nickname')) {
      return '${_pick(_firstNames, random).toLowerCase()}${10 + random.nextInt(89)}';
    }
    if (has('fullname') || key == 'name' || key == 'customername' || key == 'authorname' || key == 'ownername') {
      return '${_pick(_firstNames, random)} ${_pick(_lastNames, random)}';
    }
    if (has('company') || has('organization') || has('organisation') || key == 'org' || has('employer')) return _pick(_companies, random);
    if (has('filename')) return '${_pick(_words, random)}-${random.nextInt(99)}.pdf';
    if (has('productname') || has('itemname') || key.endsWith('name')) return _titleCase('${_pick(_adjectives, random)} ${_pick(_words, random)}');
    if (isAny(const ['phone', 'mobile', 'telephone', 'fax']) || key == 'tel') return _phone(random);
    if (isAny(const ['url', 'link', 'website', 'homepage', 'avatar', 'image', 'photo', 'picture', 'thumbnail', 'icon', 'logo', 'href'])) {
      return _url(key, random);
    }
    if (_wordsOf(name).lastOrNull == 'at' ||
        isAny(const ['timestamp', 'datetime', 'birthday', 'birthdate', 'dob', 'expires', 'expiry'])) {
      return _dateTime(random).toIso8601String();
    }
    if (key == 'date' || _wordsOf(name).lastOrNull == 'date') return _date(random);
    if (key == 'time') return _time(random);
    if (has('city') || key == 'town') return _pick(_cities, random);
    if (has('country')) return _pick(_countries, random);
    if (has('street') || has('address')) return '${1 + random.nextInt(998)} ${_pick(_streets, random)}';
    if (has('zip') || has('postal') || has('postcode')) return '${10000 + random.nextInt(89999)}';
    if (key == 'state' || has('province') || has('region')) return _pick(_regions, random);
    if (has('currency')) return _pick(const ['USD', 'EUR', 'GBP', 'JPY'], random);
    if (has('language') || key == 'lang' || key == 'locale') return _pick(const ['en', 'de', 'fr', 'es', 'ja'], random);
    if (has('color') || has('colour')) return _pick(const ['red', 'green', 'blue', 'orange', 'purple', 'teal'], random);
    if (has('slug')) return '${_pick(_adjectives, random)}-${_pick(_words, random)}-${random.nextInt(99)}';
    if (has('password') || has('secret') || has('token') || has('apikey')) return 'mock-${_hex(random, 16)}';
    if (has('sku') || has('code') || has('reference') || key == 'ref' || has('number') && !has('phone')) {
      return '${_pick(const ['AB', 'CD', 'EF', 'XY'], random)}-${1000 + random.nextInt(8999)}';
    }
    if (key == 'status' || key == 'state') return _pick(const ['active', 'pending', 'done'], random);
    if (key == 'type' || key == 'kind' || key == 'category' || key == 'role') {
      return _pick(const ['standard', 'premium', 'basic'], random);
    }
    if (isAny(const ['title', 'subject', 'headline'])) return _titleCase(_words3(random));
    if (isAny(const ['description', 'summary', 'bio', 'about', 'comment', 'message', 'body', 'content', 'text', 'note', 'detail', 'reason'])) {
      return _sentence(random);
    }
    return null;
  }

  // --- numbers and booleans -----------------------------------------------------------

  Object _number(Map<String, dynamic> node, String name, int index, Random random, {required bool integer}) {
    final key = _key(name);
    final minimum = (node['minimum'] as num?)?.toDouble();
    final maximum = (node['maximum'] as num?)?.toDouble();
    final exclusiveMin = node['exclusiveMinimum'];
    final exclusiveMax = node['exclusiveMaximum'];
    var low = minimum ?? (exclusiveMin is num ? exclusiveMin.toDouble() + (integer ? 1 : 0.01) : null);
    var high = maximum ?? (exclusiveMax is num ? exclusiveMax.toDouble() - (integer ? 1 : 0.01) : null);

    bool has(String part) => key.contains(part);
    // What the name suggests, when the schema does not limit it.
    double? suggestedLow;
    double? suggestedHigh;
    var decimals = integer ? 0 : 2;
    var step = false;
    if (_isIdName(name)) {
      suggestedLow = 1;
      suggestedHigh = 9999;
      step = true;
    } else if (has('price') || has('amount') || has('cost') || has('total') && !integer || has('balance') || has('fee') || has('salary') || has('revenue')) {
      suggestedLow = 1;
      suggestedHigh = 999;
    } else if (_wordsOf(name).contains('age')) {
      suggestedLow = 18;
      suggestedHigh = 80;
    } else if (has('quantity') || key == 'qty' || has('stock') || has('count') || has('total')) {
      suggestedLow = 1;
      suggestedHigh = 20;
    } else if (has('year')) {
      suggestedLow = 1990;
      suggestedHigh = 2026;
    } else if (has('rating') || has('score')) {
      suggestedLow = 1;
      suggestedHigh = 5;
      decimals = integer ? 0 : 1;
    } else if (has('latitude') || key == 'lat') {
      suggestedLow = -90;
      suggestedHigh = 90;
      decimals = 5;
    } else if (has('longitude') || key == 'lng' || key == 'lon' || key == 'long') {
      suggestedLow = -180;
      suggestedHigh = 180;
      decimals = 5;
    } else if (has('percent') || has('ratio') || key.endsWith('rate')) {
      suggestedLow = 0;
      suggestedHigh = 100;
    } else if (key == 'page' || key == 'pagenumber') {
      suggestedLow = 1;
      suggestedHigh = 1;
    } else if (key == 'limit' || has('pagesize') || has('perpage') || key == 'size') {
      suggestedLow = 10;
      suggestedHigh = 10;
    } else if (has('width') || has('height')) {
      suggestedLow = 100;
      suggestedHigh = 1000;
    } else if (has('weight')) {
      suggestedLow = 1;
      suggestedHigh = 100;
    } else if (integer && (_wordsOf(name).lastOrNull == 'at' || has('timestamp') || key == 'time')) {
      suggestedLow = _epoch.millisecondsSinceEpoch / 1000;
      suggestedHigh = _epoch.millisecondsSinceEpoch / 1000 + 365 * 86400;
    }
    low ??= suggestedLow ?? 0;
    high ??= suggestedHigh ?? (low < 1000 ? 1000 : low + 1000);
    if (high < low) high = low;

    double value;
    if (step && minimum == null && maximum == null) {
      // An id in a list counts up: 1, 2, 3.
      value = (index + 1).toDouble();
    } else {
      value = low + random.nextDouble() * (high - low);
    }
    final multipleOf = node['multipleOf'];
    if (multipleOf is num && multipleOf > 0) {
      value = (value / multipleOf).round() * multipleOf.toDouble();
      if (value < low) value += multipleOf;
      if (value > high) value -= multipleOf;
    } else if (integer) {
      value = value.roundToDouble();
    } else {
      final factor = pow(10, decimals).toDouble();
      value = (value * factor).round() / factor;
    }
    if (value < low) value = low;
    if (value > high) value = high;
    return integer ? value.round() : value;
  }

  bool _boolean(String name, Random random) {
    final key = _key(name);
    if (key == 'success' || key == 'ok' || key.contains('active') || key.contains('enabled') || key.contains('verified') || key == 'available') return true;
    if (key == 'error' || key.contains('failed') || key.contains('deleted') || key.contains('archived') || key.contains('banned') || key.contains('blocked')) {
      return false;
    }
    return random.nextBool();
  }

  // --- building blocks -------------------------------------------------------------------

  static String _key(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// The words of a name: `createdAt`, `created_at` and `created-at` are all `created`, `at`.
  static List<String> _wordsOf(String name) => name
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.toLowerCase())
      .toList();

  /// `id`, `userId`, `user_id`, `ID`: a name whose last word is `id`.
  static bool _isIdName(String name) => _wordsOf(name).lastOrNull == 'id';

  static String _singular(String name) {
    if (name.endsWith('ies') && name.length > 4) return '${name.substring(0, name.length - 3)}y';
    if (name.endsWith('s') && !name.endsWith('ss') && name.length > 2) return name.substring(0, name.length - 1);
    return name;
  }

  /// A hash of [text] that is the same on every run and platform (`String.hashCode` is neither).
  static int _hash(String text) {
    var h = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  static String _pick(List<String> values, Random random) => values[random.nextInt(values.length)];

  static String _hex(Random random, int length) => List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();

  static String _uuid(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int from, int to) => bytes.sublist(from, to).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  /// A UUID for [text]: the same text gives the same one. The store uses it for the ids of string-keyed resources.
  static String uuidFor(String text) => _uuid(Random(_hash(text)));

  static String _email(Random random) =>
      '${_pick(_firstNames, random).toLowerCase()}.${_pick(_lastNames, random).toLowerCase()}@example.com';

  static String _phone(Random random) => '+1-555-${(random.nextInt(9000) + 1000)}';

  static String _url(String key, Random random) {
    final slug = '${_pick(_words, random)}-${random.nextInt(999)}';
    if (key.contains('avatar') || key.contains('image') || key.contains('photo') || key.contains('picture') || key.contains('thumbnail')) {
      return 'https://example.com/images/$slug.jpg';
    }
    return 'https://example.com/$slug';
  }

  static DateTime _dateTime(Random random) => _epoch.add(Duration(seconds: random.nextInt(365 * 86400)));

  static String _date(Random random) => _dateTime(random).toIso8601String().substring(0, 10);

  static String _time(Random random) =>
      '${random.nextInt(24).toString().padLeft(2, '0')}:${random.nextInt(60).toString().padLeft(2, '0')}:${random.nextInt(60).toString().padLeft(2, '0')}';

  static String _titleCase(String text) =>
      text.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  static String _words2(Random random) => '${_pick(_adjectives, random)} ${_pick(_words, random)}';

  static String _words3(Random random) => '${_pick(_adjectives, random)} ${_pick(_words, random)} ${_pick(_words, random)}';

  static String _sentence(Random random) =>
      '${_titleCase(_pick(_adjectives, random))} ${_pick(_words, random)} for the ${_pick(_words, random)} ${_pick(_words, random)}.';

  static Object? _copy(Object? value) => value is Map || value is List ? jsonDecode(jsonEncode(value)) : value;

  static const _firstNames = ['Ann', 'Bob', 'Carla', 'Dev', 'Elena', 'Femi', 'Greta', 'Hugo', 'Iris', 'Jon', 'Kai', 'Lena'];
  static const _lastNames = ['Larsen', 'Okafor', 'Silva', 'Nguyen', 'Khan', 'Rossi', 'Novak', 'Haddad', 'Berg', 'Tanaka'];
  static const _companies = ['Acme Corp', 'Globex', 'Initech', 'Umbrella Ltd', 'Hooli', 'Stark Industries', 'Wayne Works'];
  static const _cities = ['Oslo', 'Lagos', 'Lisbon', 'Hanoi', 'Karachi', 'Turin', 'Brno', 'Cairo', 'Osaka', 'Austin'];
  static const _countries = ['Norway', 'Nigeria', 'Portugal', 'Vietnam', 'Pakistan', 'Italy', 'Czechia', 'Egypt', 'Japan', 'USA'];
  static const _streets = ['Main Street', 'Park Avenue', 'Mill Road', 'Harbour Lane', 'Station Road', 'Elm Street'];
  static const _regions = ['Texas', 'Bavaria', 'Tuscany', 'Osaka', 'Lagos', 'Ontario'];
  static const _adjectives = ['great', 'small', 'quick', 'quiet', 'bright', 'solid', 'fresh', 'handy', 'smart', 'plain'];
  static const _words = ['river', 'lamp', 'garden', 'engine', 'pillow', 'planet', 'basket', 'window', 'ticket', 'signal', 'market', 'harbor'];
}
