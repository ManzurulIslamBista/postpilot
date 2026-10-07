import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/info_banner.dart';
import '../../environments/domain/entities/environment_entity.dart';
import '../../environments/presentation/view_models/environments_view_model.dart';
import '../domain/services/connected_device.dart';
import '../domain/services/device_detector.dart';
import '../domain/services/device_url_planner.dart';

/// The emulators, simulators and phones that are running right now, found with adb and simctl, each with a button that points an
/// environment variable at the right host for it (and sets up `adb reverse` for a phone). The change is shown before it is made
/// and can be undone.
class RunningDevicesSection extends StatefulWidget {
  final DeviceDetector detector;

  /// Where the variables to change live; without it the devices are listed and nothing can be applied.
  final EnvironmentsViewModel? environments;

  /// This computer's address on the local network, for a phone when adb reverse is not wanted.
  final String? lanIp;

  /// Scan as soon as the section opens.
  final bool autoScan;

  const RunningDevicesSection({super.key, required this.detector, this.environments, this.lanIp, this.autoScan = true});

  @override
  State<RunningDevicesSection> createState() => _RunningDevicesSectionState();
}

/// What was changed, so it can be put back.
final class _Applied {
  final EnvironmentVariableEntity before;
  final String environmentName;
  final String after;
  final ConnectedDevice device;
  final int? reversePort;
  final bool reverseCreated;

  const _Applied({
    required this.before,
    required this.environmentName,
    required this.after,
    required this.device,
    required this.reversePort,
    required this.reverseCreated,
  });
}

class _RunningDevicesSectionState extends State<RunningDevicesSection> {
  DeviceScanResult? _result;
  bool _scanning = false;
  bool _applying = false;
  int? _environmentId;
  String? _variableKey;
  bool _useReverse = true;
  _Applied? _applied;
  String? _error;

  EnvironmentsViewModel? get _vm => widget.environments;

  @override
  void initState() {
    super.initState();
    _vm?.addListener(_onEnvironments);
    if (widget.autoScan && widget.detector.isSupported) _scan();
  }

  @override
  void dispose() {
    _vm?.removeListener(_onEnvironments);
    super.dispose();
  }

  void _onEnvironments() {
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    final result = await widget.detector.scan();
    if (!mounted) return;
    setState(() {
      _result = result;
      _scanning = false;
    });
  }

  EnvironmentEntity? get _environment {
    final all = _vm?.environments ?? const <EnvironmentEntity>[];
    if (all.isEmpty) return null;
    return all.where((e) => e.id == _environmentId).firstOrNull ?? all.where((e) => e.isActive).firstOrNull ?? all.first;
  }

  /// The variables of the chosen environment that hold an address a device could be pointed at.
  List<EnvironmentVariableEntity> get _addressVariables {
    final env = _environment;
    if (env == null) return const [];
    _vm!.watchVariables(env.id);
    return [
      for (final v in _vm!.variablesFor(env.id))
        if (v.enabled && !v.isSecret && v.key.trim().isNotEmpty && DeviceUrlPlanner.looksLikeAddress(v.value)) v,
    ];
  }

  EnvironmentVariableEntity? get _variable {
    final all = _addressVariables;
    return all.where((v) => v.key == _variableKey).firstOrNull ?? all.where((v) => v.key == 'baseUrl').firstOrNull ?? all.firstOrNull;
  }

  Future<void> _use(ConnectedDevice device) async {
    final env = _environment;
    final variable = _variable;
    if (env == null || variable == null) return;
    final plan = DeviceUrlPlanner.plan(device, variable.value, useReverse: _useReverse, lanIp: widget.lanIp);
    if (!plan.ok) {
      setState(() => _error = plan.error);
      return;
    }
    setState(() => _error = null);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangeDialog(plan: plan, environmentName: env.name, variableKey: variable.key),
    );
    if (accepted != true || !mounted) return;
    setState(() => _applying = true);
    var reverseCreated = false;
    if (plan.reversePort != null) {
      final outcome = await widget.detector.reverse(device.id, plan.reversePort!);
      if (!mounted) return;
      if (!outcome.ok) {
        setState(() {
          _applying = false;
          _error = '${outcome.message} Nothing was changed.';
        });
        return;
      }
      reverseCreated = outcome.createdByUs;
    }
    await _vm!.upsertVariable(EnvironmentVariableEntity(
      id: variable.id,
      environmentId: variable.environmentId,
      key: variable.key,
      value: plan.after!,
      isSecret: variable.isSecret,
      enabled: variable.enabled,
    ));
    if (!mounted) return;
    setState(() {
      _applying = false;
      _applied = _Applied(
        before: variable,
        environmentName: env.name,
        after: plan.after!,
        device: device,
        reversePort: plan.reversePort,
        reverseCreated: reverseCreated,
      );
    });
  }

  Future<void> _undo() async {
    final applied = _applied;
    if (applied == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final current = _vm!.variablesFor(applied.before.environmentId).where((v) => v.id == applied.before.id).firstOrNull;
    if (current != null && current.value != applied.after) {
      messenger.showSnackBar(SnackBar(content: Text('${applied.before.key} was edited since, so it was left as it is.')));
      setState(() => _applied = null);
      return;
    }
    await _vm!.upsertVariable(applied.before);
    var note = 'Put ${applied.before.key} back to ${applied.before.value}.';
    final port = applied.reversePort;
    if (port != null && applied.reverseCreated) {
      final removed = await widget.detector.removeReverse(applied.device.id, port);
      note += removed ? ' adb reverse for port $port was removed.' : ' adb reverse for port $port could not be removed.';
    }
    if (!mounted) return;
    setState(() => _applied = null);
    messenger.showSnackBar(SnackBar(content: Text(note)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detector = widget.detector;
    if (!detector.isSupported) {
      return const ToolSection(
        title: 'Running devices',
        child: InfoBanner(
          message: 'Finding running emulators and phones needs the desktop app: a browser cannot run adb or simctl. '
              'Use the addresses and commands below instead.',
        ),
      );
    }
    final result = _result;
    final env = _environment;
    final variable = _variable;
    final variables = _addressVariables;
    final devices = result?.devices ?? const <ConnectedDevice>[];
    return ToolSection(
      title: 'Running devices',
      hint: 'Found with adb${detector.scansIos ? ' and xcrun simctl' : ''}. Pick one to point an environment variable at it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _scanning ? null : _scan,
                child: BusyLabel(busy: _scanning, label: result == null ? 'Scan for devices' : 'Scan again', busyLabel: 'Scanning…', icon: Icons.refresh, iconSize: 16),
              ),
              if (result?.adbPath != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text('adb: ${result!.adbPath}', style: context.textStyles.caption.copyWith(color: colors.secondaryText), overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
          if (result?.adbProblem != null) ...[
            const SizedBox(height: 10),
            InfoBanner(key: const ValueKey('adb-problem'), kind: BannerKind.warning, message: result!.adbProblem!),
          ],
          if (result?.simctlProblem != null) ...[
            const SizedBox(height: 10),
            InfoBanner(key: const ValueKey('simctl-problem'), kind: BannerKind.warning, message: result!.simctlProblem!),
          ],
          if (result != null && !result.scannedIos) ...[
            const SizedBox(height: 6),
            Text('iOS simulators are listed on a Mac only.', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
          ],
          if (result != null && devices.isEmpty && result.adbProblem == null) ...[
            const SizedBox(height: 10),
            Text(
              'No running emulator, simulator or phone found. Start an emulator, or plug in a phone with USB debugging on, then scan again.',
              key: const ValueKey('no-devices'),
              style: context.textStyles.caption.copyWith(color: colors.secondaryText),
            ),
          ],
          if (devices.isNotEmpty) ...[
            const SizedBox(height: 12),
            _target(context, env, variable, variables),
            const SizedBox(height: 6),
            for (final d in devices) _deviceRow(context, d, env, variable),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            InfoBanner(key: const ValueKey('device-error'), kind: BannerKind.error, message: _error!),
          ],
          if (_applied != null) ...[
            const SizedBox(height: 10),
            InfoBanner(
              key: const ValueKey('device-applied'),
              kind: BannerKind.success,
              title: 'Changed ${_applied!.before.key} in ${_applied!.environmentName}',
              message: '${_applied!.before.value}  ->  ${_applied!.after}',
              trailing: TextButton(onPressed: _undo, child: const Text('Undo')),
            ),
          ],
        ],
      ),
    );
  }

  /// Which environment and variable the buttons change, and how a phone is reached.
  Widget _target(BuildContext context, EnvironmentEntity? env, EnvironmentVariableEntity? variable, List<EnvironmentVariableEntity> variables) {
    final colors = context.colors;
    final vm = _vm;
    if (vm == null || env == null) {
      return Text('Create an environment with a baseUrl variable to point it at a device from here.', style: context.textStyles.caption.copyWith(color: colors.secondaryText));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                key: ValueKey('device-env-${env.id}'),
                initialValue: env.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Environment'),
                items: [for (final e in vm.environments) DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis))],
                onChanged: (id) => setState(() {
                  _environmentId = id;
                  _variableKey = null;
                }),
              ),
            ),
            SizedBox(
              width: 220,
              child: variable == null
                  ? InputDecorator(
                      decoration: const InputDecoration(labelText: 'Variable'),
                      child: Text('no address variable', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                    )
                  : DropdownButtonFormField<String>(
                      key: ValueKey('device-var-${env.id}-${variable.key}'),
                      initialValue: variable.key,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Variable to change'),
                      items: [for (final v in variables) DropdownMenuItem(value: v.key, child: Text(v.key, overflow: TextOverflow.ellipsis))],
                      onChanged: (key) => setState(() => _variableKey = key),
                    ),
            ),
          ],
        ),
        if (variable != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Now: ${variable.value}', style: context.textStyles.mono.copyWith(color: colors.secondaryText), overflow: TextOverflow.ellipsis),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${env.name} has no enabled variable holding an address (such as baseUrl = http://localhost:3000).', style: context.textStyles.caption.copyWith(color: colors.statusWarning)),
          ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _useReverse,
          onChanged: (v) => setState(() => _useReverse = v ?? true),
          title: const Text('Use adb reverse for phones (the address becomes localhost)'),
          subtitle: Text(_useReverse
              ? 'Works over the USB cable with no network setup.'
              : 'A phone gets this computer\'s Wi-Fi address instead: ${widget.lanIp ?? 'none found'}.'),
        ),
      ],
    );
  }

  Widget _deviceRow(BuildContext context, ConnectedDevice d, EnvironmentEntity? env, EnvironmentVariableEntity? variable) {
    final colors = context.colors;
    final icon = switch (d.kind) {
      DeviceKind.androidEmulator => Icons.developer_board,
      DeviceKind.androidDevice => Icons.smartphone,
      DeviceKind.iosSimulator => Icons.phone_iphone,
    };
    final details = [d.kind.label, d.transport.label, if (d.osVersion != null) d.osVersion!, d.id].join('  ·  ');
    final canUse = d.isReady && env != null && variable != null && !_applying;
    return Container(
      key: ValueKey('device-${d.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: d.isReady ? colors.mainAccent : colors.secondaryText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(details, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                    if (d.problem != null) Text(d.problem!, style: context.textStyles.caption.copyWith(color: colors.statusWarning)),
                  ],
                ),
              ),
            ],
          ),
          if (env != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: FilledButton.tonal(
                  onPressed: canUse ? () => _use(d) : null,
                  child: Text('Use for ${env.name}', overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The exact change, before it is made.
class _ChangeDialog extends StatelessWidget {
  final DeviceUrlPlan plan;
  final String environmentName;
  final String variableKey;
  const _ChangeDialog({required this.plan, required this.environmentName, required this.variableKey});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text('Use ${plan.device.name} for $environmentName'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This changes the variable "$variableKey" of "$environmentName":', style: context.textStyles.body),
              const SizedBox(height: 10),
              _line(context, 'Now', plan.before, colors.statusError),
              const SizedBox(height: 6),
              _line(context, 'After', plan.after ?? '', colors.statusSuccess),
              if (plan.reverseCommand != null) ...[
                const SizedBox(height: 14),
                Text('And runs this on the phone first:', style: context.textStyles.body),
                const SizedBox(height: 6),
                SelectableText(plan.reverseCommand!, key: const ValueKey('reverse-command'), style: context.textStyles.mono),
              ],
              for (final note in plan.notes) ...[
                const SizedBox(height: 10),
                Text(note, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: plan.isUnchanged ? null : () => Navigator.pop(context, true),
          child: Text(plan.isUnchanged ? 'Already set' : 'Apply'),
        ),
      ],
    );
  }

  Widget _line(BuildContext context, String label, String value, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 48, child: Text(label, style: context.textStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700))),
          Expanded(child: SelectableText(value, style: context.textStyles.mono)),
        ],
      );
}
