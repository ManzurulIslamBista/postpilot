import '../../../device_helper/data/network_info.dart';

/// Which of this computer's network addresses a phone on the same Wi-Fi can really use. The device helper lists every
/// adapter (Docker, WSL, VPN and VM ones last); a recorder that shows a QR code or a URL must not offer those first, because
/// a phone cannot reach them.
abstract final class RecorderAddresses {
  /// Adapter names of virtual and tunnel interfaces on Windows, macOS and Linux.
  static final _virtualAdapter = RegExp(
    r'vethernet|docker|wsl|virtual|vmware|vmnet|vbox|hyper-v|loopback|\btun\d*\b|\btap\d*\b|utun|vpn|bridge|tailscale|'
    r'zerotier|hamachi|wireguard|npcap|bluetooth|isatap|teredo|pseudo|veth|virbr|^br-|awdl|llw\d|anpi',
    caseSensitive: false,
  );
  static final _wifiOrEthernet = RegExp(r'wi-?fi|wlan|wireless|wlp|en0|en1|^eth|ethernet|enp|eno', caseSensitive: false);

  /// [all] without the addresses a phone cannot reach (virtual adapters, tunnels, carrier-grade NAT such as Tailscale's
  /// `100.64.0.0/10`, link-local), real Wi-Fi and Ethernet first and private ranges before the rest. When filtering would
  /// leave nothing, every address that is not link-local is returned instead, so the person still sees something to try.
  static List<LocalAddress> usable(List<LocalAddress> all) {
    final reachable = [
      for (final a in all)
        if (!_isLinkLocal(a.ip)) a,
    ];
    final real = [
      for (final a in reachable)
        if (!_virtualAdapter.hasMatch(a.adapter) && !_isCarrierGradeNat(a.ip)) a,
    ];
    final chosen = real.isEmpty ? reachable : real;
    // Ties keep the order the system listed them in (List.sort is not stable).
    final indexed = [for (var i = 0; i < chosen.length; i++) (index: i, address: chosen[i])]
      ..sort((a, b) {
        final byRank = _rank(a.address).compareTo(_rank(b.address));
        return byRank != 0 ? byRank : a.index.compareTo(b.index);
      });
    return [for (final entry in indexed) entry.address];
  }

  /// This computer's addresses a phone could use, best first; empty where the platform cannot say (a browser).
  static Future<List<LocalAddress>> lookup() async => usable(await listLocalAddresses());

  static int _rank(LocalAddress a) {
    final adapter = _wifiOrEthernet.hasMatch(a.adapter) ? 0 : 2;
    final privateRange = _isPrivate(a.ip) ? 0 : 1;
    return adapter + privateRange;
  }

  static List<int>? _octets(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final n = [for (final p in parts) int.tryParse(p)];
    return n.any((o) => o == null || o < 0 || o > 255) ? null : [for (final o in n) o!];
  }

  static bool _isLinkLocal(String ip) {
    final o = _octets(ip);
    return o != null && o[0] == 169 && o[1] == 254;
  }

  static bool _isCarrierGradeNat(String ip) {
    final o = _octets(ip);
    return o != null && o[0] == 100 && o[1] >= 64 && o[1] <= 127;
  }

  static bool _isPrivate(String ip) {
    final o = _octets(ip);
    if (o == null) return false;
    return o[0] == 10 || (o[0] == 192 && o[1] == 168) || (o[0] == 172 && o[1] >= 16 && o[1] <= 31);
  }
}
