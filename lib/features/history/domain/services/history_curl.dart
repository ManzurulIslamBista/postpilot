import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../request_builder/domain/services/code_generators/string_literals.dart';
import '../entities/history_snapshot.dart';
import 'history_har.dart';

/// "Copy as cURL" for a History entry, in the template form: the command is
/// built from the stored request alone, so `{{variables}}` stay as written and a
/// credential that was masked stays masked. Nothing is resolved here, which is
/// the point: pasting an old call into a chat or a ticket must not carry
/// whatever the active environment holds today. (The resolved form is the
/// request builder's own code generator, offered separately and on purpose.)
///
/// The lines are laid out like `CurlGenerator`'s.
abstract final class HistoryCurl {
  static String template(HistoryRequestSnapshot snapshot) {
    String same(String text) => text;
    final auth = snapshot.auth;
    var url = snapshot.fullUrl;
    final apiKeyQuery = HistoryHar.apiKeyQueryPair(auth, same);
    if (apiKeyQuery != null) url = '$url${url.contains('?') ? '&' : '?'}$apiKeyQuery';

    final headers = <String, String>{
      for (final h in snapshot.headers)
        if (h.enabled && h.key.isNotEmpty) h.key: h.value,
    };
    bool has(String name) => headers.keys.any((k) => k.toLowerCase() == name.toLowerCase());
    final authHeader = HistoryHar.authorizationHeader(auth, same);
    if (authHeader != null && !has(authHeader.name)) headers[authHeader.name] = authHeader.value;

    final body = snapshot.body;
    String? data;
    String? contentType;
    final formFields = <String>[];
    switch (body.type) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (body.rawText.isNotEmpty) {
          data = body.rawText;
          contentType = body.rawContentType.mimeType;
        }
      case BodyType.graphql:
        data = jsonEncode({'query': body.graphqlQuery, 'variables': _variables(body.graphqlVariables)});
        contentType = 'application/json';
      case BodyType.urlEncoded:
        final fields = [for (final f in body.urlEncodedFields) if (f.enabled && f.key.isNotEmpty) '${f.key}=${f.value}'];
        if (fields.isNotEmpty) {
          data = fields.join('&');
          contentType = 'application/x-www-form-urlencoded';
        }
      case BodyType.formData:
        // curl writes the multipart body, and its boundary, itself.
        formFields.addAll([for (final f in body.formFields) if (f.enabled && f.key.isNotEmpty) '${f.key}=${f.value}']);
    }
    if (contentType != null && !has('Content-Type')) headers['Content-Type'] = contentType;

    final lines = [
      'curl --location --request ${shellWord(snapshot.method.label)} ${shellQuote(url)}',
      for (final h in headers.entries) '--header ${shellQuote(h.value.isEmpty ? '${h.key};' : '${h.key}: ${h.value}')}',
      if (data != null) '--data-raw ${shellQuote(data)}',
      for (final field in formFields) '--form ${shellQuote(field)}',
    ];
    final note = switch (auth.type) {
      AuthType.basic || AuthType.digest || AuthType.awsSignatureV4 || AuthType.jwtBearer || AuthType.oauth2 =>
        '\n# ${auth.type.label} credentials are not part of History: add them before running this.',
      _ => '',
    };
    return '${shellLines(lines)}$note';
  }

  static Object? _variables(String text) {
    if (text.trim().isEmpty) return <String, Object?>{};
    try {
      return jsonDecode(text);
    } catch (_) {
      return <String, Object?>{};
    }
  }
}
