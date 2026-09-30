import '../../../../core/constants/app_constants.dart';

enum ExtractorSource {
  jsonPath,
  header;

  String get label => switch (this) {
        ExtractorSource.jsonPath => 'JSON path',
        ExtractorSource.header => 'Header',
      };
}

enum ExtractorScope {
  environment,
  global;

  String get label => switch (this) {
        ExtractorScope.environment => 'Environment',
        ExtractorScope.global => 'Global',
      };
}

/// Copies one value out of a response into a variable so the next request
/// can reference `{{variableKey}}` — Postman's `pm.environment.set(...)`.
/// [id] is session-only, for stable editor row keys.
final class ExtractorEntity {
  static int _nextId = 0;

  final int id;
  final ExtractorSource source;

  /// JSON path or header name, depending on [source].
  final String path;
  final ExtractorScope scope;
  final String variableKey;

  ExtractorEntity({
    int? id,
    this.source = ExtractorSource.jsonPath,
    this.path = '',
    this.scope = ExtractorScope.environment,
    this.variableKey = '',
  }) : id = id ?? _nextId++;

  /// Why [variableKey] can't be saved, or `null` when it can. The resolver only
  /// substitutes names its own `{{name}}` pattern matches whole, so any other
  /// name would be saved and reported OK yet never be referenceable.
  String? get keyError {
    final key = variableKey.trim();
    if (key.isEmpty) return 'No variable name';
    final token = '{{$key}}';
    final referenceable = AppConstants.variablePattern.matchAsPrefix(token)?.end == token.length;
    return referenceable ? null : r'Use letters, digits, _ - . or $ only';
  }

  /// Why [path] can't be read, or `null` when it can. A blank JSON path would
  /// resolve to the whole body, which an unfinished row never means.
  String? get pathError => path.trim().isNotEmpty
      ? null
      : switch (source) {
          ExtractorSource.jsonPath => 'Enter a JSON path',
          ExtractorSource.header => 'Enter a header name',
        };

  ExtractorEntity copyWith({ExtractorSource? source, String? path, ExtractorScope? scope, String? variableKey}) =>
      ExtractorEntity(
        id: id,
        source: source ?? this.source,
        path: path ?? this.path,
        scope: scope ?? this.scope,
        variableKey: variableKey ?? this.variableKey,
      );
}
