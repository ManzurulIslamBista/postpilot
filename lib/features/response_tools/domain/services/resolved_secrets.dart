import '../../../../core/utils/variable_resolver.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/services/secret_names.dart';

/// Credentials that only exist once a request's `{{variables}}` are resolved.
///
/// A report or an AI prompt built from the request as the sender builds it holds
/// the real values. [SecretMasker] hides what a header, query or JSON key name
/// gives away, but a secret variable placed in a header called `X-Customer-Ref`
/// or in a body field called `ref` looks like data once it is text. So the values
/// of the variables that are secret are also masked wherever they appear.
abstract final class ResolvedSecrets {
  /// Values shorter than this, and the words below, are not hidden: they would
  /// blank out ordinary text (`true` in a body) for no gain.
  static const _minLength = 6;
  static const _plainWords = {'true', 'false', 'null', 'none'};

  /// The resolved values of the variables in [resolver] that are secret: those in
  /// [flaggedKeys] (marked secret in an environment or the globals) and those
  /// whose names say so (`apiKey`, `db_password`). Longest first, so a value that
  /// contains another is hidden whole.
  static List<String> valuesOf(VariableResolver resolver, {Set<String> flaggedKeys = const {}}) {
    final values = <String>{};
    for (final scope in resolver.scopes) {
      for (final key in scope.keys) {
        if (!flaggedKeys.contains(key) && !SecretNames.looksSecretKey(key)) continue;
        final value = resolver.resolve('{{$key}}');
        if (value.length < _minLength || value.contains('{{') || _plainWords.contains(value.toLowerCase())) continue;
        values.add(value);
      }
    }
    return values.toList()..sort((a, b) => b.length.compareTo(a.length));
  }

  /// [text] with every one of [values] replaced by the mask.
  static String mask(String text, List<String> values) {
    var masked = text;
    for (final value in values) {
      masked = masked.replaceAll(value, SecretMasker.mask);
    }
    return masked;
  }
}
