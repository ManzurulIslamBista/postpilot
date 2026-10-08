// Pure Dart (no Flutter, no database).
import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../entities/auth_finding.dart';
import 'auth_context.dart';
import 'token_evidence.dart';

/// What was wrong with the credential the request carried, or with the fact that it carried none: no credential at
/// all, a variable that is undefined or empty, a token that is the word `null`, a doubled `Bearer`, whitespace in a
/// token, a `Basic` header that is not `user:password`.
abstract final class CredentialChecks {
  static const _schemes = {'bearer', 'basic', 'token', 'digest', 'apikey', 'jwt'};
  static const _singleTokenSchemes = {'bearer', 'basic', 'token', ''};
  static const _nullish = {'null', 'undefined', 'nan', 'none', 'nil', '(null)', '[object object]', 'false'};

  static List<AuthFinding> run(AuthContext ctx) {
    final out = <AuthFinding>[];
    if (!ctx.input.requestKnown) return out;
    final missing = _noCredential(ctx);
    if (missing != null) out.add(missing);
    for (final credential in ctx.credentials) {
      final fromVariable = _variables(ctx, credential);
      out.addAll(fromVariable);
      if (credential.isCookie) continue;
      out.addAll(_value(ctx, credential, explainedByVariable: fromVariable.isNotEmpty));
    }
    return out;
  }

  // --- nothing was sent -----------------------------------------------------------------------------------------

  static AuthFinding? _noCredential(AuthContext ctx) {
    final status = ctx.status;
    if (status != 401 && status != 403 && status != 407) return null;
    final proxy = status == 407;
    if (proxy ? ctx.authorization != null : ctx.hasCredential) return null;
    final input = ctx.input;
    final type = input.authType;

    final String why;
    final String fix;
    switch (type) {
      case AuthType.apiKey when input.apiKeyName.trim().isEmpty:
        why = 'API Key auth is selected but the key has no name, so no header or query parameter was added.';
        fix = 'Open the Auth tab and fill in the key name (for example X-API-Key) and its value.';
      case AuthType.oauth2:
        why = 'OAuth 2.0 auth is selected but there is no access token yet, so no Authorization header was added.';
        fix = 'Open the Auth tab and choose "Get new access token" (or send once so the app fetches it by itself).';
      case AuthType.inherit:
        why = 'The request is set to inherit its auth, but the folder and the collection above it define none, so nothing was sent.';
        fix = 'Set the auth once on the collection (Collection defaults) or choose a type in the request\'s Auth tab.';
      default:
        why = proxy
            ? 'The request carried no Proxy-Authorization header, so the proxy had nothing to check.'
            : 'The request carried no Authorization header, no cookie and no API key (header or query string)'
                '${type == AuthType.none ? ', and its auth type is "No Auth"' : ''}.';
        fix = proxy
            ? 'Give the proxy a user name and password in Settings (Proxy: custom), or add a Proxy-Authorization header.'
            : 'Open the Auth tab, choose Bearer Token (or the type your API uses) and put the token in a variable such as {{token}}; '
                'or set the auth once on the collection and let the request inherit it.';
    }
    return AuthFinding(
      id: proxy ? 'credential.no-proxy-credential' : 'credential.none-sent',
      confidence: status == 403 ? FindingConfidence.likely : FindingConfidence.certain,
      title: proxy ? 'No proxy credentials were sent' : 'No credential was sent',
      explanation: status == 403
          ? '$why Many servers answer an anonymous call with 403 instead of 401.'
          : why,
      fix: fix,
      evidence: [
        'Auth type: ${type.label}',
        if (!proxy) 'No Authorization, Cookie or API-key header, and no key in the query string of the URL.',
        if (proxy) 'No Proxy-Authorization header was sent.',
      ],
    );
  }

  // --- the variables that feed a credential ----------------------------------------------------------------------

  static List<AuthFinding> _variables(AuthContext ctx, SentCredential credential) {
    final out = <AuthFinding>[];
    final env = ctx.input.environmentName;
    final where = env == null ? 'no environment is selected' : 'the active environment is "$env"';
    for (final name in credential.variables) {
      final fact = ctx.input.variables[name];
      final elsewhere = [
        for (final other in ctx.input.otherEnvironments)
          if (other.filledVariables.contains(name)) other.name,
      ];
      final hint = elsewhere.isEmpty ? '' : ' It has a value in ${AuthText.list(elsewhere.map((e) => '"$e"'))}: switch to it.';
      if (fact == null) {
        out.add(AuthFinding(
          id: 'credential.variable-undefined',
          confidence: FindingConfidence.certain,
          title: '{{$name}} is not defined',
          explanation: '${_Words.capital(credential.label)} is fed by {{$name}}, but no variable of that name is visible to this request '
              '($where), so the credential cannot have been the real one.',
          fix: 'Select the environment that defines $name, or add it to the environment, the collection variables or the globals.$hint',
          evidence: [
            '${_Words.capital(credential.label)} is fed by {{$name}}.',
            if (env == null) 'No environment is active.' else 'Active environment: $env.',
          ],
        ));
      } else if (fact.isEmpty) {
        final scope = fact.scopeName == null ? fact.source : '${fact.source} "${fact.scopeName}"';
        out.add(AuthFinding(
          id: 'credential.variable-empty',
          confidence: FindingConfidence.certain,
          title: '{{$name}} is empty',
          explanation: '${_Words.capital(credential.label)} is fed by {{$name}}, and that variable holds nothing in the $scope, '
              'so the server received an empty credential.',
          fix: 'Fill it in: run the login request that saves it, or paste the value into the variable.$hint',
          evidence: [
            '${_Words.capital(credential.label)} is fed by {{$name}}.',
            '{{$name}} is empty in the $scope${fact.isSecret ? ' (a secret variable)' : ''}.',
          ],
        ));
      }
    }
    return out;
  }

  // --- the value that was sent -----------------------------------------------------------------------------------

  static List<AuthFinding> _value(AuthContext ctx, SentCredential c, {required bool explainedByVariable}) {
    final out = <AuthFinding>[];
    // A variable that is undefined or empty already says why the value is what it is.
    if (explainedByVariable) return out;
    final secret = c.secret;
    final label = _Words.capital(c.label);
    final shown = c.isAuthorization ? TokenEvidence.ofHeader(c.value) : TokenEvidence.of(c.value);

    // A placeholder that reached the wire is the one problem that is not about the value itself.
    if (c.value.contains('{{') && c.value.contains('}}')) {
      out.add(AuthFinding(
        id: 'credential.placeholder',
        confidence: FindingConfidence.certain,
        title: 'A {{placeholder}} was sent as text',
        explanation: '$label still contains a {{variable}} reference. A variable whose value is its own name, or a smart reference that '
            'was not looked up, is sent as written.',
        fix: 'Make the variable hold the real credential, or send once the request that saves it.',
        evidence: ['$label: $shown'],
      ));
      return out;
    }

    final lowerSecret = secret.toLowerCase();
    final bareScheme = c.isAuthorization && c.scheme.isEmpty && _schemes.contains(lowerSecret);
    if (c.value.trim().isEmpty || bareScheme) {
      out.add(AuthFinding(
        id: 'credential.empty',
        confidence: FindingConfidence.certain,
        title: 'The credential is empty',
        explanation: '$label has no value after ${bareScheme ? 'the scheme word' : 'the name'}, so the server received no credential.',
        fix: 'Put the token in the Auth tab (or the header row). If it comes from a variable, check that the variable has a value.',
        evidence: ['$label: ${c.value.isEmpty ? 'empty' : '"${c.value.trim()}" and nothing else'}'],
      ));
      return out;
    }
    if (_nullish.contains(lowerSecret)) {
      out.add(AuthFinding(
        id: 'credential.literal-null',
        confidence: FindingConfidence.certain,
        title: 'The token is the word "${secret.toLowerCase()}"',
        explanation: '$label carries the text "$secret" instead of a token. This happens when a login script saves a value that was '
            'missing from the response, or a variable was saved from the wrong JSON path.',
        fix: 'Check the request that saves this token (its variable extractor) and run it again; then send this request.',
        evidence: ['$label: the value is literally "$secret".'],
      ));
      return out;
    }
    if (c.isAuthorization && RegExp(r'^(?:bearer|basic|token|digest)\s+\S', caseSensitive: false).hasMatch(secret)) {
      out.add(AuthFinding(
        id: 'credential.double-scheme',
        confidence: FindingConfidence.certain,
        title: 'The scheme word is written twice',
        explanation: '$label reads "${c.scheme} ${secret.split(RegExp(r'\s+')).first} ...": the word is there twice, so the server reads '
            'the second one as the token. Usually the token variable already starts with "Bearer " and the Auth tab adds it again.',
        fix: 'Keep "Bearer " in only one place: either in the variable or in the Auth tab, not both.',
        evidence: ['$label: ${TokenEvidence.ofHeader(c.value)}', 'The text after "${c.scheme}" starts with another scheme word.'],
      ));
      return out;
    }
    // Schemes such as Digest, OAuth and AWS4-HMAC-SHA256 carry spaces of their own; a bare token never does.
    final singleToken = !c.isAuthorization || _singleTokenSchemes.contains(c.scheme.toLowerCase());
    if (RegExp(r'[\r\n\t]').hasMatch(c.value) || (singleToken && RegExp(r'\s').hasMatch(c.isAuthorization ? secret : c.value.trim()))) {
      out.add(AuthFinding(
        id: 'credential.whitespace',
        confidence: FindingConfidence.certain,
        title: 'There is whitespace inside the token',
        explanation: '$label contains a space, tab or line break in the middle of the credential, so the server sees something that '
            'is not the token. A value pasted from a terminal or a JSON file often brings a trailing newline along.',
        fix: 'Paste the token again without any space or line break, or turn on "Trim keys and values" in Settings.',
        evidence: ['$label: ${TokenEvidence.ofHeader(c.value)}'],
      ));
      return out;
    }
    if (c.value != c.value.trim()) {
      out.add(AuthFinding(
        id: 'credential.padding',
        confidence: FindingConfidence.likely,
        title: 'The credential has spaces around it',
        explanation: '$label starts or ends with whitespace. Most clients trim it, some servers compare it as it is.',
        fix: 'Remove the space before or after the value (or turn on "Trim keys and values" in Settings).',
        evidence: ['$label: ${TokenEvidence.ofHeader(c.value.trim())}'],
      ));
    }
    if (secret.length > 2 && ((secret.startsWith('"') && secret.endsWith('"')) || (secret.startsWith("'") && secret.endsWith("'")))) {
      out.add(AuthFinding(
        id: 'credential.quoted',
        confidence: FindingConfidence.likely,
        title: 'The token is wrapped in quotes',
        explanation: '$label starts and ends with a quote character. A JSON string saved without unquoting it keeps its quotes, '
            'and the server then looks for a token that includes them.',
        fix: 'Remove the quotes around the token (check the extractor that saves it: use the string value, not its JSON text).',
        evidence: ['$label: ${TokenEvidence.ofHeader(c.value)}'],
      ));
    }
    if (c.isAuthorization && c.scheme.isEmpty && ctx.input.authType != AuthType.apiKey && secret.length >= 16) {
      out.add(AuthFinding(
        id: 'credential.no-scheme',
        confidence: FindingConfidence.likely,
        title: 'The Authorization header has no scheme word',
        explanation: '$label holds only the token. Most APIs expect "Bearer <token>", "Basic <credentials>" or another scheme before it.',
        fix: 'Write "Bearer " before the token, or use the Bearer Token type in the Auth tab.',
        evidence: ['$label: ${TokenEvidence.of(secret)}'],
      ));
    }
    if (c.isAuthorization && c.scheme.toLowerCase() == 'basic') {
      final basic = _basic(c, label);
      if (basic != null) out.add(basic);
    }
    return out;
  }

  /// A `Basic` credential must be the base64 of `user:password`, with both halves filled in.
  static AuthFinding? _basic(SentCredential c, String label) {
    String? decoded;
    try {
      decoded = utf8.decode(base64.decode(base64.normalize(c.secret)));
    } catch (_) {
      decoded = null;
    }
    if (decoded == null || !decoded.contains(':')) {
      return AuthFinding(
        id: 'credential.basic-malformed',
        confidence: FindingConfidence.likely,
        title: 'The Basic credential is not user:password',
        explanation: '$label does not decode to "user:password" in base64, so the server cannot split it into a user and a password.',
        fix: 'Use the Basic Auth type in the Auth tab and fill in the user name and the password; it encodes them for you.',
        evidence: ['$label: ${TokenEvidence.ofHeader(c.value)}'],
      );
    }
    final colon = decoded.indexOf(':');
    final user = decoded.substring(0, colon);
    final password = decoded.substring(colon + 1);
    if (user.isEmpty || password.isEmpty) {
      return AuthFinding(
        id: 'credential.basic-empty-half',
        confidence: FindingConfidence.certain,
        title: user.isEmpty ? 'The Basic user name is empty' : 'The Basic password is empty',
        explanation: '$label decodes to ${user.isEmpty ? 'an empty user name' : 'an empty password'}. '
            'A variable that has no value leaves the half empty.',
        fix: 'Fill in the ${user.isEmpty ? 'user name' : 'password'} in the Auth tab, or give the variable it uses a value.',
        evidence: ['$label: ${TokenEvidence.ofHeader(c.value)}', if (user.isEmpty) 'The user name is empty.' else 'The password is empty.'],
      );
    }
    return null;
  }
}

abstract final class _Words {
  /// `the "Authorization" header` -> `The "Authorization" header`.
  static String capital(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}
