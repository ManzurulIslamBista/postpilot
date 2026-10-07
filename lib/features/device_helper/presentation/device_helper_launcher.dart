import 'package:flutter/widgets.dart';
import '../../../core/di/injector.dart';
import '../domain/services/device_detector.dart';
import 'device_helper_dialog.dart';

/// Opens the device helper with the app's own detector, so it lists the running emulators and phones as it opens. The dialog
/// itself does not reach for the service locator: opened without a detector it scans only when asked.
Future<void> openDeviceHelper(BuildContext context, {String initialUrl = '', int? initialPort}) => DeviceHelperDialog.show(
      context,
      initialUrl: initialUrl,
      initialPort: initialPort,
      detector: locator.isRegistered<DeviceDetector>() ? locator<DeviceDetector>() : null,
    );
