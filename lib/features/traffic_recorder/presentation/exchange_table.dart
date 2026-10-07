import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../history/presentation/widgets/history_format.dart';
import '../data/recorder_engine.dart';
import 'traffic_recorder_view_model.dart';

/// The live table of recorded calls, newest first: a checkbox to pick calls for a collection, method, status, path, time and
/// size. A tap selects the call for the detail pane.
class ExchangeTable extends StatelessWidget {
  final TrafficRecorderViewModel vm;
  final List<RecordedExchange> rows;

  const ExchangeTable({super.key, required this.vm, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderRow(vm: vm, rows: rows, compact: compact),
            Divider(height: 1, color: colors.borderSubtle),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
                itemBuilder: (context, i) => _Row(key: ValueKey(rows[i].id), vm: vm, exchange: rows[i], compact: compact),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final TrafficRecorderViewModel vm;
  final List<RecordedExchange> rows;
  final bool compact;
  const _HeaderRow({required this.vm, required this.rows, required this.compact});

  @override
  Widget build(BuildContext context) {
    final style = context.textStyles.caption.copyWith(color: context.colors.secondaryText, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6);
    final allChecked = rows.isNotEmpty && rows.every((e) => vm.checkedIds.contains(e.id));
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Checkbox(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              value: allChecked,
              onChanged: rows.isEmpty ? null : (_) => vm.toggleCheckAllVisible(),
            ),
          ),
          SizedBox(width: 56, child: Text('METHOD', style: style)),
          SizedBox(width: 44, child: Text('STATUS', style: style)),
          Expanded(child: Text('PATH', style: style)),
          SizedBox(width: 64, child: Text('TIME', style: style, textAlign: TextAlign.right)),
          if (!compact) SizedBox(width: 66, child: Text('SIZE', style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final TrafficRecorderViewModel vm;
  final RecordedExchange exchange;
  final bool compact;
  const _Row({super.key, required this.vm, required this.exchange, required this.compact});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mono = context.textStyles.mono.copyWith(fontSize: 12);
    final e = exchange;
    final selected = vm.selectedId == e.id;
    final failed = e.kind != RecordedKind.proxied;
    return Material(
      color: selected ? colors.mainAccent.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: () => vm.select(e.id),
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Checkbox(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    value: vm.checkedIds.contains(e.id),
                    onChanged: (v) => vm.toggleChecked(e.id, v ?? false),
                  ),
                ),
                SizedBox(width: 56, child: Text(e.method, style: mono.copyWith(color: colors.forMethod(e.method), fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                SizedBox(width: 44, child: Text('${e.status}', style: mono.copyWith(color: colors.forStatus(e.status), fontWeight: FontWeight.w700))),
                Expanded(
                  child: Row(
                    children: [
                      if (failed) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.error_outline, size: 14, color: colors.statusError)),
                      Expanded(child: Text(vm.pathFor(e), style: mono, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                SizedBox(width: 64, child: Text(formatDuration(e.duration.inMilliseconds), style: mono.copyWith(color: colors.secondaryText), textAlign: TextAlign.right)),
                if (!compact) SizedBox(width: 66, child: Text(formatBytes(e.responseBodySize), style: mono.copyWith(color: colors.secondaryText), textAlign: TextAlign.right)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
