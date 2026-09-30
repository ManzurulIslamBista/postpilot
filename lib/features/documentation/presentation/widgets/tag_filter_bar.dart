import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/tag_filter_view_model.dart';

/// A row of chips for the top of the sidebar: "All" plus every tag in use.
/// Selecting tags narrows the sidebar to the requests that carry any of them;
/// "All" clears the filter. Hidden while no tag exists.
class TagFilterBar extends StatelessWidget {
  const TagFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final filter = context.watch<TagFilterViewModel>();
    if (filter.allTags.isEmpty) return const SizedBox.shrink();
    final labelStyle = context.textStyles.caption;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          _chip('All', selected: !filter.isFiltering, style: labelStyle, onTap: filter.clear),
          for (final tag in filter.allTags)
            _chip(tag, selected: filter.isSelected(tag), style: labelStyle, onTap: () => filter.toggleTag(tag)),
        ],
      ),
    );
  }

  Widget _chip(String label, {required bool selected, required TextStyle style, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          key: ValueKey('tag-filter-$label'),
          label: Text(label, style: style),
          selected: selected,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => onTap(),
        ),
      );
}
