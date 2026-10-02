import 'package:flutter/material.dart';
import 'split_handle.dart';

/// Two panels with a draggable divider between them. [fraction] is the share
/// of the space the [first] panel takes; both panels keep at least their
/// minimum size however the divider is dragged or the window is resized.
class ResizableSplit extends StatelessWidget {
  final Axis axis;
  final Widget first;
  final Widget second;
  final double fraction;
  final double minFirst;
  final double minSecond;
  final ValueChanged<double> onFractionChanged;
  final VoidCallback? onDragEnd;
  final VoidCallback? onReset;

  const ResizableSplit({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
    required this.fraction,
    required this.onFractionChanged,
    this.minFirst = 280,
    this.minSecond = 280,
    this.onDragEnd,
    this.onReset,
  });

  static const _handle = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = axis == Axis.horizontal;
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final available = total - _handle;
        // Window too small for both minimums: split evenly instead of overflowing.
        final tooSmall = available < minFirst + minSecond;
        final firstSize = tooSmall ? available / 2 : (available * fraction).clamp(minFirst, available - minSecond);

        final handle = SplitHandle(
          axis: axis,
          thickness: _handle,
          onDrag: (delta) {
            if (available <= 0) return;
            onFractionChanged((firstSize + delta) / available);
          },
          onDragEnd: onDragEnd,
          onReset: onReset,
        );
        final children = [
          SizedBox(width: horizontal ? firstSize : null, height: horizontal ? null : firstSize, child: first),
          handle,
          Expanded(child: second),
        ];
        return horizontal ? Row(children: children) : Column(children: children);
      },
    );
  }
}
