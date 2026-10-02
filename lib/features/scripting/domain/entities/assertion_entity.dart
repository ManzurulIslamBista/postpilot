enum AssertionType {
  statusEquals,
  statusIn2xx,
  bodyContains,
  jsonPathEquals,
  jsonPathExists,
  headerEquals,
  headerExists,
  responseTimeBelowMs,
  jsonSchema;

  String get label => switch (this) {
        AssertionType.statusEquals => 'Status equals',
        AssertionType.statusIn2xx => 'Status is 2xx',
        AssertionType.bodyContains => 'Body contains',
        AssertionType.jsonPathEquals => 'JSON path equals',
        AssertionType.jsonPathExists => 'JSON path exists',
        AssertionType.headerEquals => 'Header equals',
        AssertionType.headerExists => 'Header exists',
        AssertionType.responseTimeBelowMs => 'Response time below',
        AssertionType.jsonSchema => 'Matches JSON Schema',
      };

  bool get isHeader => this == AssertionType.headerEquals || this == AssertionType.headerExists;

  /// The expected value is a whole JSON Schema document, not a short value.
  bool get isSchema => this == AssertionType.jsonSchema;

  /// Whether [AssertionEntity.path] (a JSON path or header name) applies.
  bool get usesPath => switch (this) {
        AssertionType.jsonPathEquals ||
        AssertionType.jsonPathExists ||
        AssertionType.headerEquals ||
        AssertionType.headerExists ||
        AssertionType.jsonSchema =>
          true,
        _ => false,
      };

  bool get usesExpected => switch (this) {
        AssertionType.statusIn2xx || AssertionType.jsonPathExists || AssertionType.headerExists => false,
        _ => true,
      };
}

/// One declarative check on a response — PostPilot's stand-in for a
/// `pm.test` block, since scripts can't run on web. [id] is session-only,
/// purely so editor rows keep a stable `ValueKey` (same reason as
/// `KeyValueItem.id`).
final class AssertionEntity {
  static int _nextId = 0;

  final int id;
  final AssertionType type;

  /// JSON path (`data.items[0].id`) or header name, depending on [type].
  final String path;
  final String expected;

  AssertionEntity({int? id, required this.type, this.path = '', this.expected = ''}) : id = id ?? _nextId++;

  AssertionEntity copyWith({AssertionType? type, String? path, String? expected}) => AssertionEntity(
        id: id,
        type: type ?? this.type,
        path: path ?? this.path,
        expected: expected ?? this.expected,
      );

  String get name => switch (type) {
        AssertionType.statusEquals => 'Status equals $expected',
        AssertionType.statusIn2xx => 'Status is 2xx',
        AssertionType.bodyContains => 'Body contains "$expected"',
        AssertionType.jsonPathEquals => '$path equals $expected',
        AssertionType.jsonPathExists => '$path exists',
        AssertionType.headerEquals => 'Header $path equals $expected',
        AssertionType.headerExists => 'Header $path exists',
        AssertionType.responseTimeBelowMs => 'Response time below $expected ms',
        AssertionType.jsonSchema => path.trim().isEmpty ? 'Body matches the JSON Schema' : '$path matches the JSON Schema',
      };
}
