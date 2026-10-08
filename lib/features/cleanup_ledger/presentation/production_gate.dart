import 'package:flutter/widgets.dart';
import '../../../core/di/injector.dart';
import '../../safety/domain/services/production_guard.dart';
import '../../safety/presentation/production_confirm_dialog.dart';
import '../domain/services/cleanup_executor.dart';

/// The production lock for a cleanup: asks once, about every request that is about to go out, with the dialog the
/// request builder and the runner use. A delete is destructive, so while the active environment (or the host) is
/// production it is always asked about, even after "don't ask again" for ordinary writes.
///
/// False when the person says no, or when [context] is gone by the time the answer is needed: nothing is sent then.
CleanupGate productionGate(BuildContext context, {String what = 'the cleanup'}) => (requests) async {
      final guard = locator.isRegistered<ProductionGuard>() ? locator<ProductionGuard>() : null;
      if (guard == null) return true;
      final warning = await guard.checkRunRequests(requests, what);
      if (warning == null) return true;
      if (!context.mounted) return false;
      return confirmProductionSend(context, warning, onSilence: () => guard.silenceForSession(warning.environmentName));
    };
