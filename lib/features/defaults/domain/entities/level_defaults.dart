import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
import 'default_variable.dart';

/// What one level of the tree (the collection, or one folder) passes down to
/// every request below it.
///
/// A level that sets nothing is [empty]; the stores keep no row for it. The
/// collection keeps its [variables] (`collection_variables`) and its [auth]
/// (`collection_auth`) in tables of their own, so those two are filled in when
/// a whole tree is read but are not written by `DefaultsRepository.saveCollection`.
final class LevelDefaults {
  final List<KeyValueItem> headers;

  /// Folder variables. A collection's variables live in `collection_variables`.
  final List<DefaultVariable> variables;

  /// The auth requests below inherit, or null when this level sets none. On a
  /// folder null is "Inherit from parent"; an explicit [AuthType.none] there
  /// switches the inherited auth off for everything below.
  final RequestAuth? auth;

  /// Tests that run for every request below, before the request's own.
  final List<AssertionEntity> assertions;
  final List<ExtractorEntity> extractors;

  const LevelDefaults({
    this.headers = const [],
    this.variables = const [],
    this.auth,
    this.assertions = const [],
    this.extractors = const [],
  });

  static const empty = LevelDefaults();

  bool get isEmpty =>
      headers.isEmpty && variables.isEmpty && auth == null && assertions.isEmpty && extractors.isEmpty;

  bool get hasTests => assertions.isNotEmpty || extractors.isNotEmpty;

  LevelDefaults copyWith({
    List<KeyValueItem>? headers,
    List<DefaultVariable>? variables,
    List<AssertionEntity>? assertions,
    List<ExtractorEntity>? extractors,
  }) =>
      LevelDefaults(
        headers: headers ?? this.headers,
        variables: variables ?? this.variables,
        auth: auth,
        assertions: assertions ?? this.assertions,
        extractors: extractors ?? this.extractors,
      );

  /// [auth] may be null here, which [copyWith] cannot express.
  LevelDefaults withAuth(RequestAuth? auth) => LevelDefaults(
        headers: headers,
        variables: variables,
        auth: auth,
        assertions: assertions,
        extractors: extractors,
      );
}
