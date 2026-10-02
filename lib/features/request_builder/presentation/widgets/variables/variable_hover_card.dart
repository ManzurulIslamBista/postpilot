import 'package:flutter/material.dart';
import '../../../../../core/theme/context_theme_extensions.dart';
import '../../../../../core/widgets/glass_container.dart';
import '../../../domain/entities/variable_info.dart';

/// The small card shown while hovering a `{{variable}}`: its name, what it
/// currently holds and which scope supplies it. Display only; it never takes
/// the pointer, so it cannot get in the way of the field underneath.
class VariableHoverCard extends StatelessWidget {
  final VariableInfo info;
  const VariableHoverCard({super.key, required this.info});

  /// Longest value shown; the rest is cut so a pasted token or payload cannot
  /// fill the screen.
  static const _maxValueChars = 300;
  static const width = 340.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    final accent = info.isResolved ? colors.mainAccent : colors.statusError;

    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: width),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(12),
          opacity: 0.94,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: DefaultTextStyle(
            style: textStyles.body,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '{{${info.name}}}',
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.mono.copyWith(color: accent, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _SourceChip(info: info),
                  ],
                ),
                const SizedBox(height: 8),
                _Body(info: info),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final VariableInfo info;
  const _Body({required this.info});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);

    if (!info.isResolved) {
      return Text(
        'Not defined in the active environment, this collection or the globals. It is sent as written.',
        style: context.textStyles.caption.copyWith(color: colors.statusError, height: 1.35),
      );
    }
    if (info.isSecret) {
      return Row(
        children: [
          Icon(Icons.lock_outline, size: 14, color: colors.secondaryText),
          const SizedBox(width: 6),
          Text('••••••••', style: context.textStyles.mono),
          const SizedBox(width: 8),
          Flexible(child: Text('Secret, hidden', style: caption)),
        ],
      );
    }
    final value = info.value ?? '';
    final shown = value.length > VariableHoverCard._maxValueChars
        ? '${value.substring(0, VariableHoverCard._maxValueChars)}…'
        : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: colors.appBackground.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Text(
            value.isEmpty ? '(empty)' : shown,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.mono.copyWith(color: value.isEmpty ? colors.secondaryText : colors.primaryText),
          ),
        ),
        if (info.source == VariableSource.dynamic) ...[
          const SizedBox(height: 6),
          Text('Example only: a new value is generated on every send.', style: caption),
        ],
      ],
    );
  }
}

class _SourceChip extends StatelessWidget {
  final VariableInfo info;
  const _SourceChip({required this.info});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, color) = switch (info.source) {
      VariableSource.environment => ('Environment · ${info.scopeName ?? ''}'.trim(), colors.statusSuccess),
      VariableSource.collection => ('Collection', colors.methodPut),
      VariableSource.global => ('Global', colors.methodPatch),
      VariableSource.dynamic => ('Dynamic', colors.methodPost),
      VariableSource.unresolved => ('Undefined', colors.statusError),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
