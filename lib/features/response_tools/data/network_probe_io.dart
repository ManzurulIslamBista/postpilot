import 'dart:io';
import 'network_probe.dart';

bool get canProbeNetwork => true;

Future<NetworkProbe?> probeNetwork(Uri url, {required Duration timeout}) async {
  final host = url.host;
  if (host.isEmpty) return null;
  final secure = url.scheme == 'https';
  final port = url.hasPort ? url.port : (secure ? 443 : 80);
  final clock = Stopwatch()..start();

  final addresses = await InternetAddress.lookup(host).timeout(timeout);
  if (addresses.isEmpty) return null;
  final dns = clock.elapsed;
  // Prefer IPv4: it is what most servers answer fastest, and a missing IPv6 route would time out.
  final address = addresses.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => addresses.first);

  clock
    ..reset()
    ..start();
  final socket = await Socket.connect(address, port, timeout: timeout);
  final tcp = clock.elapsed;

  Duration? tls;
  String? tlsVersion;
  try {
    if (secure) {
      clock
        ..reset()
        ..start();
      final secured = await SecureSocket.secure(socket, host: host).timeout(timeout);
      tls = clock.elapsed;
      tlsVersion = secured.selectedProtocol;
      await secured.close();
    }
  } finally {
    socket.destroy();
  }
  return NetworkProbe(host: host, port: port, ip: address.address, dns: dns, tcp: tcp, tls: tls, tlsVersion: tlsVersion);
}
