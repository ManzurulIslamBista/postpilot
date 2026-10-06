import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../domain/entities/relogin_config.dart';
import '../view_models/relogin_section_view_model.dart';

/// The "Re-login on 401/403" part of the Auth tab of a collection or a folder: which request logs in
/// again when another one comes back rejected, which statuses count, and a "Test" that runs it. Edits go
/// into [RequestAuth.relogin], so they are saved with the auth they sit in. Needs a
/// [ReloginSectionViewModel] above it.
class ReloginSection extends StatelessWidget {
  final RequestAuth auth;
  final ValueChanged<RequestAuth> onChanged;
  final int collectionId;

  const ReloginSection({super.key, required this.auth, required this.onChanged, required this.collectionId});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReloginSectionViewModel>();
    final colors = context.colors;
    final config = auth.relogin;
    final names = {for (final c in vm.candidates) c.path};
    final missing = config != null && !vm.isLoading && !names.contains(config.request);

    void setConfig(ReloginConfig? next) {
      vm.clearResult();
      onChanged(auth.withRelogin(next));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Row(
          children: [
            Expanded(child: Text('Re-login on 401/403', style: context.textStyles.heading)),
            Switch(
              key: const ValueKey('relogin-switch'),
              value: config != null,
              onChanged: (on) => setConfig(on ? ReloginConfig(request: vm.likelyLogin?.path ?? '') : null),
            ),
          ],
        ),
        Text(
          'When a request here comes back rejected, run a login request of this collection first, then send the '
          'request again, once. The login request\'s extractors must save the variable the requests use for the token.',
          style: context.textStyles.caption.copyWith(color: colors.secondaryText),
        ),
        if (config != null) ...[
          const SizedBox(height: 12),
          if (vm.candidates.isEmpty && !vm.isLoading)
            Text(
              'This collection has no request yet. Add the login request, then choose it here.',
              style: context.textStyles.caption.copyWith(color: colors.statusWarning),
            )
          else
            DropdownButton<String>(
              key: const ValueKey('relogin-request'),
              isExpanded: true,
              value: names.contains(config.request) ? config.request : null,
              hint: const Text('Choose the login request'),
              onChanged: (path) => path == null ? null : setConfig(config.copyWith(request: path)),
              items: [
                for (final c in vm.candidates)
                  DropdownMenuItem(
                    value: c.path,
                    child: Text('${c.method.label}  ${c.path}', overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          if (missing && config.request.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No request is called "${config.request}" in this collection (renamed or deleted?). '
                'Choose the login request again.',
                style: context.textStyles.caption.copyWith(color: colors.statusError),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Run it on', style: context.textStyles.caption),
              for (final status in const [401, 403])
                FilterChip(
                  key: ValueKey('relogin-status-$status'),
                  label: Text('$status'),
                  selected: config.statuses.contains(status),
                  onSelected: (on) {
                    final next = {...config.statuses};
                    on ? next.add(status) : next.remove(status);
                    // A config with no status would never run; keep at least one.
                    if (next.isNotEmpty) setConfig(config.copyWith(statuses: next));
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('relogin-test'),
              onPressed: vm.isTesting || !config.isActive ? null : () => vm.test(collectionId, config),
              child: BusyLabel(busy: vm.isTesting, icon: Icons.play_arrow_outlined, label: 'Test', busyLabel: 'Testing…'),
            ),
          ),
          if (vm.testResult case final result?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(
                result.message,
                style: context.textStyles.caption.copyWith(color: result.ok ? colors.statusSuccess : colors.statusError),
              ),
            ),
        ],
      ],
    );
  }
}
