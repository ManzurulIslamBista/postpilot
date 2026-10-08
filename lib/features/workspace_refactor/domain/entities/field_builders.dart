import '../../../../core/enums/auth_type.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
import 'refactor_scope.dart';
import 'unit_field.dart';

/// Building blocks the units share: the rows of a header list, the fields of an auth, the lines of a test list.
/// Each yields [UnitField]s whose `write` hands the changed list back to the unit to rebuild itself with.

/// A value made only of `{{variables}}`: a reference to a secret, not the secret itself.
final _onlyReferences = RegExp(r'^\s*(?:\{\{[^{}]+\}\}\s*)+$');

bool isOnlyReferences(String value) => _onlyReferences.hasMatch(value);

/// [text] cut to [max] characters for a label.
String shorten(String text, [int max = 32]) => text.length <= max ? text : '${text.substring(0, max - 1)}…';

/// [list] with the element at [index] replaced.
List<T> replacedAt<T>(List<T> list, int index, T item) => [...list.sublist(0, index), item, ...list.sublist(index + 1)];

/// The key and value of every row (and the file name and content type of a form-data file row).
Iterable<UnitField> keyValueFields({
  required List<KeyValueItem> rows,
  required String pathPrefix,
  required String group,
  required RefactorScope scope,
  required String what,
  required RefactorUnit Function(List<KeyValueItem> rows) rebuild,
  bool unused = false,
}) sync* {
  final suffix = unused ? ' (unused)' : '';
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final name = row.key.isEmpty ? '$what ${i + 1}' : '$what "${shorten(row.key)}"';
    UnitField field(String part, String label, String value, KeyValueItem Function(String) change) => UnitField(
      path: '$pathPrefix.$i.$part',
      group: group,
      scope: scope,
      label: '$label$suffix',
      value: value,
      active: row.enabled && !unused,
      write: (v) => rebuild(replacedAt(rows, i, change(v))),
    );
    if (row.key.isNotEmpty) yield field('key', '$what key', row.key, (v) => row.copyWith(key: v));
    if (row.value.isNotEmpty) yield field('value', '$name value', row.value, (v) => row.copyWith(value: v));
    if (row.isFile) {
      if (row.fileName.isNotEmpty) yield field('fileName', '$name file name', row.fileName, (v) => row.copyWith(fileName: v));
      if (row.contentType.isNotEmpty) yield field('contentType', '$name content type', row.contentType, (v) => row.copyWith(contentType: v));
    }
  }
}

/// One text of an auth config.
final class AuthTextField {
  final String name;
  final String label;

  /// A credential: its value is a secret unless it only refers to variables.
  final bool secret;

  /// The auth types that use the field; under another type it is leftover text.
  final Set<AuthType> types;

  /// What the field holds in a new auth: a leftover that still says this is not worth listing.
  final String defaultValue;
  final String Function(RequestAuth auth) read;
  final RequestAuth Function(RequestAuth auth, String value) write;

  const AuthTextField(
    this.name,
    this.label,
    this.types,
    this.read,
    this.write, {
    this.secret = false,
    this.defaultValue = '',
  });
}

const _oauth2 = {AuthType.oauth2};

/// The texts of a [RequestAuth] a user typed. The tokens an OAuth 2.0 flow fetched are not among them: they are
/// state, not configuration.
final List<AuthTextField> authTextFields = [
  AuthTextField('apiKeyName', 'API key name', const {AuthType.apiKey}, (a) => a.apiKeyName, (a, v) => a.copyWith(apiKeyName: v)),
  AuthTextField('apiKeyValue', 'API key', const {AuthType.apiKey}, (a) => a.apiKeyValue, (a, v) => a.copyWith(apiKeyValue: v), secret: true),
  AuthTextField('bearerToken', 'Bearer token', const {AuthType.bearer}, (a) => a.bearerToken, (a, v) => a.copyWith(bearerToken: v), secret: true),
  AuthTextField('basicUsername', 'user name', const {AuthType.basic, AuthType.digest}, (a) => a.basicUsername, (a, v) => a.copyWith(basicUsername: v)),
  AuthTextField('basicPassword', 'password', const {AuthType.basic, AuthType.digest}, (a) => a.basicPassword, (a, v) => a.copyWith(basicPassword: v), secret: true),
  AuthTextField('awsAccessKey', 'AWS access key', const {AuthType.awsSignatureV4}, (a) => a.awsAccessKey, (a, v) => a.copyWith(awsAccessKey: v)),
  AuthTextField('awsSecretKey', 'AWS secret key', const {AuthType.awsSignatureV4}, (a) => a.awsSecretKey, (a, v) => a.copyWith(awsSecretKey: v), secret: true),
  AuthTextField('awsRegion', 'AWS region', const {AuthType.awsSignatureV4}, (a) => a.awsRegion, (a, v) => a.copyWith(awsRegion: v), defaultValue: 'us-east-1'),
  AuthTextField('awsService', 'AWS service', const {AuthType.awsSignatureV4}, (a) => a.awsService, (a, v) => a.copyWith(awsService: v), defaultValue: 'execute-api'),
  AuthTextField('awsSessionToken', 'AWS session token', const {AuthType.awsSignatureV4}, (a) => a.awsSessionToken, (a, v) => a.copyWith(awsSessionToken: v), secret: true),
  AuthTextField('jwtSecret', 'JWT secret', const {AuthType.jwtBearer}, (a) => a.jwtSecret, (a, v) => a.copyWith(jwtSecret: v), secret: true),
  AuthTextField('jwtPayload', 'JWT payload', const {AuthType.jwtBearer}, (a) => a.jwtPayload, (a, v) => a.copyWith(jwtPayload: v), defaultValue: '{}'),
  AuthTextField('jwtHeaderPrefix', 'JWT header prefix', const {AuthType.jwtBearer}, (a) => a.jwtHeaderPrefix, (a, v) => a.copyWith(jwtHeaderPrefix: v), defaultValue: 'Bearer'),
  AuthTextField('oauth2AccessTokenUrl', 'OAuth 2.0 token URL', _oauth2, (a) => a.oauth2AccessTokenUrl, (a, v) => a.copyWith(oauth2AccessTokenUrl: v)),
  AuthTextField('oauth2AuthorizationUrl', 'OAuth 2.0 authorization URL', _oauth2, (a) => a.oauth2AuthorizationUrl, (a, v) => a.copyWith(oauth2AuthorizationUrl: v)),
  AuthTextField('oauth2RedirectUri', 'OAuth 2.0 redirect URI', _oauth2, (a) => a.oauth2RedirectUri, (a, v) => a.copyWith(oauth2RedirectUri: v)),
  AuthTextField('oauth2ClientId', 'OAuth 2.0 client id', _oauth2, (a) => a.oauth2ClientId, (a, v) => a.copyWith(oauth2ClientId: v)),
  AuthTextField('oauth2ClientSecret', 'OAuth 2.0 client secret', _oauth2, (a) => a.oauth2ClientSecret, (a, v) => a.copyWith(oauth2ClientSecret: v), secret: true),
  AuthTextField('oauth2Scope', 'OAuth 2.0 scope', _oauth2, (a) => a.oauth2Scope, (a, v) => a.copyWith(oauth2Scope: v)),
  AuthTextField('oauth2Username', 'OAuth 2.0 user name', _oauth2, (a) => a.oauth2Username, (a, v) => a.copyWith(oauth2Username: v)),
  AuthTextField('oauth2Password', 'OAuth 2.0 password', _oauth2, (a) => a.oauth2Password, (a, v) => a.copyWith(oauth2Password: v), secret: true),
  AuthTextField('oauth2Audience', 'OAuth 2.0 audience', _oauth2, (a) => a.oauth2Audience, (a, v) => a.copyWith(oauth2Audience: v)),
];

/// The texts of [auth]: those of the type in force, and leftovers of a type the user switched away from (a request
/// that was Bearer once still holds its token, and it comes back when the type does) unless they only repeat a default.
Iterable<UnitField> authFields({
  required RequestAuth auth,
  required String pathPrefix,
  required String group,
  required RefactorScope scope,
  required String what,
  required RefactorUnit Function(RequestAuth auth) rebuild,
}) sync* {
  for (final field in authTextFields) {
    final value = field.read(auth);
    final inUse = field.types.contains(auth.type);
    if (value.isEmpty || (!inUse && value == field.defaultValue)) continue;
    yield UnitField(
      path: '$pathPrefix.${field.name}',
      group: group,
      scope: scope,
      label: '$what: ${field.label}${inUse ? '' : ' (unused)'}',
      value: value,
      secret: field.secret && !isOnlyReferences(value),
      active: inUse,
      write: (v) => rebuild(field.write(auth, v)),
    );
  }
}

/// The assertions and extractors of a request or of a level's defaults. An extractor's variable name defines a
/// variable; [ownerKey] and [ownerLabel] say whose it is.
Iterable<UnitField> testFields({
  required List<AssertionEntity> assertions,
  required List<ExtractorEntity> extractors,
  required String pathPrefix,
  required String group,
  required RefactorScope scope,
  required String ownerKey,
  required String ownerLabel,
  required RefactorUnit Function(List<AssertionEntity>? assertions, List<ExtractorEntity>? extractors) rebuild,
}) sync* {
  for (var i = 0; i < assertions.length; i++) {
    final a = assertions[i];
    UnitField field(String part, String label, String value, AssertionEntity Function(String) change) => UnitField(
      path: '$pathPrefix.assert.$i.$part',
      group: group,
      scope: scope,
      label: label,
      value: value,
      write: (v) => rebuild(replacedAt(assertions, i, change(v)), null),
    );
    final what = 'Test ${i + 1} (${a.type.label})';
    if (a.path.isNotEmpty) yield field('path', '$what ${a.type.isHeader ? 'header' : 'path'}', a.path, (v) => a.copyWith(path: v));
    if (a.expected.isNotEmpty) yield field('expected', '$what expected value', a.expected, (v) => a.copyWith(expected: v));
  }
  for (var i = 0; i < extractors.length; i++) {
    final x = extractors[i];
    UnitField field(String part, String label, String value, ExtractorEntity Function(String) change, {VariableDefinition? defines}) =>
        UnitField(
          path: '$pathPrefix.extract.$i.$part',
          group: group,
          scope: scope,
          label: label,
          value: value,
          defines: defines,
          write: (v) => rebuild(null, replacedAt(extractors, i, change(v))),
        );
    final name = 'Extractor ${i + 1}';
    if (x.path.isNotEmpty) yield field('path', '$name ${x.source == ExtractorSource.header ? 'header' : 'path'}', x.path, (v) => x.copyWith(path: v));
    final target = x.variableKey.trim();
    if (x.variableKey.isNotEmpty) {
      yield field(
        'key',
        '$name variable name',
        x.variableKey,
        (v) => x.copyWith(variableKey: v),
        defines: target.isEmpty
            ? null
            : VariableDefinition(
                name: target,
                home: VariableHome.extractor,
                containerKey: 'extractor:$ownerKey:$pathPrefix.$i',
                where: 'Extractor of $ownerLabel',
                unitKey: ownerKey,
                keyPath: '$pathPrefix.extract.$i.key',
                value: x.path,
              ),
      );
    }
  }
}
