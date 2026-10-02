import 'network_probe.dart';

bool get canProbeNetwork => false;

Future<NetworkProbe?> probeNetwork(Uri url, {required Duration timeout}) async => null;
