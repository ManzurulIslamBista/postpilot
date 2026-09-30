import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: DropdownButton<int>(
            isDense: true,
            isExpanded: true,
            value: active?.id ?? _noEnvironmentId,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(
                value: _noEnvironmentId,
                child: Text('No Environment', style: context.textStyles.caption, overflow: TextOverflow.ellipsis),
              ),
              for (final env in vm.environments)
                DropdownMenuItem(value: env.id, child: Text(env.name, overflow: TextOverflow.ellipsis)),
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
          icon: const Icon(Icons.settings_outlined, size: 18),
          tooltip: 'Manage environments',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
          onPressed: () => EnvironmentsManagerDialog.show(context),
        ),
      ],
    );
  }

  EnvironmentEntity? _activeOf(List<EnvironmentEntity> environments) {
    for (final e in environments) {
      if (e.isActive) return e;
    }
    return null;
  }
}
