import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

/// The draggable divider between two resizable panels. A wide invisible hit
/// area around a hairline that lights up in the accent gradient while the
/// pointer is over it or dragging.
class SplitHandle extends StatefulWidget {
  /// Axis along which the *panels* are laid out: [Axis.horizontal] puts them
  /// side by side, so this handle is a vertical bar dragged left/right.
  final Axis axis;

  /// Pointer movement along [axis] since the last event, in logical pixels.
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;
  final VoidCallback? onReset;

  /// Space the handle occupies between the panels.
  final double thickness;

  const SplitHandle({
    super.key,
    required this.axis,
    required this.onDrag,
    this.onDragEnd,
    this.onReset,
    this.thickness = 10,
  });

  @override
  State<SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<SplitHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final horizontal = widget.axis == Axis.horizontal;
    final active = _hovered || _dragging;
    final line = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: horizontal ? (active ? 3 : 1) : null,
      height: horizontal ? null : (active ? 3 : 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: active
            ? LinearGradient(
                begin: horizontal ? Alignment.topCenter : Alignment.centerLeft,
                end: horizontal ? Alignment.bottomCenter : Alignment.centerRight,
                colors: [colors.mainAccent, colors.accentSecondary],
              )
            : null,
        color: active ? null : colors.border,
        boxShadow: active ? [BoxShadow(color: colors.glow, blurRadius: 8)] : null,
      ),
    );

    return MouseRegion(
      cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: horizontal ? (_) => setState(() => _dragging = true) : null,
        onHorizontalDragUpdate: horizontal ? (d) => widget.onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: horizontal ? (_) => _end() : null,
        onHorizontalDragCancel: horizontal ? _end : null,
        onVerticalDragStart: horizontal ? null : (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: horizontal ? null : (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: horizontal ? null : (_) => _end(),
        onVerticalDragCancel: horizontal ? null : _end,
        child: SizedBox(
          width: horizontal ? widget.thickness : null,
          height: horizontal ? null : widget.thickness,
          child: Center(child: line),
        ),
      ),
    );
  }

  void _end() {
    if (_dragging) setState(() => _dragging = false);
    widget.onDragEnd?.call();
  }
}
