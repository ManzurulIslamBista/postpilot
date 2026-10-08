// Pure Dart (no Flutter, no database).
import '../../../../core/constants/app_constants.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../entities/auth_doctor_input.dart';
import 'token_evidence.dart';
import 'www_authenticate.dart';

enum CredentialPlace { header, query }

/// A credential the request carried: a header or a query parameter, as sent, with the template it was written as.
final class SentCredential {
  final CredentialPlace place;
  final String name;

  /// The whole header value or query value, as sent.
  final String value;

  /// The value as written (`Bearer {{token}}`), when the request was built from templates the doctor knows.
  final String? template;

  /// The word before the credential in an `Authorization` value (`Bearer`); empty when there is none.
  final String scheme;

  /// What follows the scheme: the token, the base64 of `user:password`.
  final String secret;

  const SentCredential({
    required this.place,
    required this.name,
    required this.value,
    this.template,
    this.scheme = '',
    this.secret = '',
  });

  /// `Authorization` or `Proxy-Authorization`: a header whose value is a scheme word and a credential.
  bool get isAuthorization => place == CredentialPlace.header && name.toLowerCase().endsWith('authorization');
  bool get isCookie => place == CredentialPlace.header && name.toLowerCase() == 'cookie';

  /// `the "Authorization" header`, `the "api_key" query parameter`.
  String get label => place == CredentialPlace.header ? 'the "$name" header' : 'the "$name" query parameter';

  /// The variables the credential was written with.
  List<String> get variables => AuthText.variablesIn(template ?? '');
}

/// What every check needs, worked out once from the input.
final class AuthContext {
  final AuthDoctorInput input;
  final Uri? uri;
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final String body;
  final String bodyLower;
  final List<SentCredential> credentials;

  /// The challenges the server made: `WWW-Authenticate`, or `Proxy-Authenticate` for a 407.
  final List<AuthChallenge> challenges;

  const AuthContext._(
    this.input,
    this.uri,
    this.requestHeaders,
    this.responseHeaders,
    this.body,
    this.bodyLower,
    this.credentials,
    this.challenges,
  );

  /// The body is only read up to here; a rejection that needs more than this to be told is not worth the scan.
  static const _maxBody = 64 * 1024;

  factory AuthContext.of(AuthDoctorInput input) {
    final uri = Uri.tryParse(input.url);
    final request = {for (final e in input.headers.entries) e.key.toLowerCase(): e.value};
    final response = {for (final e in input.responseHeaders.entries) e.key.toLowerCase(): e.value};
    final body = input.responseBody.length > _maxBody ? input.responseBody.substring(0, _maxBody) : input.responseBody;
    final headerTemplates = {for (final e in input.headerTemplates.entries) e.key.toLowerCase(): e.value};
    final isProxy = input.status == 407;

    final credentials = <SentCredential>[];
    for (final entry in input.headers.entries) {
      final lower = entry.key.toLowerCase();
      if (lower == 'proxy-authorization' && !isProxy) continue;
      if (lower.contains('csrf') || lower.contains('xsrf')) continue;
      final isCredential = lower == 'authorization' ||
          lower == 'proxy-authorization' ||
          lower == 'cookie' ||
          SecretNames.isSecretHeader(entry.key) ||
          SecretMasker.isSensitiveName(entry.key);
      if (!isCredential) continue;
      final (scheme, secret) = _split(entry.value, authorization: lower.endsWith('authorization'));
      credentials.add(SentCredential(
        place: CredentialPlace.header,
        name: entry.key,
        value: entry.value,
        template: headerTemplates[lower],
        scheme: scheme,
        secret: secret,
      ));
    }
    if (uri != null) {
      for (final entry in uri.queryParametersAll.entries) {
        if (!SecretNames.isSecretQuery(entry.key)) continue;
        for (final value in entry.value) {
          credentials.add(SentCredential(
            place: CredentialPlace.query,
            name: entry.key,
            value: value,
            template: input.queryTemplates[entry.key],
            secret: value,
          ));
        }
      }
    }

    return AuthContext._(
      input,
      uri,
      request,
      response,
      body,
      body.toLowerCase(),
      credentials,
      WwwAuthenticate.parse(response[isProxy ? 'proxy-authenticate' : 'www-authenticate']),
    );
  }

  static final _schemed = RegExp(r'^([A-Za-z][A-Za-z0-9._~+-]*)\s+([\s\S]*)$');

  static (String, String) _split(String value, {required bool authorization}) {
    if (!authorization) return ('', value.trim());
    final match = _schemed.firstMatch(value.trim());
    if (match == null) return ('', value.trim());
    return (match[1]!, match[2]!);
  }

  String get host => (uri?.host ?? '').toLowerCase();
  int get status => input.status;
  DateTime get now => input.now;

  /// Text the server wrote, safe to show: the credentials of this request and anything that looks like one are masked first
  /// (a server may echo the token it rejected), then it is put on one line and clipped.
  String quote(String text, {int max = 160}) {
    var hidden = text;
    for (final c in credentials) {
      for (final secret in {c.secret, c.value}) {
        if (secret.length >= _minHidden) hidden = hidden.replaceAll(secret, SecretMasker.mask);
      }
    }
    return TokenEvidence.quote(hidden, max: max);
  }

  /// Shorter values are not hidden: they would blank out ordinary words.
  static const _minHidden = 6;

  String? requestHeader(String name) => requestHeaders[name.toLowerCase()];
  String? responseHeader(String name) => responseHeaders[name.toLowerCase()];

  /// The `Authorization` (or, for a 407, `Proxy-Authorization`) credential.
  SentCredential? get authorization {
    final wanted = status == 407 ? 'proxy-authorization' : 'authorization';
    for (final c in credentials) {
      if (c.place == CredentialPlace.header && c.name.toLowerCase() == wanted) return c;
    }
    return null;
  }

  /// A credential was sent, or will be answered to a challenge (Digest asks first, then sends).
  bool get hasCredential => credentials.isNotEmpty || input.authType == AuthType.digest;

  /// Credentials that are not a cookie: a token, a key, a password.
  List<SentCredential> get tokens => [
        for (final c in credentials)
          if (!c.isCookie) c,
      ];

  bool get isHtml {
    final type = responseHeader('content-type') ?? '';
    return type.toLowerCase().contains('html') || body.trimLeft().startsWith('<');
  }

  bool get isJson {
    final type = responseHeader('content-type') ?? '';
    return type.toLowerCase().contains('json') || body.trimLeft().startsWith('{');
  }

  /// A scheme the server asked for, or null when it asked for none.
  AuthChallenge? challenge(String scheme) {
    for (final c in challenges) {
      if (c.isScheme(scheme)) return c;
    }
    return null;
  }
}

/// Small text helpers the checks share.
abstract final class AuthText {
  /// The `{{names}}` in [template], without the built-in `{{$guid}}` family, in order, once each.
  static List<String> variablesIn(String template) => [
        for (final name in {for (final m in AppConstants.variablePattern.allMatches(template)) m[1]!})
          if (!name.startsWith(r'$')) name,
      ];

  /// `3 hours 12 minutes`, `45 seconds`, `2 days 3 hours`: the two largest units.
  static String span(Duration duration) {
    var seconds = duration.inSeconds.abs();
    if (seconds < 1) return 'less than a second';
    final days = seconds ~/ 86400;
    seconds %= 86400;
    final hours = seconds ~/ 3600;
    seconds %= 3600;
    final minutes = seconds ~/ 60;
    seconds %= 60;
    String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    final parts = [
      if (days > 0) unit(days, 'day'),
      if (hours > 0) unit(hours, 'hour'),
      if (minutes > 0) unit(minutes, 'minute'),
      if (seconds > 0 && days == 0 && hours == 0) unit(seconds, 'second'),
    ];
    return parts.take(2).join(' ');
  }

  /// `2026-10-08 09:00 UTC`.
  static String stamp(DateTime time) {
    final t = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} UTC';
  }

  /// `Sun, 06 Nov 1994 08:49:37 GMT`, the only date format a server should send in a `Date` header.
  static DateTime? httpDate(String? text) {
    if (text == null) return null;
    final m = RegExp(r'^\w{3},\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT$').firstMatch(text.trim());
    if (m == null) return null;
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final month = months.indexOf(m[2]!.toLowerCase()) + 1;
    if (month == 0) return null;
    return DateTime.utc(int.parse(m[3]!), month, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
  }

  /// `a`, `a and b`, `a, b and c`.
  static String list(Iterable<String> items) {
    final all = items.toList();
    if (all.length <= 1) return all.join();
    return '${all.sublist(0, all.length - 1).join(', ')} and ${all.last}';
  }
}
