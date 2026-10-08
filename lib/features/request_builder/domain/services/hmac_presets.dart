import '../../../../core/enums/auth_type.dart';
import '../entities/request_auth.dart';

/// What a webhook preset fills into an [AuthType.hmac] auth: everything but the secret and the timestamp
/// source, which are the user's own.
final class HmacPresetSettings {
  final HmacAlgorithm algorithm;
  final HmacEncoding encoding;
  final String payloadTemplate;
  final String headerName;
  final String headerTemplate;
  final String timestampHeader;

  const HmacPresetSettings({
    this.algorithm = HmacAlgorithm.sha256,
    this.encoding = HmacEncoding.hex,
    required this.payloadTemplate,
    required this.headerName,
    required this.headerTemplate,
    this.timestampHeader = '',
  });
}

/// The documented signing schemes of the services that send webhooks. A preset only pre-fills the fields of
/// an auth; once they are filled the user may edit them, and [HmacPreset.generic] keeps what is there.
abstract final class HmacPresets {
  /// `X-Hub-Signature-256: sha256=<hex HMAC-SHA256 of the body>`.
  static const github = HmacPresetSettings(
    payloadTemplate: '{body}',
    headerName: 'X-Hub-Signature-256',
    headerTemplate: 'sha256={signature}',
  );

  /// `Stripe-Signature: t=<timestamp>,v1=<hex HMAC-SHA256 of "<timestamp>.<body>">`.
  static const stripe = HmacPresetSettings(
    payloadTemplate: '{timestamp}.{body}',
    headerName: 'Stripe-Signature',
    headerTemplate: 't={timestamp},v1={signature}',
  );

  /// `X-Shopify-Hmac-Sha256: <base64 HMAC-SHA256 of the body>`.
  static const shopify = HmacPresetSettings(
    encoding: HmacEncoding.base64,
    payloadTemplate: '{body}',
    headerName: 'X-Shopify-Hmac-Sha256',
    headerTemplate: '{signature}',
  );

  /// `X-Slack-Signature: v0=<hex HMAC-SHA256 of "v0:<timestamp>:<body>">` together with
  /// `X-Slack-Request-Timestamp: <timestamp>`.
  static const slack = HmacPresetSettings(
    payloadTemplate: 'v0:{timestamp}:{body}',
    headerName: 'X-Slack-Signature',
    headerTemplate: 'v0={signature}',
    timestampHeader: 'X-Slack-Request-Timestamp',
  );

  /// The settings of [preset]; null for [HmacPreset.generic], which has none of its own.
  static HmacPresetSettings? of(HmacPreset preset) => switch (preset) {
        HmacPreset.github => github,
        HmacPreset.stripe => stripe,
        HmacPreset.shopify => shopify,
        HmacPreset.slack => slack,
        HmacPreset.generic => null,
      };

  /// [auth] with [preset] chosen and its fields filled in. The secret and the timestamp source are kept, and
  /// so are all fields when [preset] is [HmacPreset.generic] ("keep what I have, I will edit it").
  static RequestAuth apply(RequestAuth auth, HmacPreset preset) {
    final settings = of(preset);
    if (settings == null) return auth.copyWith(hmacPreset: preset);
    return auth.copyWith(
      hmacPreset: preset,
      hmacAlgorithm: settings.algorithm,
      hmacEncoding: settings.encoding,
      hmacPayloadTemplate: settings.payloadTemplate,
      hmacHeaderName: settings.headerName,
      hmacHeaderTemplate: settings.headerTemplate,
      hmacTimestampHeader: settings.timestampHeader,
    );
  }

  /// Whether the fields of [auth] are exactly the ones [preset] fills in; any auth matches
  /// [HmacPreset.generic].
  static bool matches(HmacPreset preset, RequestAuth auth) {
    final settings = of(preset);
    if (settings == null) return true;
    return auth.hmacAlgorithm == settings.algorithm &&
        auth.hmacEncoding == settings.encoding &&
        auth.hmacPayloadTemplate == settings.payloadTemplate &&
        auth.hmacHeaderName == settings.headerName &&
        auth.hmacHeaderTemplate == settings.headerTemplate &&
        auth.hmacTimestampHeader == settings.timestampHeader;
  }

  /// [auth] with its preset set back to [HmacPreset.generic] when an edit took its fields away from the
  /// preset it was started from, so the name shown never claims a scheme the fields no longer are.
  static RequestAuth settled(RequestAuth auth) =>
      auth.hmacPreset == HmacPreset.generic || matches(auth.hmacPreset, auth)
          ? auth
          : auth.copyWith(hmacPreset: HmacPreset.generic);
}
