import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../safety/data/safety_prefs.dart';
import '../../../safety/domain/services/production_detector.dart';
import '../../domain/entities/environment_entity.dart';
import '../view_models/environments_view_model.dart';
import 'environments_manager_dialog.dart';

/// Dropdown value of the "No Environment" entry. Environment ids are
/// autoincrement and start at 1, so 0 can never collide with one.
const _noEnvironmentId = 0;

class EnvironmentSelector extends StatelessWidget {
  const EnvironmentSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<EnvironmentsViewModel>();
    final active = _activeOf(vm.environments);

    final colors = context.colors;
    final hasActive = active != null;
    // A production environment is drawn in red, so it is never mistaken for a safe one.
    final prefs = locator.isRegistered<SafetyPrefs>() ? locator<SafetyPrefs>() : null;
    final isProd = hasActive &&
        prefs != null &&
        prefs.confirmProductionWrites &&
        ProductionDetector.isProduction(active.name, extraWords: prefs.extraWords);
    final tint = isProd ? colors.statusError : colors.statusSuccess;
    // A pill: a status dot (lit while an environment is active), the picker,
    // and the manage button, so the control reads as one unit in the top bar.
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hasActive ? tint.withValues(alpha: isProd ? 0.8 : 0.55) : colors.border, width: isProd ? 1.4 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasActive ? tint : colors.secondaryText.withValues(alpha: 0.5),
              boxShadow: hasActive
                  ? [BoxShadow(color: tint.withValues(alpha: 0.5), blurRadius: 6)]
                  : null,
            ),
          ),
          if (isProd)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: colors.statusError, borderRadius: BorderRadius.circular(4)),
              child: const Text('PROD', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: DropdownButton<int>(
              isDense: true,
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              value: active?.id ?? _noEnvironmentId,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: _noEnvironmentId,
                  child: Text('No Environment', style: context.textStyles.caption, overflow: TextOverflow.ellipsis),
                ),
                for (final env in vm.environments)
                  DropdownMenuItem(
                    value: env.id,
                    child: Text(env.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return;
                if (id == _noEnvironmentId) {
                  vm.clearActive();
                } else {
                  vm.setActive(id);
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune, size: 18),
            tooltip: 'Manage environments',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(8),
            onPressed: () => EnvironmentsManagerDialog.show(context),
          ),
        ],
      ),
    );
  }

  EnvironmentEntity? _activeOf(List<EnvironmentEntity> environments) {
    for (final e in environments) {
      if (e.isActive) return e;
    }
    return null;
  }
}
