import '../../../device_helper/data/network_info.dart';
import '../../../device_helper/domain/services/device_targets.dart';

/// One way an app can reach the running recorder, for one kind of device.
final class RecorderConnectOption {
  final String label;

  /// The base URL to put in the app (`http://10.0.2.2:8099`); for [command] options the one to use after the command ran.
  final String url;
  final String note;

  /// A shell command that has to run first (`adb reverse ...`), null when none.
  final String? command;

  /// False while the option cannot work yet (a phone on the network needs "also reachable from other devices").
  final bool available;

  const RecorderConnectOption({
    required this.label,
    required this.url,
    required this.note,
    this.command,
    this.available = true,
  });
}

/// The addresses to give the app, for every kind of device, in the order most developers need them.
abstract final class RecorderConnect {
  /// The options for a recorder listening on [port]. [addresses] are this computer's network addresses (see
  /// `RecorderAddresses.usable`); [allowOtherDevices] says whether it listens on all interfaces.
  static List<RecorderConnectOption> options({
    required int port,
    required bool allowOtherDevices,
    required List<LocalAddress> addresses,
  }) =>
      [
        RecorderConnectOption(
          label: 'This computer',
          url: 'http://localhost:$port',
          note: 'Desktop and web apps, the iOS simulator.',
        ),
        RecorderConnectOption(
          label: 'Android emulator',
          url: 'http://10.0.2.2:$port',
          note: "The emulator's alias for this computer. Genymotion uses 10.0.3.2.",
        ),
        RecorderConnectOption(
          label: 'Phone over USB',
          url: 'http://localhost:$port',
          command: DeviceTargets.adbReverse(port),
          note: 'Run the command once (USB debugging on), then the phone reaches this computer as localhost.',
        ),
        if (addresses.isEmpty)
          RecorderConnectOption(
            label: 'Phone on the same Wi-Fi',
            url: '',
            available: false,
            note: 'No network address found. Connect this computer to the Wi-Fi or Ethernet the phone uses.',
          )
        else
          for (final a in addresses)
            RecorderConnectOption(
              label: 'Phone on the same Wi-Fi (${a.adapter})',
              url: 'http://${a.ip}:$port',
              available: allowOtherDevices,
              note: allowOtherDevices
                  ? 'The phone and this computer must be on the same network, and the firewall must allow port $port.'
                  : 'Switch on "Also reachable from phones on my network" and start the recorder again.',
            ),
      ];

  /// The URL to show first: the network address when the recorder listens for other devices, localhost otherwise.
  static String primaryUrl({required int port, required bool allowOtherDevices, required List<LocalAddress> addresses}) {
    if (allowOtherDevices && addresses.isNotEmpty) return 'http://${addresses.first.ip}:$port';
    return 'http://localhost:$port';
  }
}
