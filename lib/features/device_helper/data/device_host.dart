import '../domain/services/device_detector.dart';
import 'device_host_stub.dart' if (dart.library.io) 'device_host_io.dart' as platform;

/// The machine this app runs on: real programs, real environment variables, real files. A browser gets one that cannot run
/// anything, so the device section says so instead of failing.
DeviceHost systemDeviceHost() => platform.systemDeviceHost();

/// A detector for this machine.
DeviceDetector createSystemDeviceDetector() => DeviceDetector(systemDeviceHost());
