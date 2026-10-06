import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
import 'default_variable.dart';
import 'defaults_chain.dart';
import 'defaults_origin.dart';

/// An inherited header and the level that set it.
final class InheritedHeader {
  final KeyValueItem item;
  final DefaultsOrigin origin;
  const InheritedHeader(this.item, this.origin);
}

/// A folder variable and the folder that holds it.
final class InheritedVariable {
  final DefaultVariable variable;
  final DefaultsOrigin origin;
  const InheritedVariable(this.variable, this.origin);
}

/// The tests one level adds to every request below it.
final class InheritedTests {
  final DefaultsOrigin origin;
  final List<AssertionEntity> assertions;
  final List<ExtractorEntity> extractors;
  const InheritedTests(this.origin, this.assertions, this.extractors);
}

/// What a request gets from the collection and its folders, already resolved
/// with the inheritance rules (see `DefaultsResolver`).
final class InheritedDefaults {
  final DefaultsChain chain;

  /// The headers that are sent, outermost level first: enabled rows whose name
  /// no more specific level has taken over or switched off. The request's own
  /// headers are applied on top by the request builder.
  final List<InheritedHeader> headers;

  /// The auth a request set to "Inherit from parent" gets from the nearest
  /// folder that sets one, else the collection; null when nothing sets any.
  final RequestAuth? auth;
  final DefaultsOrigin? authOrigin;

  /// Enabled folder variables, one map per folder, innermost folder first (the
  /// order the resolver layers them in).
  final List<Map<String, String>> variableScopes;

  /// Every enabled folder variable with its folder, outermost first, for lists
  /// and hover cards. A name an inner folder redefines appears for each.
  final List<InheritedVariable> variables;

  /// The tests of each level that has any, collection first, then the folders
  /// from the outermost down. They run before the request's own.
  final List<InheritedTests> tests;

  const InheritedDefaults({
    required this.chain,
    this.headers = const [],
    this.auth,
    this.authOrigin,
    this.variableScopes = const [],
    this.variables = const [],
    this.tests = const [],
  });

  static const none = InheritedDefaults(chain: DefaultsChain.empty);

  /// The inherited headers as plain rows, for [RequestSpecBuilder.build].
  List<KeyValueItem> get headerRows => [for (final h in headers) h.item];

  bool get hasTests => tests.isNotEmpty;
}
