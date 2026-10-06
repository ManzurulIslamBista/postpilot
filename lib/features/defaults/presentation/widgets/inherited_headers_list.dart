import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../domain/entities/defaults_origin.dart';
import '../../domain/entities/inherited_defaults.dart';
import 'origin_chip.dart';

/// The headers something inherits, read-only, each with the collection or folder that set it.
///
/// [own] are the rows of the level looking at them (a request's own headers): one that has the same
/// name as an inherited header (any case) takes it over, and a disabled one switches it off, so the
/// inherited row is shown struck through with that said. [onOverride] adds an own row to change the
/// value, [onSwitchOff] adds a disabled one; without them the list is a plain read-out. A secret
/// header's value is not shown, only copied by an override.
class InheritedHeadersList extends StatelessWidget {
  final List<InheritedHeader> headers;
  final List<KeyValueItem> own;
  final ValueChanged<InheritedHeader>? onOverride;
  final ValueChanged<InheritedHeader>? onSwitchOff;

  /// Opens the defaults of the level that set a header.
  final ValueChanged<DefaultsOrigin>? onEditOrigin;

  const InheritedHeadersList({
    super.key,
    required this.headers,
    this.own = const [],
    this.onOverride,
    this.onSwitchOff,
    this.onEditOrigin,
  });

  static String _normal(String name) => name.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ownEnabled = {for (final h in own) if (h.enabled && h.key.trim().isNotEmpty) _normal(h.key)};
    final ownNames = {for (final h in own) if (h.key.trim().isNotEmpty) _normal(h.key)};
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.sidebarBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: [
          for (var i = 0; i < headers.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.borderSubtle),
            _Row(
              header: headers[i],
              state: !ownNames.contains(_normal(headers[i].item.key))
                  ? _RowState.inherited
                  : ownEnabled.contains(_normal(headers[i].item.key))
                      ? _RowState.overridden
                      : _RowState.switchedOff,
              onOverride: onOverride,
              onSwitchOff: onSwitchOff,
              onEditOrigin: onEditOrigin,
            ),
          ],
        ],
      ),
    );
  }
}

enum _RowState { inherited, overridden, switchedOff }

class _Row extends StatelessWidget {
  final InheritedHeader header;
  final _RowState state;
  final ValueChanged<InheritedHeader>? onOverride;
  final ValueChanged<InheritedHeader>? onSwitchOff;
  final ValueChanged<DefaultsOrigin>? onEditOrigin;

  const _Row({
    required this.header,
    required this.state,
    required this.onOverride,
    required this.onSwitchOff,
    required this.onEditOrigin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    final item = header.item;
    final active = state == _RowState.inherited;
    final struck = active ? null : TextDecoration.lineThrough;
    final shownValue = SecretMasker.maskValue(item.key, item.value);
    final note = switch (state) {
      _RowState.inherited => null,
      _RowState.overridden => 'overridden here',
      _RowState.switchedOff => 'switched off here',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 15, color: colors.secondaryText),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  item.key,
                  style: textStyles.mono.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: struck,
                    color: active ? colors.primaryText : colors.secondaryText,
                  ),
                ),
                Text(
                  shownValue.isEmpty ? '(empty)' : shownValue,
                  style: textStyles.mono.copyWith(color: colors.secondaryText, decoration: struck),
                ),
                if (note != null) Text(note, style: textStyles.caption.copyWith(color: colors.statusWarning)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OriginChip(origin: header.origin),
          if (onEditOrigin != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              tooltip: 'Edit the defaults of the ${header.origin.label}',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => onEditOrigin!(header.origin),
            ),
          if (active && onOverride != null)
            TextButton(onPressed: () => onOverride!(header), child: const Text('Override')),
          if (active && onSwitchOff != null)
            TextButton(onPressed: () => onSwitchOff!(header), child: const Text('Turn off')),
        ],
      ),
    );
  }
}
