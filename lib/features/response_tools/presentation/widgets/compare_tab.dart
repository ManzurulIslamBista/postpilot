import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/services/json_diff.dart';
import '../view_models/response_tools_view_model.dart';

/// What changed between this response and an earlier one (or a saved example):
/// keys added, removed or changed, by path. Fields that differ on every call
/// (timestamps, request ids) can be ignored so the real change stands out.
class CompareTab extends StatefulWidget {
  final ResponseToolsViewModel viewModel;
  const CompareTab({super.key, required this.viewModel});

  @override
  State<CompareTab> createState() => _CompareTabState();
}

class _CompareTabState extends State<CompareTab> {
  static const _volatile = {'updated_at', 'created_at', 'updatedat', 'createdat', 'timestamp', 'requestid', 'request_id', 'write_date', 'date'};

  int _source = 0;
  bool _ignoreVolatile = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final sources = vm.compareSources;
    final colors = context.colors;
    if (sources.isEmpty) {
      return const EmptyHint(
        icon: Icons.compare_arrows,
        title: 'Nothing to compare with yet',
        message: 'Send the request again to compare the two responses, or save one with "Save as example" '
            'to keep a baseline.',
      );
    }
    final index = _source.clamp(0, sources.length - 1);
    final other = sources[index];
    final data = vm.data;

    Object? decode(String s) {
      try {
        return jsonDecode(s);
      } on FormatException {
        return null;
      }
    }

    final left = decode(other.body);
    final bothJson = data.isJson && left != null;
    final result = bothJson ? JsonDiff.compare(left, data.json, ignoreKeys: _ignoreVolatile ? _volatile : const {}) : null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final picker = DropdownButtonFormField<int>(
                key: ValueKey(index),
                initialValue: index,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Compare current response with'),
                items: [for (var i = 0; i < sources.length; i++) DropdownMenuItem(value: i, child: Text(sources[i].label, overflow: TextOverflow.ellipsis))],
                onChanged: (i) => setState(() => _source = i ?? 0),
              );
              final ignore = FilterChip(
                label: const Text('Ignore volatile fields'),
                tooltip: 'Skip ${_volatile.take(4).join(', ')}…',
                selected: _ignoreVolatile,
                onSelected: (v) => setState(() => _ignoreVolatile = v),
              );
              // Beside the chip a phone-width picker is left too narrow to show which response is chosen: put the chip underneath.
              if (box.maxWidth < 520) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [picker, const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: ignore)]);
              }
              return Row(children: [Expanded(child: picker), const SizedBox(width: 10), ignore]);
            },
          ),
          const SizedBox(height: 12),
          if (result == null)
            Expanded(
              child: Center(
                child: other.body == data.bodyText
                    ? const InfoBanner(kind: BannerKind.success, message: 'The bodies are identical.')
                    : const InfoBanner(
                        kind: BannerKind.warning,
                        message: 'The bodies differ, but at least one is not JSON, so they cannot be compared field by field.',
                      ),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              children: [
                _Count(label: 'added', count: result.count(JsonChangeKind.added), color: colors.statusSuccess),
                _Count(label: 'removed', count: result.count(JsonChangeKind.removed), color: colors.statusError),
                _Count(label: 'changed', count: result.count(JsonChangeKind.changed), color: colors.statusWarning),
                Text('of ${result.compared} values compared', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: result.isIdentical
                  ? const Center(child: InfoBanner(kind: BannerKind.success, message: 'No differences: the two responses match.'))
                  : Container(
                      decoration: BoxDecoration(
                        color: colors.appBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        itemCount: result.changes.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
                        itemBuilder: (context, i) => _ChangeRow(change: result.changes[i]),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
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

class _ChangeRow extends StatelessWidget {
  final JsonChange change;
  const _ChangeRow({required this.change});

  String _short(Object? v) {
    final s = jsonEncode(v);
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (sign, color) = switch (change.kind) {
      JsonChangeKind.added => ('+', colors.statusSuccess),
      JsonChangeKind.removed => ('−', colors.statusError),
      JsonChangeKind.changed => ('~', colors.statusWarning),
    };
    final mono = context.textStyles.mono.copyWith(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 18, child: Text(sign, style: mono.copyWith(color: color, fontWeight: FontWeight.w800))),
          Expanded(
            child: SelectableText.rich(
              TextSpan(children: [
                TextSpan(text: change.path, style: mono.copyWith(color: colors.syntaxKey, fontWeight: FontWeight.w600)),
                if (change.kind != JsonChangeKind.added) TextSpan(text: '   ${_short(change.before)}', style: mono.copyWith(color: colors.statusError)),
                if (change.kind == JsonChangeKind.changed) TextSpan(text: '  →', style: mono.copyWith(color: colors.secondaryText)),
                if (change.kind != JsonChangeKind.removed) TextSpan(text: '  ${_short(change.after)}', style: mono.copyWith(color: colors.statusSuccess)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
