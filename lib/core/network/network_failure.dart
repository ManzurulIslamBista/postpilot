import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../errors/unreachable_message.dart';
import 'api_http_response.dart';

/// Tells a failed send in one line, by what the failure says: Dio and `dart:io`
/// report a refused connection, a missing host, a TLS problem or a dropped
/// download all as a generic network error whose cause sits in the text of the
/// wrapped exception. The exceptions of `dart:io` cannot be named here (the
/// web build compiles this file too), so they are told apart by that text.
abstract final class NetworkFailure {
  static const certificateHint = 'If you trust this server, turn off "Verify SSL certificates" in Settings.';

  static const _timeoutHint =
      'Raise the "Request timeout" in Settings (or in this request\'s Settings tab) if the server is just slow.';

  /// A TLS failure over a certificate the platform does not trust.
  static bool isCertificateProblem(DioException e) {
    if (e.type == DioExceptionType.badCertificate) return true;
    final cause = '${e.error}';
    return cause.contains('CERTIFICATE_VERIFY_FAILED') || cause.contains('HandshakeException');
  }

  /// The one line shown to the user for [e], which came from sending a request
  /// with [options]. Names the host (never the URL, which can hold a secret).
  static String summarize(DioException e, ApiRequestOptions options, {bool web = kIsWeb}) {
    final uri = e.requestOptions.uri;
    final proxied = !web && options.proxy.isUsableCustom && !options.proxy.bypasses(uri);
    final role = proxied ? 'proxy' : 'server';
    final host = proxied ? options.proxy.host : uri.host;
    final authority = proxied ? '${options.proxy.host}:${options.proxy.port}' : _authority(uri);
    final cause = '${e.error ?? e.message ?? ''}';

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        final limit = _limit(options.timeout);
        return limit == null
            ? 'The connection to $authority timed out — the $role may be down or blocked by a firewall.'
            : 'Could not connect to $authority within $limit — the $role may be down or blocked by a firewall. '
                '$_timeoutHint';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        final limit = _limit(options.timeout);
        return limit == null
            ? 'The $role at $authority took too long to answer.'
            : 'The $role at $authority did not answer within $limit. $_timeoutHint';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      case DioExceptionType.badCertificate:
        return _tls(authority, cause, options);
      case DioExceptionType.badResponse:
        return 'The $role at $authority returned a response that could not be read.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        break;
    }

    if (_has(cause, _memory)) {
      return 'The response from $authority is too large to hold in memory — set a "Max response size" in Settings '
          'so that it is cut off instead.';
    }
    if (isCertificateProblem(e) || _has(cause, _tlsMarkers)) return _tls(authority, cause, options);
    if (_has(cause, _dns)) {
      return 'Couldn\'t find the $role "$host" — check the spelling of the host name, and your network, DNS or VPN.';
    }
    if (_has(cause, _refused)) {
      return 'The $role at $authority refused the connection — check that it is running and that the port is right.';
    }
    if (_has(cause, _closedEarly)) {
      return 'The $role at $authority closed the connection without answering — it may have crashed, or the URL uses '
          'https where it expects http (or the other way round).';
    }
    if (_has(cause, _closedMidBody)) {
      return 'The $role at $authority closed the connection before the whole response arrived.';
    }
    if (_has(cause, _reset)) {
      return 'The $role at $authority dropped the connection — it may have crashed, or a firewall or proxy cut it off.';
    }
    if (_has(cause, _unreachable)) {
      return '$authority can\'t be reached from this network — check your connection, VPN or proxy.';
    }
    if (_has(cause, _decode)) {
      return 'The response from $authority could not be decoded (corrupt or wrongly compressed body).';
    }
    if (cause.toLowerCase().contains('formatexception')) return 'The URL could not be read — ${_firstLine(cause)}';
    if (e.type == DioExceptionType.connectionError) {
      return web ? unreachableServerMessage(web: true) : 'Couldn\'t reach the $role at $authority — ${_firstLine(cause)}';
    }
    return 'The request failed: ${_firstLine(cause.isEmpty ? 'unknown error' : cause)}';
  }

  /// The hint about "Verify SSL certificates" is only useful while it is on.
  static String _tls(String authority, String cause, ApiRequestOptions options) {
    if (_has(cause, _wrongProtocol)) {
      return 'The server at $authority doesn\'t speak HTTPS on this port — try http:// in the URL, or check the port.';
    }
    final hint = options.verifySsl ? ' $certificateHint' : '';
    final reason = _certificateReason(cause);
    return reason == null
        ? 'The secure connection to $authority could not be set up (TLS handshake failed).$hint'
        : 'The secure connection to $authority failed: $reason.$hint';
  }

  /// `CERTIFICATE_VERIFY_FAILED: self signed certificate(handshake.cc:393)` and
  /// its siblings, reworded.
  static String? _certificateReason(String cause) {
    final lower = cause.toLowerCase();
    if (lower.contains('hostname mismatch') || lower.contains('host name mismatch')) {
      return 'the certificate was issued for a different host name';
    }
    if (lower.contains('expired')) return 'the server\'s certificate has expired';
    if (lower.contains('self signed') || lower.contains('self-signed')) return 'the server\'s certificate is self-signed';
    if (lower.contains('unable to get local issuer') || lower.contains('unable to verify')) {
      return 'the server\'s certificate was issued by an authority this device does not trust';
    }
    if (lower.contains('certificate_verify_failed') || lower.contains('bad certificate')) {
      return 'the server\'s certificate could not be verified';
    }
    return null;
  }

  static String _authority(Uri uri) {
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    return uri.hasPort && uri.port != defaultPort ? '$host:${uri.port}' : host;
  }

  /// The configured timeout as the user typed it in Settings; null when there
  /// is none, so an operating-system timeout is not blamed on a number that
  /// was never set.
  static String? _limit(Duration? timeout) {
    if (timeout == null || timeout <= Duration.zero) return null;
    final ms = timeout.inMilliseconds;
    if (ms < 1000) return '$ms ms';
    final seconds = ms / 1000;
    final text = seconds == seconds.roundToDouble() ? '${seconds.round()}' : seconds.toStringAsFixed(1);
    return text == '1' ? '1 second' : '$text seconds';
  }

  static String _firstLine(String text) {
    final line = text.trim().split(RegExp(r'[\r\n]+')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return line.length > 160 ? '${line.substring(0, 157)}...' : line;
  }

  static bool _has(String cause, List<String> needles) {
    final lower = cause.toLowerCase();
    return needles.any((n) => lower.contains(n));
  }

  // Wording of `dart:io` on Linux, macOS and Windows (the Windows system
  // messages are the long ones), all lowercase.
  static const _dns = [
    'failed host lookup',
    'no address associated with hostname',
    'nodename nor servname',
    'name or service not known',
    'temporary failure in name resolution',
    'no such host is known',
  ];
  static const _refused = ['connection refused', 'refused the network connection', 'actively refused'];
  static const _closedEarly = ['connection closed before full header was received'];
  static const _closedMidBody = ['connection closed while receiving data'];
  static const _reset = ['connection reset', 'forcibly closed', 'broken pipe'];
  static const _unreachable = ['network is unreachable', 'no route to host', 'unreachable network', 'network is down'];
  static const _wrongProtocol = ['wrong_version_number', 'wrong version number', 'packet length too long'];
  static const _tlsMarkers = ['handshakeexception', 'tlsexception', 'handshake error', 'certificate_verify_failed'];
  static const _decode = ['filter error', 'incorrect header check', 'invalid block type', 'invalid distance'];
  static const _memory = ['out of memory', 'outofmemory'];
}
