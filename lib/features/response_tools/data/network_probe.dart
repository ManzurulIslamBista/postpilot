import 'network_probe_stub.dart' if (dart.library.io) 'network_probe_io.dart' as platform;

/// How long each step of opening a connection to a server takes right now.
final class NetworkProbe {
  final String host;
  final int port;
  final String? ip;
  final Duration dns;
  final Duration tcp;

  /// Null for plain http.
  final Duration? tls;
  final String? tlsVersion;

  const NetworkProbe({required this.host, required this.port, required this.ip, required this.dns, required this.tcp, this.tls, this.tlsVersion});

  Duration get total => dns + tcp + (tls ?? Duration.zero);
}

/// Opens a separate connection to [url]'s server and times DNS, TCP and TLS.
/// It is not the connection the request used (that one may have been reused),
/// so it estimates what a cold request pays. Null where the platform cannot
/// open sockets (a browser) or the host cannot be reached.
Future<NetworkProbe?> probeNetwork(Uri url, {Duration timeout = const Duration(seconds: 10)}) => platform.probeNetwork(url, timeout: timeout);

bool get canProbeNetwork => platform.canProbeNetwork;
