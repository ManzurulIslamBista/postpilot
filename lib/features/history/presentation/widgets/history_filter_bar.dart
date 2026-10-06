import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/entities/history_filter.dart';
import '../view_models/history_view_model.dart';

/// The search box and the filters above the History list.
class HistoryFilterBar extends StatefulWidget {
  final HistoryViewModel viewModel;
  final bool autofocus;
  const HistoryFilterBar({super.key, required this.viewModel, this.autofocus = false});

  @override
  State<HistoryFilterBar> createState() => _HistoryFilterBarState();
}

class _HistoryFilterBarState extends State<HistoryFilterBar> {
  late final TextEditingController _controller = TextEditingController(text: widget.viewModel.filter.query);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final filter = vm.filter;
    // "Clear filters" empties the box too; the model is the source of truth for the query.
    if (_controller.text != filter.query) _controller.text = filter.query;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            onChanged: (value) {
              vm.setQuery(value);
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: 'Search URL, method, name, status or body',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Clear the search',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _controller.clear();
                        vm.setQuery('');
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FilterMenu<HistoryRange>(
                label: 'When',
                valueLabel: filter.range == HistoryRange.all ? null : filter.range.label,
                options: [for (final r in HistoryRange.values) (value: r, label: r.label)],
                selected: filter.range,
                onSelected: vm.setRange,
              ),
              _FilterMenu<HistoryStatusClass?>(
                label: 'Status',
                valueLabel: filter.statusClass?.label,
                options: [
                  (value: null, label: 'Any status'),
                  for (final s in HistoryStatusClass.values) (value: s, label: s.label),
                ],
                selected: filter.statusClass,
                onSelected: vm.setStatusClass,
              ),
              _FilterMenu<String?>(
                label: 'Method',
                valueLabel: filter.method,
                options: [(value: null, label: 'Any method'), for (final m in vm.methods) (value: m, label: m)],
                selected: filter.method,
                onSelected: vm.setMethod,
              ),
              if (vm.collections.isNotEmpty)
                _FilterMenu<int?>(
                  label: 'Collection',
                  valueLabel: vm.collections.where((c) => c.id == filter.collectionId).firstOrNull?.name,
                  options: [(value: null, label: 'Any collection'), for (final c in vm.collections) (value: c.id, label: c.name)],
                  selected: filter.collectionId,
                  onSelected: vm.setCollection,
                ),
              if (filter.isActive)
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: vm.clearFilters,
                  child: const Text('Clear filters'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wraps a value so that choosing "none" (null) is told from dismissing the menu, which reports null.
final class _Choice<T> {
  final T value;
  const _Choice(this.value);
}

/// A chip that opens a menu of choices: `Status: 4xx`, or just `Status` while nothing is chosen.
class _FilterMenu<T> extends StatelessWidget {
  final String label;

  /// What is chosen, shown after the label; null while the filter is off.
  final String? valueLabel;
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onSelected;

  const _FilterMenu({
    required this.label,
    required this.valueLabel,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = valueLabel != null;
    final tint = active ? colors.mainAccent : colors.secondaryText;
    return PopupMenuButton<_Choice<T>>(
      tooltip: 'Filter by ${label.toLowerCase()}',
      onSelected: (choice) => onSelected(choice.value),
      itemBuilder: (context) => [
        for (final option in options)
          CheckedPopupMenuItem<_Choice<T>>(
            value: _Choice(option.value),
            checked: option.value == selected,
            child: Text(option.label),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? colors.mainAccent.withValues(alpha: 0.12) : colors.hover,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? colors.mainAccent.withValues(alpha: 0.45) : colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              active ? '$label: $valueLabel' : label,
              style: context.textStyles.caption.copyWith(color: tint, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: tint),
          ],
        ),
      ),
    );
  }
}
