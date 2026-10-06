import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/services/collection_order.dart';

/// What a sidebar row hands over when it is picked up.
final class SidebarDragItem {
  final OrderRef ref;
  final int collectionId;

  /// The folder it sits in now; null at the collection's top level.
  final int? parentFolderId;
  final String name;
  final IconData icon;

  const SidebarDragItem({
    required this.ref,
    required this.collectionId,
    required this.parentFolderId,
    required this.name,
    required this.icon,
  });
}

/// Where a drop would put the dragged item: into [parentFolderId] of [collectionId] (null = the collection's top
/// level), in front of [before] (the end when null).
final class DropSpot {
  final int collectionId;
  final int? parentFolderId;
  final OrderRef? before;

  const DropSpot(this.collectionId, this.parentFolderId, [this.before]);
}

/// Which part of a row the pointer is over.
enum DropZone { before, into, after }

/// How a row divides its height between the three zones.
enum DropLayout {
  /// Upper half = in front of the request, lower half = behind it.
  request,

  /// Top quarter = in front, bottom quarter = behind, the middle = into the folder.
  folder,

  /// The whole row means "into": a collection, or the "nothing here yet" line of a folder.
  container;

  DropZone zoneAt(double fraction) => switch (this) {
    DropLayout.request => fraction < 0.5 ? DropZone.before : DropZone.after,
    DropLayout.folder => fraction < 0.25 ? DropZone.before : (fraction > 0.75 ? DropZone.after : DropZone.into),
    DropLayout.container => DropZone.into,
  };
}

/// Drag bookkeeping the rows share: scrolls the list while an item is held near its top or bottom edge, so a long
/// tree can be reached without dropping first.
final class SidebarDragState {
  final ScrollController scroll;

  /// Key of the widget that holds the scrolling list, to know where its edges are on screen.
  final GlobalKey viewportKey;
  Timer? _timer;
  double _velocity = 0;

  SidebarDragState({required this.scroll, required this.viewportKey});

  static const _edge = 56.0;
  static const _maxStep = 14.0;

  void update(Offset globalPosition) {
    final box = viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return stop();
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    if (globalPosition.dy < top + _edge) {
      _velocity = -_maxStep * (1 - ((globalPosition.dy - top) / _edge).clamp(0.0, 1.0));
    } else if (globalPosition.dy > bottom - _edge) {
      _velocity = _maxStep * ((globalPosition.dy - (bottom - _edge)) / _edge).clamp(0.0, 1.0);
    } else {
      _velocity = 0;
    }
    if (_velocity == 0) return stop();
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _step());
  }

  void _step() {
    if (!scroll.hasClients) return;
    final position = scroll.position;
    final next = (position.pixels + _velocity).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next != position.pixels) scroll.jumpTo(next);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _velocity = 0;
  }

  void dispose() => stop();
}

/// A sidebar row that can be picked up (when [item] is given) and dropped on: it draws where the drop would land
/// (a line in front of or behind the row, or a highlight for "into") and reports the drop.
///
/// Picking up is a press-and-hold, so it works with a finger, where a plain drag scrolls the list, and with a
/// mouse. Whatever the drop would break (a folder into itself) is refused up front, so it never highlights.
class SidebarDndRow extends StatefulWidget {
  final bool enabled;
  final SidebarDragItem? item;
  final DropLayout layout;
  final bool Function(SidebarDragItem dragged) accepts;
  final DropSpot Function(DropZone zone) spotFor;
  final void Function(SidebarDragItem dragged, DropSpot spot) onDrop;

  /// Called when an item has been held over the middle of the row for a moment: opens a closed folder.
  final VoidCallback? onHoverOpen;
  final SidebarDragState? drag;
  final Widget child;

  const SidebarDndRow({
    super.key,
    required this.enabled,
    required this.layout,
    required this.accepts,
    required this.spotFor,
    required this.onDrop,
    required this.child,
    this.item,
    this.onHoverOpen,
    this.drag,
  });

  /// How long a row has to be held before it lifts.
  static const holdToDrag = Duration(milliseconds: 250);

  /// How long an item has to rest on a closed folder before it opens.
  static const hoverToOpen = Duration(milliseconds: 600);

  @override
  State<SidebarDndRow> createState() => _SidebarDndRowState();
}

class _SidebarDndRowState extends State<SidebarDndRow> {
  DropZone? _zone;
  Timer? _openTimer;

  @override
  void dispose() {
    _openTimer?.cancel();
    super.dispose();
  }

  DropZone _zoneAt(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.height == 0) return DropZone.into;
    final local = box.globalToLocal(globalPosition);
    return widget.layout.zoneAt((local.dy / box.size.height).clamp(0.0, 1.0));
  }

  void _moved(DragTargetDetails<SidebarDragItem> details) {
    final zone = _zoneAt(details.offset);
    if (zone == _zone) return;
    setState(() => _zone = zone);
    _openTimer?.cancel();
    final open = widget.onHoverOpen;
    if (zone == DropZone.into && open != null) _openTimer = Timer(SidebarDndRow.hoverToOpen, open);
  }

  void _clear() {
    _openTimer?.cancel();
    if (_zone != null && mounted) setState(() => _zone = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final zone = _zone;
    final target = DragTarget<SidebarDragItem>(
      onWillAcceptWithDetails: (details) => widget.accepts(details.data),
      onMove: _moved,
      onLeave: (_) => _clear(),
      onAcceptWithDetails: (details) {
        final dropZone = _zoneAt(details.offset);
        _clear();
        widget.onDrop(details.data, widget.spotFor(dropZone));
      },
      builder: (context, candidates, rejected) => Stack(
        children: [
          widget.child,
          if (zone != null && candidates.isNotEmpty)
            Positioned.fill(child: IgnorePointer(child: _DropIndicator(zone: zone))),
        ],
      ),
    );
    final item = widget.item;
    if (item == null) return target;
    return LongPressDraggable<SidebarDragItem>(
      data: item,
      delay: SidebarDndRow.holdToDrag,
      maxSimultaneousDrags: 1,
      // The pointer is the drop point, so a row reads the zone straight from where it is.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(item: item),
      childWhenDragging: Opacity(opacity: 0.35, child: target),
      onDragUpdate: (details) => widget.drag?.update(details.globalPosition),
      onDragEnd: (_) => widget.drag?.stop(),
      child: target,
    );
  }
}

class _DropIndicator extends StatelessWidget {
  final DropZone zone;
  const _DropIndicator({required this.zone});

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.mainAccent;
    return switch (zone) {
      DropZone.into => DecoratedBox(
        key: const ValueKey('drop-into'),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          border: Border.all(color: accent, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      DropZone.before => Align(
        alignment: Alignment.topCenter,
        child: Container(key: const ValueKey('drop-before'), height: 2, color: accent),
      ),
      DropZone.after => Align(
        alignment: Alignment.bottomCenter,
        child: Container(key: const ValueKey('drop-after'), height: 2, color: accent),
      ),
    };
  }
}

/// The name under the pointer while a row is carried.
class _DragFeedback extends StatelessWidget {
  final SidebarDragItem item;
  const _DragFeedback({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: Transform.translate(
        offset: const Offset(14, 10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.mainAccent),
            boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 16, color: colors.primaryText),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.body.copyWith(color: colors.primaryText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
