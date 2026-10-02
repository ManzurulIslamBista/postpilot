import 'dart:io';
import 'network_info.dart';

Future<List<LocalAddress>> listLocalAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final found = <LocalAddress>[
      for (final i in interfaces)
        for (final a in i.addresses)
          // 169.254.x.x means "no network": not an address anyone can reach.
          if (!a.address.startsWith('169.254.')) LocalAddress(i.name, a.address),
    ];
    // Real adapters first; Docker, WSL, VPN and VM adapters last.
    int rank(LocalAddress a) {
      final n = a.adapter.toLowerCase();
      if (RegExp(r'vethernet|docker|wsl|virtual|vmware|vbox|hyper-v|tun|tap|vpn|utun|bridge').hasMatch(n)) return 2;
      if (RegExp(r'wi-?fi|wlan|wireless|en0|eth|ethernet|en1').hasMatch(n)) return 0;
      return 1;
    }

    found.sort((a, b) => rank(a).compareTo(rank(b)));
    return found;
  } catch (_) {
    return const [];
  }
}
