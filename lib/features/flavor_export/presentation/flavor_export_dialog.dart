import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../dart_codegen/presentation/widgets/generated_files_view.dart';
import '../../environments/domain/entities/environment_entity.dart';
import '../../environments/presentation/view_models/environments_view_model.dart';
import '../domain/services/flavor_exporter.dart';

/// "Export for Flutter": pick environments and variables, name the flavors, and get the `.env`, `env.json`, run commands,
/// launch configurations and a typed `AppConfig` that read them. Nothing is written until "Save to folder…", which asks
/// before replacing a file.
class FlavorExportDialog extends StatefulWidget {
  /// The environment that is ticked at first; every environment when null.
  final int? initialEnvironmentId;
  const FlavorExportDialog({super.key, this.initialEnvironmentId});

  static Future<void> show(BuildContext context, {int? environmentId}) =>
      ToolDialog.show(context, (_) => FlavorExportDialog(initialEnvironmentId: environmentId));

  @override
  State<FlavorExportDialog> createState() => _FlavorExportDialogState();
}

class _FlavorExportDialogState extends State<FlavorExportDialog> {
  late final EnvironmentsViewModel _vm = context.read<EnvironmentsViewModel>();
  final _appName = TextEditingController(text: 'app');

  /// Environments that are not exported; everything else is, so a new environment is included without asking.
  final Set<int> _off = {};
  bool _onlyInitial = true;
  final Map<int, String> _flavorNames = {};

  /// Variables the person ticked or unticked; the rest follow the default (secrets off).
  final Map<String, bool> _ticks = {};
  bool _upperSnake = true;
  bool _defaults = true;
  bool _flavorArg = false;

  @override
  void initState() {
    super.initState();
    _vm.watchGlobals();
  }

  @override
  void dispose() {
    _appName.dispose();
    super.dispose();
  }

  List<FlavorEnvironment> _environments() {
    final globals = [
      for (final g in _vm.globals)
        if (g.enabled && g.key.trim().isNotEmpty) FlavorVariable(g.key, g.value, isSecret: g.isSecret),
    ];
    final result = <FlavorEnvironment>[];
    for (final e in _selected()) {
      final own = [
        for (final v in _vm.variablesFor(e.id))
          if (v.enabled && v.key.trim().isNotEmpty) FlavorVariable(v.key, v.value, isSecret: v.isSecret),
      ];
      result.add(FlavorEnvironment(
        name: e.name,
        flavor: _flavorNames[e.id] ?? FlavorExporter.defaultFlavorName(e.name),
        variables: FlavorExporter.mergeScopes(globals, own),
      ));
    }
    return result;
  }

  Iterable<EnvironmentEntity> _selected() sync* {
    for (final e in _vm.environments) {
      final initialOnly = _onlyInitial && widget.initialEnvironmentId != null && e.id != widget.initialEnvironmentId;
      if (!_off.contains(e.id) && !initialOnly) yield e;
    }
  }

  bool _isOn(EnvironmentEntity e) => _selected().any((s) => s.id == e.id);

  void _toggleEnvironment(EnvironmentEntity e, bool on) {
    setState(() {
      // The first manual change leaves "only the environment the dialog was opened for" and starts from what is shown.
      if (_onlyInitial) {
        _off
          ..clear()
          ..addAll([for (final x in _vm.environments) if (!_isOn(x)) x.id]);
        _onlyInitial = false;
      }
      if (on) {
        _off.remove(e.id);
      } else {
        _off.add(e.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        // Variables load per environment; asking again for one already being watched does nothing.
        for (final e in _vm.environments) {
          _vm.watchVariables(e.id);
        }
        final subtitle = 'Turn environments into .env, env.json, run commands and a typed AppConfig';
        if (_vm.environments.isEmpty) {
          return ToolDialog(
            icon: Icons.flutter_dash,
            title: 'Export for Flutter',
            subtitle: subtitle,
            width: 1060,
            height: 700,
            child: const EmptyHint(
              icon: Icons.layers_outlined,
              title: 'No environments yet',
              message: 'Create an environment (Development, Staging, Production) with its variables, then export it here.',
            ),
          );
        }
        final environments = _environments();
        final defaults = FlavorExporter.defaultSelection(environments);
        final allKeys = <String>{
          for (final env in environments)
            for (final v in env.variables)
              if (v.key.trim().isNotEmpty) v.key,
        }.toList();
        final included = {for (final k in allKeys) if (_ticks[k] ?? defaults.contains(k)) k};
        final export = environments.isEmpty
            ? null
            : FlavorExporter.export(
                environments,
                FlavorExportOptions(
                  includedKeys: included,
                  upperSnakeNames: _upperSnake,
                  embedDefaults: _defaults,
                  passFlavorArgument: _flavorArg,
                  appName: _appName.text.trim().isEmpty ? 'app' : _appName.text.trim(),
                ),
              );
        final choose = _Choose(
          vm: _vm,
          isOn: _isOn,
          onToggleEnvironment: _toggleEnvironment,
          flavorName: (e) => _flavorNames[e.id] ?? FlavorExporter.defaultFlavorName(e.name),
          onFlavorName: (e, name) => setState(() => _flavorNames[e.id] = name),
          variables: environments,
          allKeys: allKeys,
          isTicked: (k) => included.contains(k),
          onTick: (k, on) => setState(() => _ticks[k] = on),
          appName: _appName,
          upperSnake: _upperSnake,
          defaults: _defaults,
          flavorArg: _flavorArg,
          onOptions: ({upperSnake, defaults, flavorArg}) => setState(() {
            _upperSnake = upperSnake ?? _upperSnake;
            _defaults = defaults ?? _defaults;
            _flavorArg = flavorArg ?? _flavorArg;
          }),
          onAppName: () => setState(() {}),
        );
        final result = _Result(export: export);
        return ToolDialog(
          icon: Icons.flutter_dash,
          title: 'Export for Flutter',
          subtitle: subtitle,
          width: 1060,
          height: 700,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return ToolTabs(tabs: [
                  ToolTab(label: 'Choose', icon: Icons.checklist, child: choose),
                  ToolTab(label: 'Files', icon: Icons.description_outlined, child: result),
                ]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: choose),
                  VerticalDivider(width: 1, color: context.colors.border),
                  Expanded(child: result),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

typedef _OptionsChanged = void Function({bool? upperSnake, bool? defaults, bool? flavorArg});

class _Choose extends StatelessWidget {
  final EnvironmentsViewModel vm;
  final bool Function(EnvironmentEntity) isOn;
  final void Function(EnvironmentEntity, bool) onToggleEnvironment;
  final String Function(EnvironmentEntity) flavorName;
  final void Function(EnvironmentEntity, String) onFlavorName;
  final List<FlavorEnvironment> variables;
  final List<String> allKeys;
  final bool Function(String) isTicked;
  final void Function(String, bool) onTick;
  final TextEditingController appName;
  final bool upperSnake;
  final bool defaults;
  final bool flavorArg;
  final _OptionsChanged onOptions;
  final VoidCallback onAppName;

  const _Choose({
    required this.vm,
    required this.isOn,
    required this.onToggleEnvironment,
    required this.flavorName,
    required this.onFlavorName,
    required this.variables,
    required this.allKeys,
    required this.isTicked,
    required this.onTick,
    required this.appName,
    required this.upperSnake,
    required this.defaults,
    required this.flavorArg,
    required this.onOptions,
    required this.onAppName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    bool secret(String key) => variables.any((e) => e.variables.any((v) => v.key == key && FlavorExporter.isSecretVariable(v)));
    String? sample(String key) {
      for (final e in variables) {
        for (final v in e.variables) {
          if (v.key == key) return v.value;
        }
      }
      return null;
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        ToolSection(
          title: 'Environments and flavors',
          hint: 'Each ticked environment becomes one flavor. The flavor name is used in file names; change it if you like.',
          child: Column(
            children: [
              for (final e in vm.environments)
                Row(
                  key: ValueKey('flavor-env-${e.id}'),
                  children: [
                    Checkbox(value: isOn(e), onChanged: (v) => onToggleEnvironment(e, v ?? false)),
                    Expanded(child: Text(e.name, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 104,
                      child: _FlavorNameField(
                        initial: flavorName(e),
                        enabled: isOn(e),
                        onChanged: (name) => onFlavorName(e, name),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        ToolSection(
          title: 'Variables (${allKeys.where(isTicked).length} of ${allKeys.length})',
          hint: 'Names that look like secrets are unticked. If you tick one it is exported as an empty placeholder, never with its value.',
          child: allKeys.isEmpty
              ? Text('The ticked environments have no enabled variables.', style: context.textStyles.caption.copyWith(color: colors.secondaryText))
              : Column(
                  children: [
                    for (final key in allKeys)
                      CheckboxListTile(
                        key: ValueKey('flavor-var-$key'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: isTicked(key),
                        onChanged: (v) => onTick(key, v ?? false),
                        title: Row(
                          children: [
                            Flexible(child: Text(key, style: context.textStyles.mono, overflow: TextOverflow.ellipsis)),
                            if (secret(key)) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.lock_outline, size: 14, color: colors.statusWarning),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          secret(key)
                              ? (isTicked(key) ? 'Looks like a secret: exported as an empty placeholder' : 'Looks like a secret: left out')
                              : (sample(key) ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.caption.copyWith(color: secret(key) ? colors.statusWarning : colors.secondaryText),
                        ),
                      ),
                  ],
                ),
        ),
        ToolSection(
          title: 'Options',
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: appName,
                decoration: const InputDecoration(labelText: 'App name (for the launch configurations)'),
                onChanged: (_) => onAppName(),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: upperSnake,
                onChanged: (v) => onOptions(upperSnake: v),
                title: const Text('Name defines like BASE_URL'),
                subtitle: const Text('Off keeps the variable names as you wrote them.'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: defaults,
                onChanged: (v) => onOptions(defaults: v),
                title: const Text("Use the first flavor's values as defaults"),
                subtitle: const Text('A plain flutter run then works without any flag.'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: flavorArg,
                onChanged: (v) => onOptions(flavorArg: v),
                title: const Text('Also pass --flavor <name>'),
                subtitle: const Text('Only if the Android and iOS flavors of that name exist.'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Keeps its own text: a parent rebuild on every keystroke must not reset what is being typed.
class _FlavorNameField extends StatefulWidget {
  final String initial;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _FlavorNameField({required this.initial, required this.enabled, required this.onChanged});

  @override
  State<_FlavorNameField> createState() => _FlavorNameFieldState();
}

class _FlavorNameFieldState extends State<_FlavorNameField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        enabled: widget.enabled,
        autocorrect: false,
        decoration: const InputDecoration(isDense: true, hintText: 'flavor'),
        onChanged: widget.onChanged,
      );
}

class _Result extends StatelessWidget {
  final FlavorExport? export;
  const _Result({required this.export});

  @override
  Widget build(BuildContext context) {
    final export = this.export;
    if (export == null) {
      return const EmptyHint(
        icon: Icons.layers_outlined,
        title: 'Tick an environment',
        message: 'Choose at least one environment on the left to see the files.',
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (export.hasSecretPlaceholders)
            const InfoBanner(
              key: ValueKey('flavor-secret-warning'),
              kind: BannerKind.warning,
              title: 'Real secrets must never go in here',
              message: FlavorExporter.secretWarning,
              margin: EdgeInsets.only(bottom: 8),
            ),
          if (export.warnings.isNotEmpty)
            InfoBanner(
              key: const ValueKey('flavor-warnings'),
              kind: BannerKind.warning,
              title: export.warnings.length == 1 ? 'Check this' : 'Check these (${export.warnings.length})',
              message: [...export.warnings.take(6), if (export.warnings.length > 6) '…and ${export.warnings.length - 6} more'].join('\n'),
              margin: const EdgeInsets.only(bottom: 8),
            ),
          Expanded(child: GeneratedFilesView(files: export.files, downloadName: 'flavor-export')),
        ],
      ),
    );
  }
}
