import '../../../../core/network/api_http_response.dart';
import '../entities/effective_request_options.dart';
import '../repositories/settings_repository.dart';

/// How a developer tool's own call (an Odoo search, a GraphQL introspection, a
/// question to the AI) is sent: with the app's timeout, redirect, TLS-verification
/// and proxy settings, exactly as a saved request is. Without them such a call
/// would ignore the proxy a company network needs or the "do not verify
/// certificates" a local server needs, while the same request in a tab works.
abstract final class ToolRequestOptions {
  /// The options for a tool call.
  ///
  /// [maxResponseBytes] is the tool's own ceiling (it keeps the whole body in memory); a
  /// smaller cap in the settings still wins. [minTimeout] is for a call that is slow by
  /// nature: the setting is raised to it, except that "wait forever" stays that.
  /// [settings] null gives the defaults of [ApiRequestOptions].
  static ApiRequestOptions resolve(
    SettingsRepository? settings, {
    int? maxResponseBytes,
    Duration? minTimeout,
  }) {
    final base = settings == null
        ? const ApiRequestOptions()
        : EffectiveRequestOptions.resolve(settings.current, null).toApiOptions();
    final timeout = base.timeout;
    final cap = base.maxResponseBytes;
    return ApiRequestOptions(
      timeout: timeout != null && minTimeout != null && timeout < minTimeout ? minTimeout : timeout,
      followRedirects: base.followRedirects,
      maxRedirects: base.maxRedirects,
      verifySsl: base.verifySsl,
      proxy: base.proxy,
      maxResponseBytes: switch ((cap, maxResponseBytes)) {
        (final c?, final m?) => c < m ? c : m,
        (final c?, null) => c,
        (null, final m) => m,
      },
    );
  }
}
