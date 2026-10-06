import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/method_badge.dart';
import '../../../response_tools/domain/services/json_diff.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/services/history_body_diff.dart';
import '../view_models/history_view_model.dart';
import 'history_format.dart';

/// Two entries side by side: how their responses differ. JSON bodies are compared by structure (the
/// same diff the response tools use), other text line by line.
class HistoryCompareView extends StatelessWidget {
  final HistoryViewModel viewModel;
  final HistoryComparison comparison;
  final VoidCallback onBack;
  const HistoryCompareView({super.key, required this.viewModel, required this.comparison, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final diff = comparison.diff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 14, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                tooltip: 'Back to the list',
                visualDensity: VisualDensity.compact,
                onPressed: onBack,
              ),
              Text('Compare responses', style: context.textStyles.heading),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: LayoutBuilder(
            builder: (context, box) {
              final older = _Side(label: 'Older', entry: comparison.older);
              final newer = _Side(label: 'Newer', entry: comparison.newer);
              if (box.maxWidth < 520) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [older, const SizedBox(height: 8), newer]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: older), const SizedBox(width: 10), Expanded(child: newer)]);
            },
          ),
        ),
        if (diff is JsonBodiesDiff)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Ignore volatile fields'),
                tooltip: 'Skip updated_at, created_at, timestamp, request_id and the like',
                selected: comparison.ignoreVolatile,
                onSelected: (value) => viewModel.compareChecked(ignoreVolatile: value),
              ),
            ),
          ),
        Divider(height: 1, color: colors.border),
        Expanded(child: _DiffBody(diff: diff)),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  final String label;
  final HistoryEntryEntity entry;
  const _Side({required this.label, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    final size = entrySize(entry);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: caption.copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9)),
          const SizedBox(height: 6),
          Row(
            children: [
              MethodBadge(method: entry.method, width: 44),
              const SizedBox(width: 8),
              Expanded(child: Text(entry.url, style: context.textStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HistoryStatusChip(entry: entry),
              Text(formatDateTime(entry.sentAt), style: caption),
              if (entry.durationMs != null) Text(formatDuration(entry.durationMs!), style: caption),
              if (size != null) Text(size, style: caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiffBody extends StatelessWidget {
  final HistoryBodyDiff diff;
  const _DiffBody({required this.diff});

  @override
  Widget build(BuildContext context) {
    return switch (diff) {
      BodiesIdentical() => const _Centered(InfoBanner(kind: BannerKind.success, message: 'The two response bodies are identical.')),
      BodiesUnavailable(:final reason) => _Centered(InfoBanner(kind: BannerKind.warning, message: reason)),
      JsonBodiesDiff(:final result) => _JsonChanges(result: result),
      final LineBodiesDiff lines => _LineChanges(diff: lines),
    };
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered(this.child);

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(14), child: Align(alignment: Alignment.topCenter, child: child));
}

class _Count extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _Count({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        backgroundColor: color.withValues(alpha: 0.1),
        label: Text('$count $label', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      );
}

class _JsonChanges extends StatelessWidget {
  final JsonDiffResult result;
  const _JsonChanges({required this.result});

  String _short(Object? v) {
    final s = jsonEncode(v);
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (result.isIdentical) {
      return const _Centered(
        InfoBanner(kind: BannerKind.success, message: 'The two bodies hold the same JSON; only formatting or key order differs.'),
      );
    }
    final mono = context.textStyles.mono.copyWith(fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Count(label: 'added', count: result.count(JsonChangeKind.added), color: colors.statusSuccess),
              _Count(label: 'removed', count: result.count(JsonChangeKind.removed), color: colors.statusError),
              _Count(label: 'changed', count: result.count(JsonChangeKind.changed), color: colors.statusWarning),
              Text('of ${result.compared} values compared', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: result.changes.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
            itemBuilder: (context, i) {
              final change = result.changes[i];
              final (sign, color) = switch (change.kind) {
                JsonChangeKind.added => ('+', colors.statusSuccess),
                JsonChangeKind.removed => ('−', colors.statusError),
                JsonChangeKind.changed => ('~', colors.statusWarning),
              };
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 18, child: Text(sign, style: mono.copyWith(color: color, fontWeight: FontWeight.w800))),
                    Expanded(
                      child: SelectableText.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: change.path, style: mono.copyWith(color: colors.syntaxKey, fontWeight: FontWeight.w600)),
                            if (change.kind != JsonChangeKind.added)
                              TextSpan(text: '   ${_short(change.before)}', style: mono.copyWith(color: colors.statusError)),
                            if (change.kind == JsonChangeKind.changed) TextSpan(text: '  →', style: mono.copyWith(color: colors.secondaryText)),
                            if (change.kind != JsonChangeKind.removed)
                              TextSpan(text: '  ${_short(change.after)}', style: mono.copyWith(color: colors.statusSuccess)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LineChanges extends StatelessWidget {
  final LineBodiesDiff diff;
  const _LineChanges({required this.diff});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mono = context.textStyles.mono.copyWith(fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Count(label: 'lines added', count: diff.added, color: colors.statusSuccess),
              _Count(label: 'lines removed', count: diff.removed, color: colors.statusError),
              if (diff.cut)
                Text(
                  'Only the first ${HistoryBodyCompare.maxLines} lines of each body are compared.',
                  style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                ),
            ],
          ),
        ),
        if (diff.lines.isEmpty)
          const Expanded(
            child: _Centered(InfoBanner(message: 'No difference in the lines that were compared; the bodies differ further down.')),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: diff.lines.length,
              itemBuilder: (context, i) {
                final line = diff.lines[i];
                if (line.kind == DiffLineKind.skipped) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Center(child: Text('… ${line.text}', style: context.textStyles.caption.copyWith(color: colors.secondaryText))),
                  );
                }
                final (sign, color) = switch (line.kind) {
                  DiffLineKind.added => ('+', colors.statusSuccess),
                  DiffLineKind.removed => ('−', colors.statusError),
                  _ => (' ', null),
                };
                return Container(
                  color: color?.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 16, child: Text(sign, style: mono.copyWith(color: color, fontWeight: FontWeight.w800))),
                      Expanded(child: Text(line.text, style: mono)),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
