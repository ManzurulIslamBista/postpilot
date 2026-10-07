import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../entities/recorded_exchange.dart';

/// What of a recorded exchange may be shown, copied or saved. The live view holds the real values; everything that leaves it
/// (a cURL command, a HAR file, a saved collection) goes through here, with the app's own [SecretMasker] and [SecretNames].
abstract final class TrafficMasking {
  /// Request headers a cURL command or a HAR file does not need: the connection's own, and the ones the recorder sets again.
  static const transportHeaders = {
    'host',
    'content-length',
    'connection',
    'accept-encoding',
    'keep-alive',
    'transfer-encoding',
    'upgrade',
    'te',
    'trailer',
    'expect',
    'proxy-connection',
    'proxy-authorization',
  };

  /// [value] of the header [name] with a credential masked (`Bearer ••••••`).
  static String headerValue(String name, String value) =>
      SecretMasker.maskValue(SecretNames.isSecretHeader(name) && !SecretMasker.isSensitiveName(name) ? 'authorization' : name, value);

  /// [headers] without the transport ones when [dropTransport], credentials masked unless [reveal].
  static List<RecordedHeader> headers(List<RecordedHeader> headers, {bool reveal = false, bool dropTransport = false}) => [
        for (final h in headers)
          if (!dropTransport || !transportHeaders.contains(h.name.toLowerCase()))
            RecordedHeader(h.name, reveal ? h.value : headerValue(h.name, h.value)),
      ];

  /// An address with a password in it and the value of secret query parameters masked.
  static String url(String url, {bool reveal = false}) => reveal ? url : SecretMasker.maskUrl(url);

  /// A body with credentials masked (JSON fields, form fields, XML, known token shapes).
  static String body(String text, {bool reveal = false}) => reveal ? text : SecretMasker.maskBody(text);

  /// A header value, URL or body is a credential that has to be hidden.
  static bool isSecretHeader(String name) => SecretNames.isSecretHeader(name) || SecretMasker.isSensitiveName(name);
}
