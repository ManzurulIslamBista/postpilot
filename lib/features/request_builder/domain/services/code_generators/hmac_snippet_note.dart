import '../../../../../core/enums/auth_type.dart';
import '../../entities/request_auth.dart';
import '../hmac_signer.dart';

/// The comment a code snippet gets at its end when its HMAC signature covers a timestamp read from the clock:
/// the signature in the snippet belongs to the moment it was generated, so a receiver that checks the age of
/// the timestamp (Stripe and Slack do) rejects it a few minutes later. A snippet whose signature does not
/// depend on the time (GitHub, Shopify, or a fixed timestamp) gets no comment.
abstract final class HmacSnippetNote {
  static const text = 'HMAC signature: it covers the time this snippet was generated, so it only stays valid for a '
      'few minutes. Sign again for each call.';

  /// [snippet] with the note appended as a comment of the language [generatorId] writes, when [auth] needs it.
  static String append(String snippet, String generatorId, RequestAuth auth) {
    if (!needed(auth)) return snippet;
    final line = '${_prefix(generatorId)} $text';
    return snippet.endsWith('\n') ? '$snippet$line\n' : '$snippet\n$line';
  }

  /// Whether the signature [auth] makes changes with the clock.
  static bool needed(RequestAuth auth) =>
      auth.type == AuthType.hmac &&
      auth.hmacTimestampSource == HmacTimestampSource.now &&
      HmacSigner(
        secret: '',
        payloadTemplate: auth.hmacPayloadTemplate,
        headerTemplate: auth.hmacHeaderTemplate,
        timestampHeader: auth.hmacTimestampHeader,
      ).usesTimestamp;

  static String _prefix(String generatorId) => switch (generatorId) {
        'csharp_httpclient' ||
        'dart_http' ||
        'go_net_http' ||
        'java_okhttp' ||
        'javascript_fetch' ||
        'kotlin_okhttp' ||
        'nodejs_axios' ||
        'rust_reqwest' ||
        'swift_urlsession' =>
          '//',
        _ => '#', // shells, Python, Ruby, R, PHP, PowerShell
      };
}
