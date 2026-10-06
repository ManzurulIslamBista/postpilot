// Pure Dart.
import '../entities/ci_options.dart';

/// The secrets a CI setup needs, worked out from the names of the secret variables only.
final class CiSecretMapping {
  final List<CiSecret> secrets;

  /// Variables that cannot become an environment variable (a name with a space, say), with the reason.
  final List<String> skipped;

  const CiSecretMapping(this.secrets, this.skipped);
}

/// Turns variable names (`odooApiKey`, `db.password`) into the names of CI secrets (`ODOO_API_KEY`, `DB_PASSWORD`).
/// GitHub secret names may hold only letters, digits and underscores, cannot start with a digit or with `GITHUB_`,
/// and are not case sensitive, so two variables that map to one name get a number.
abstract final class CiSecretMapper {
  static final _word = RegExp(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+');
  static final _usable = RegExp(r'^[A-Za-z0-9_.-]+$');

  /// [variableNames] are the variables to give to the job; duplicates are mapped once.
  static CiSecretMapping map(Iterable<String> variableNames) {
    final secrets = <CiSecret>[];
    final skipped = <String>[];
    final seenVariables = <String>{};
    final usedNames = <String>{};
    for (final raw in variableNames) {
      final variable = raw.trim();
      if (variable.isEmpty || !seenVariables.add(variable)) continue;
      if (!_usable.hasMatch(variable)) {
        skipped.add('"$variable" has characters other than letters, digits, _ . and -, so it cannot be an environment variable');
        continue;
      }
      final base = secretNameOf(variable);
      var name = base;
      for (var n = 2; usedNames.contains(name); n++) {
        name = '${base}_$n';
      }
      usedNames.add(name);
      secrets.add(CiSecret(variable, name));
    }
    return CiSecretMapping(secrets, skipped);
  }

  /// `odooApiKey` -> `ODOO_API_KEY`, `X-API-Key` -> `X_API_KEY`, `db.password` -> `DB_PASSWORD`.
  static String secretNameOf(String variable) {
    final words = [for (final m in _word.allMatches(variable)) m[0]!.toUpperCase()];
    var name = words.join('_');
    if (name.isEmpty) name = 'SECRET';
    // `GITHUB_` is reserved for GitHub's own, and a name cannot start with a digit.
    if (name.startsWith('GITHUB_') || RegExp(r'^[0-9]').hasMatch(name)) name = 'PP_$name';
    return name;
  }
}
