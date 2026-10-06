import '../../../request_builder/domain/entities/request_auth.dart';
import '../entities/defaults_chain.dart';
import '../entities/defaults_origin.dart';
import '../entities/inherited_defaults.dart';
import 'header_inheritance.dart';

/// Turns the levels a request sits under into what it inherits. Pure and
/// synchronous, so the app, the CLI and the exports cannot disagree.
///
/// Headers, auth, variables and tests, outermost level first (the collection,
/// then each folder from the top one down):
///  * Headers: see [HeaderInheritance].
///  * Auth: the nearest folder that sets one wins, else the collection's. A
///    folder's "Inherit from parent" is a folder that sets none; its explicit
///    "No Auth" is a setting, and ends the search.
///  * Variables: the innermost folder wins; a disabled variable is not visible
///    (as with the collection's), so it does not hide one a folder above sets.
///    Where they rank among the other scopes is `BuildVariableResolverUseCase`'s
///    business: environment, then folders, then the collection, then globals.
///  * Tests: every level's, collection first, all run before the request's own.
abstract final class DefaultsResolver {
  static InheritedDefaults resolve(DefaultsChain chain) {
    final scopes = chain.scopes;

    final merged = HeaderInheritance.mergeWithLevels([for (final s in scopes) s.defaults.headers]);
    final headers = [for (final row in merged) InheritedHeader(row.item, scopes[row.level].origin)];

    RequestAuth? auth;
    DefaultsOrigin? authOrigin;
    for (final scope in scopes.reversed) {
      final candidate = scope.defaults.auth;
      if (candidate == null) continue;
      auth = candidate;
      authOrigin = scope.origin;
      break;
    }

    final folders = scopes.where((s) => s.origin.isFolder).toList();
    final variableScopes = [
      for (final scope in folders.reversed)
        {
          for (final v in scope.defaults.variables)
            if (v.enabled && v.key.isNotEmpty) v.key: v.value,
        },
    ];
    final variables = [
      for (final scope in folders)
        for (final v in scope.defaults.variables)
          if (v.enabled && v.key.isNotEmpty) InheritedVariable(v, scope.origin),
    ];

    final tests = [
      for (final scope in scopes)
        if (scope.defaults.hasTests) InheritedTests(scope.origin, scope.defaults.assertions, scope.defaults.extractors),
    ];

    return InheritedDefaults(
      chain: chain,
      headers: headers,
      auth: auth,
      authOrigin: authOrigin,
      variableScopes: variableScopes,
      variables: variables,
      tests: tests,
    );
  }
}
