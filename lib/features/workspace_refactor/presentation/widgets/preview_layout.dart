import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/preview_rows.dart';
import 'preview_tiles.dart';

/// A pane made of some controls, the preview list and a footer. With room (a desktop dialog) the controls stay on top
/// and the list takes the rest; on a phone or in a short window the controls and the list scroll as one, so the list is
/// never squeezed to a few pixels by what is above it.
class PreviewLayout extends StatelessWidget {
  final Widget controls;
  final PreviewRows rows;
  final bool Function(String editId) isTicked;
  final void Function(Iterable<String> editIds, bool ticked)? onTick;

  /// Shown instead of the list while there are no rows.
  final Widget empty;
  final Widget footer;

  const PreviewLayout({
    super.key,
    required this.controls,
    required this.rows,
    required this.isTicked,
    required this.empty,
    required this.footer,
    this.onTick,
  });

  PreviewTile _tile(int i) =>
      PreviewTile(key: PreviewTile.keyFor(rows.rows[i], i), row: rows.rows[i], isTicked: isTicked, onTick: onTick);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 640 && c.maxHeight >= 520) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      controls,
                      const SizedBox(height: 8),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(border: Border.all(color: context.colors.border), borderRadius: BorderRadius.circular(10)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: rows.isEmpty ? empty : ListView.builder(itemCount: rows.rows.length, itemBuilder: (context, i) => _tile(i)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return CustomScrollView(
                slivers: [
                  SliverPadding(padding: const EdgeInsets.all(16), sliver: SliverToBoxAdapter(child: controls)),
                  if (rows.isEmpty)
                    SliverToBoxAdapter(child: empty)
                  else
                    SliverList.builder(itemCount: rows.rows.length, itemBuilder: (context, i) => _tile(i)),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
              );
            },
          ),
        ),
        footer,
      ],
    );
  }
}
