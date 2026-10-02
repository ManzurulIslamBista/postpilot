import 'network_info_stub.dart' if (dart.library.io) 'network_info_io.dart' as platform;

/// An address other devices on the same network can use to reach this computer.
final class LocalAddress {
  /// The network adapter, e.g. "Wi-Fi" or "Ethernet".
  final String adapter;
  final String ip;
  const LocalAddress(this.adapter, this.ip);
}

/// This computer's IPv4 addresses on the local network, best guesses first
/// (Wi-Fi and Ethernet before virtual adapters). Empty where the platform
/// cannot say (a browser).
Future<List<LocalAddress>> listLocalAddresses() => platform.listLocalAddresses();
