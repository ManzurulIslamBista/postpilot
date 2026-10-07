import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../domain/services/mock_network.dart';

/// Picks a network profile (2G, 3G, lossy, flapping, offline...) from a menu and opens its numbers for editing. The button shows the
/// profile in force (just an icon on a phone while none is). A change applies to the next request while the server runs.
///
/// With [inherit] it is a route's button: it also offers "Same as the whole server", and "No throttling" is a profile of its own
/// that exempts the route from the whole server's.
class MockNetworkMenu extends StatelessWidget {
  /// What is in force here; null when nothing is set (for a route: the whole server's applies).
  final NetworkProfile? profile;
  final bool inherit;

  /// Null means "not set": no throttling for the whole server, the whole server's profile for a route.
  final ValueChanged<NetworkProfile?> onChanged;

  const MockNetworkMenu({super.key, required this.profile, required this.onChanged, this.inherit = false});

  static const _inheritValue = '__inherit';
  static const _editValue = '__edit';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = profile;
    final shownName = current != null && !current.isIdle ? current.name : null;
    final active = shownName != null;
    final exempt = inherit && current != null && current.isIdle;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final label = shownName ?? (exempt ? NetworkProfiles.none.name : 'Network');
    return PopupMenuButton<String>(
      key: const ValueKey('network-menu'),
      tooltip: shownName != null
          ? 'Network: $shownName. Change it'
          : (inherit ? 'Network for this route: the whole server\'s unless set here' : 'Simulate a slow, lossy or offline network'),
      onSelected: (id) async {
        if (id == _editValue) {
          final edited = await showDialog<NetworkProfile>(context: context, builder: (_) => MockNetworkTuneDialog(profile: current ?? NetworkProfiles.none));
          if (edited != null) onChanged(edited);
        } else if (id == _inheritValue) {
          onChanged(null);
        } else if (id == NetworkProfiles.none.id) {
          // "No throttling" on a route is a profile of its own: it exempts the route from the whole server's.
          onChanged(inherit ? NetworkProfiles.none : null);
        } else if (id != NetworkProfiles.customId) {
          onChanged(NetworkProfiles.byId(id));
        }
      },
      itemBuilder: (_) => [
        if (inherit) CheckedPopupMenuItem(value: _inheritValue, checked: current == null, child: const Text('Same as the whole server')),
        CheckedPopupMenuItem(value: NetworkProfiles.none.id, checked: inherit ? exempt : !active, child: Text(NetworkProfiles.none.name)),
        for (final p in NetworkProfiles.presets) CheckedPopupMenuItem(value: p.id, checked: current?.id == p.id, child: Text(p.name)),
        if (current != null && current.id == NetworkProfiles.customId) CheckedPopupMenuItem(value: current.id, checked: true, child: Text(current.name)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: _editValue, child: Text('Edit the numbers…')),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 10, vertical: 5),
        decoration: BoxDecoration(
          color: (active ? colors.statusWarning : colors.secondaryText).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.network_check, size: 16, color: active ? colors.statusWarning : colors.secondaryText),
            if (!phone || active || exempt) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: phone ? 90 : 180),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: active ? colors.statusWarning : colors.secondaryText, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The numbers of a profile. "Apply" returns a copy (named "`<profile>` (edited)") and leaves the ready-made one untouched.
class MockNetworkTuneDialog extends StatefulWidget {
  final NetworkProfile profile;
  const MockNetworkTuneDialog({super.key, required this.profile});

  @override
  State<MockNetworkTuneDialog> createState() => _MockNetworkTuneDialogState();
}

class _NumberField {
  final String label;
  final String suffix;
  final int Function(NetworkProfile) read;
  final NetworkProfile Function(NetworkProfile, int) write;
  final int max;
  const _NumberField(this.label, this.suffix, this.read, this.write, {this.max = 1000000});
}

final _numberFields = <_NumberField>[
  _NumberField('First byte after', 'ms', (p) => p.latencyMs, (p, v) => p.copyWith(latencyMs: v)),
  _NumberField('Jitter', '%', (p) => p.jitterPercent, (p, v) => p.copyWith(jitterPercent: v), max: 100),
  _NumberField('Bandwidth (0 = no limit)', 'kbit/s', (p) => p.bandwidthKbps, (p, v) => p.copyWith(bandwidthKbps: v)),
  _NumberField('Drop the connection', '%', (p) => p.resetPercent, (p, v) => p.copyWith(resetPercent: v), max: 100),
  _NumberField('Cut the body off', '%', (p) => p.truncatePercent, (p, v) => p.copyWith(truncatePercent: v), max: 100),
  _NumberField('Never answer', '%', (p) => p.timeoutPercent, (p, v) => p.copyWith(timeoutPercent: v), max: 100),
  _NumberField('Server error', '%', (p) => p.errorPercent, (p, v) => p.copyWith(errorPercent: v), max: 100),
  _NumberField('Retry-After (0 = none)', 's', (p) => p.retryAfterSeconds, (p, v) => p.copyWith(retryAfterSeconds: v)),
  _NumberField('Corrupt the answer', '%', (p) => p.corruptPercent, (p, v) => p.copyWith(corruptPercent: v), max: 100),
  _NumberField('Connection up for', 's', (p) => p.upSeconds, (p, v) => p.copyWith(upSeconds: v)),
  _NumberField('then down for', 's', (p) => p.downSeconds, (p, v) => p.copyWith(downSeconds: v)),
];

class _MockNetworkTuneDialogState extends State<MockNetworkTuneDialog> {
  late final List<TextEditingController> _controllers = [for (final f in _numberFields) TextEditingController(text: '${f.read(widget.profile)}')];
  late final _statuses = TextEditingController(text: widget.profile.errorStatuses.join(', '));
  late bool _offline = widget.profile.offline;
  late Set<NetworkCorruption> _modes = {...widget.profile.corruptModes};

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _statuses.dispose();
    super.dispose();
  }

  NetworkProfile _build() {
    var p = widget.profile;
    for (var i = 0; i < _numberFields.length; i++) {
      final f = _numberFields[i];
      p = f.write(p, (int.tryParse(_controllers[i].text.trim()) ?? 0).clamp(0, f.max).toInt());
    }
    final statuses = [
      for (final s in _statuses.text.split(RegExp(r'[,\s]+')))
        if (int.tryParse(s) != null && int.parse(s) >= 400 && int.parse(s) <= 599) int.parse(s),
    ];
    return p.copyWith(
      id: NetworkProfiles.customId,
      name: widget.profile.id == NetworkProfiles.customId ? widget.profile.name : '${widget.profile.name} (edited)',
      offline: _offline,
      errorStatuses: statuses,
      corruptModes: [for (final m in NetworkCorruption.values) if (_modes.contains(m)) m],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text('Edit ${widget.profile.name}'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Percentages are the share of requests affected. The speed limit is real: the body is written in paced slices. '
                'The values apply to the next request.',
                style: context.textStyles.caption.copyWith(color: colors.secondaryText),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < _numberFields.length; i++)
                    SizedBox(
                      width: 160,
                      child: TextField(
                        key: ValueKey('network-field-${_numberFields[i].label}'),
                        controller: _controllers[i],
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(labelText: _numberFields[i].label, suffixText: _numberFields[i].suffix),
                      ),
                    ),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      key: const ValueKey('network-field-statuses'),
                      controller: _statuses,
                      decoration: const InputDecoration(labelText: 'Error statuses', hintText: '500, 502, 503'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _offline,
                onChanged: (v) => setState(() => _offline = v),
                title: const Text('Offline'),
                subtitle: const Text('Every connection is dropped before any answer.'),
              ),
              Text('Corruption (picked at random for a corrupt answer)', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in NetworkCorruption.values)
                    FilterChip(
                      label: Text(m.label),
                      tooltip: m.description,
                      selected: _modes.contains(m),
                      onSelected: (on) => setState(() => _modes = on ? {..._modes, m} : ({..._modes}..remove(m))),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _build()), child: const Text('Apply')),
      ],
    );
  }
}
