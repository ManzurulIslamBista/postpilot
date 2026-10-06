import 'dart:convert';

/// What a baseline remembers about one path of the body: the JSON types seen there and whether it was missing
/// from some of the places it could have been.
final class BaselineField {
  /// `integer`, `number`, `string`, `boolean`, `object`, `array`, `null`.
  final Set<String> types;

  /// Present in some elements (or objects) and absent in others.
  final bool optional;

  const BaselineField(this.types, {this.optional = false});

  bool get nullable => types.contains('null');

  @override
  bool operator ==(Object other) =>
      other is BaselineField && other.optional == optional && other.types.length == types.length && other.types.containsAll(types);

  @override
  int get hashCode => Object.hash(optional, Object.hashAllUnordered(types));
}

/// The small set of values a field was seen to take, and over how many values it was seen.
final class BaselineEnum {
  final List<Object> values;
  final int instances;
  const BaselineEnum(this.values, this.instances);

  @override
  bool operator ==(Object other) =>
      other is BaselineEnum && other.instances == instances && jsonEncode(other.values) == jsonEncode(values);

  @override
  int get hashCode => Object.hash(instances, jsonEncode(values));
}

/// The recorded "known good" shape of a request's response, which later responses are compared with
/// (`DriftDetector`). It is a snapshot of structure, not of the whole body: paths with their types, a few
/// headers, the values that do not change by themselves and a speed. Stored as JSON in the `RequestBaselines`
/// table of this device.
///
/// Paths are column paths (`items[].id`, see `FieldPath`): the elements of an array are described together.
final class BaselineSnapshot {
  static const currentVersion = 1;

  final int status;

  /// Selected headers, lower-case name to the part of the value that matters: the media type of `Content-Type`,
  /// the directives of `Cache-Control`, `present` for headers whose value is different every time.
  final Map<String, String> headers;

  /// The body was JSON; when it was not, [fields], [enums] and [values] are empty.
  final bool isJson;
  final Map<String, BaselineField> fields;
  final Map<String, BaselineEnum> enums;

  /// Scalar values outside arrays that did not look like ids, timestamps, tokens or counters.
  final Map<String, Object> values;

  /// Paths a second response showed to change by themselves; their values are never compared.
  final Set<String> volatile;

  /// How long the response took.
  final int timeMs;

  /// The body was too large to describe in full.
  final bool shapeTruncated;

  const BaselineSnapshot({
    required this.status,
    this.headers = const {},
    this.isJson = false,
    this.fields = const {},
    this.enums = const {},
    this.values = const {},
    this.volatile = const {},
    this.timeMs = 0,
    this.shapeTruncated = false,
  });

  BaselineSnapshot copyWith({
    int? status,
    Map<String, String>? headers,
    bool? isJson,
    Map<String, BaselineField>? fields,
    Map<String, BaselineEnum>? enums,
    Map<String, Object>? values,
    Set<String>? volatile,
    int? timeMs,
    bool? shapeTruncated,
  }) =>
      BaselineSnapshot(
        status: status ?? this.status,
        headers: headers ?? this.headers,
        isJson: isJson ?? this.isJson,
        fields: fields ?? this.fields,
        enums: enums ?? this.enums,
        values: values ?? this.values,
        volatile: volatile ?? this.volatile,
        timeMs: timeMs ?? this.timeMs,
        shapeTruncated: shapeTruncated ?? this.shapeTruncated,
      );

  // --- storage -------------------------------------------------------------------

  Map<String, Object?> toJson() => {
        'v': currentVersion,
        'status': status,
        if (headers.isNotEmpty) 'headers': headers,
        'json': isJson,
        if (fields.isNotEmpty)
          'fields': {
            for (final e in fields.entries)
              e.key: {
                't': (e.value.types.toList()..sort()),
                if (e.value.optional) 'o': true,
              },
          },
        if (enums.isNotEmpty)
          'enums': {for (final e in enums.entries) e.key: {'values': e.value.values, 'n': e.value.instances}},
        if (values.isNotEmpty) 'values': values,
        if (volatile.isNotEmpty) 'volatile': (volatile.toList()..sort()),
        'timeMs': timeMs,
        if (shapeTruncated) 'truncated': true,
      };

  String encode() => jsonEncode(toJson());

  /// Reads a stored snapshot. A missing or wrongly typed part falls back to empty, so a snapshot written by an
  /// older or newer build never stops the app; null when [source] is not a JSON object at all.
  static BaselineSnapshot? decode(String source) {
    try {
      return fromJson(jsonDecode(source));
    } on FormatException {
      return null;
    }
  }

  static BaselineSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    Map<String, dynamic> map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
    final fields = <String, BaselineField>{};
    for (final e in map(json['fields']).entries) {
      final entry = map(e.value);
      final types = entry['t'];
      fields[e.key] = BaselineField(
        {if (types is List) ...types.whereType<String>()},
        optional: entry['o'] == true,
      );
    }
    final enums = <String, BaselineEnum>{};
    for (final e in map(json['enums']).entries) {
      final entry = map(e.value);
      final values = entry['values'];
      if (values is! List) continue;
      final n = entry['n'];
      enums[e.key] = BaselineEnum([for (final v in values) if (v is String || v is int) v as Object], n is int ? n : 0);
    }
    final values = <String, Object>{};
    for (final e in map(json['values']).entries) {
      final v = e.value;
      if (v is String || v is num || v is bool) values[e.key] = v as Object;
    }
    final headers = <String, String>{
      for (final e in map(json['headers']).entries)
        if (e.value is String) e.key: e.value as String,
    };
    final volatile = json['volatile'];
    final status = json['status'];
    final time = json['timeMs'];
    return BaselineSnapshot(
      status: status is int ? status : 0,
      headers: headers,
      isJson: json['json'] == true,
      fields: fields,
      enums: enums,
      values: values,
      volatile: {if (volatile is List) ...volatile.whereType<String>()},
      timeMs: time is int ? time : 0,
      shapeTruncated: json['truncated'] == true,
    );
  }

  /// A short description for the panel: `200 · 14 fields · recorded from a JSON body`.
  String get summary {
    final count = fields.isEmpty ? 0 : fields.length - 1;
    final parts = ['status $status', if (isJson) '$count ${count == 1 ? 'field' : 'fields'}' else 'not JSON', '$timeMs ms'];
    return parts.join(' · ');
  }
}
