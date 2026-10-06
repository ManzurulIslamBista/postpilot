import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/services/odoo_request_checker.dart';

/// What the request checker found: the problems one under the other, each with where it is and, when there is an
/// obvious one, a button that applies the fix. With nothing wrong it says so.
class OdooProblemsView extends StatelessWidget {
  final List<OdooProblem> problems;

  /// Applies one problem's fix; the fix buttons are not shown without it (a view that cannot edit what was checked).
  final ValueChanged<OdooProblem>? onFix;

  /// Applies every fix at once; shown when more than one problem has a fix.
  final VoidCallback? onFixAll;

  const OdooProblemsView({super.key, required this.problems, this.onFix, this.onFixAll});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (problems.isEmpty) {
      return const InfoBanner(
        kind: BannerKind.success,
        title: 'No problems found',
        message: 'The model, the field names, the types, the required fields and the domain all match what the server describes.',
      );
    }
    final errors = problems.where((p) => p.isError).length;
    final warnings = problems.length - errors;
    final fixable = problems.where((p) => p.fix != null && p.fix!.changesBody).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            Text(
              '${problems.length} problem${problems.length == 1 ? '' : 's'}: '
              '$errors error${errors == 1 ? '' : 's'}, $warnings warning${warnings == 1 ? '' : 's'}',
              style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            if (onFixAll != null && fixable > 1)
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: onFixAll,
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: Text('Apply all $fixable fixes'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final p in problems)
          Container(
            key: ValueKey('${p.code}|${p.path}|${p.message}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(
              color: (p.isError ? colors.statusError : colors.statusWarning).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (p.isError ? colors.statusError : colors.statusWarning).withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(p.isError ? Icons.error_outline : Icons.warning_amber_rounded, size: 18, color: p.isError ? colors.statusError : colors.statusWarning),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(p.message, style: context.textStyles.body),
                      const SizedBox(height: 2),
                      Text(p.path, style: context.textStyles.mono.copyWith(fontSize: 11.5, color: colors.secondaryText)),
                      if (p.fix != null && onFix != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                            onPressed: () => onFix!(p),
                            icon: const Icon(Icons.build_circle_outlined, size: 16),
                            label: Flexible(child: Text(p.fix!.label, overflow: TextOverflow.ellipsis)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
