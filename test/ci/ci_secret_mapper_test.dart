// Variable names become CI secret names. GitHub allows letters, digits and underscores only, forbids a leading digit and
// the GITHUB_ prefix, and ignores case, so each expectation below follows those rules by hand.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/ci/domain/entities/ci_options.dart';
import 'package:postpilot/features/ci/domain/services/ci_secret_mapper.dart';

void main() {
  test('camelCase, acronyms, separators and dots become UPPER_SNAKE_CASE', () {
    expect(CiSecretMapper.secretNameOf('odooApiKey'), 'ODOO_API_KEY');
    expect(CiSecretMapper.secretNameOf('X-API-Key'), 'X_API_KEY');
    expect(CiSecretMapper.secretNameOf('db.password'), 'DB_PASSWORD');
    expect(CiSecretMapper.secretNameOf('APIKey'), 'API_KEY');
    expect(CiSecretMapper.secretNameOf('client_secret'), 'CLIENT_SECRET');
    expect(CiSecretMapper.secretNameOf('apiKey2'), 'API_KEY_2');
  });

  test('a reserved or number-leading name gets a prefix', () {
    expect(CiSecretMapper.secretNameOf('githubToken'), 'PP_GITHUB_TOKEN');
    expect(CiSecretMapper.secretNameOf('2fa_secret'), 'PP_2_FA_SECRET');
    // Only the GITHUB_ prefix is reserved, not a name that merely contains it.
    expect(CiSecretMapper.secretNameOf('myGithubToken'), 'MY_GITHUB_TOKEN');
  });

  test('every secret gets a name that is a legal secret name', () {
    final mapping = CiSecretMapper.map(['odooApiKey', 'db.password', 'X-API-Key', 'githubToken', '9lives', 'a.b-c.d']);
    expect(mapping.skipped, isEmpty);
    expect(mapping.secrets, hasLength(6));
    for (final s in mapping.secrets) {
      expect(s.secretName, matches(RegExp(r'^[A-Z_][A-Z0-9_]*$')), reason: s.variable);
      expect(s.secretName.startsWith('GITHUB_'), isFalse, reason: s.variable);
    }
  });

  test('names that collapse to one secret name are numbered, case-insensitively unique', () {
    final mapping = CiSecretMapper.map(['api-key', 'api_key', 'apiKey', 'API.KEY']);
    expect([for (final s in mapping.secrets) s.secretName], ['API_KEY', 'API_KEY_2', 'API_KEY_3', 'API_KEY_4']);
    expect([for (final s in mapping.secrets) s.variable], ['api-key', 'api_key', 'apiKey', 'API.KEY']);
  });

  test('a variable listed twice is mapped once, blanks are ignored', () {
    final mapping = CiSecretMapper.map(['token', 'token', '  ', '', ' token ']);
    expect(mapping.secrets, [const CiSecret('token', 'TOKEN')]);
  });

  test('a name that cannot be an environment variable is reported, not mapped', () {
    final mapping = CiSecretMapper.map(['good_one', 'bad name', r'cost$']);
    expect(mapping.secrets.map((s) => s.variable), ['good_one']);
    expect(mapping.skipped, hasLength(2));
    expect(mapping.skipped.first, contains('"bad name"'));
    expect(mapping.skipped.first, contains('cannot be an environment variable'));
  });

  test('the process variable is POSTPILOT_VAR_ plus the variable name, as the command line reads it', () {
    const secret = CiSecret('db.password', 'DB_PASSWORD');
    expect(secret.processVariable, 'POSTPILOT_VAR_db.password');
  });
}
