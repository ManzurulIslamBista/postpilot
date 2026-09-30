import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../shell_view_model.dart';

const _tabBarHeight = 36.0;
const _maxTabWidth = 200.0;

/// Postman-style strip of open request tabs. Click selects, the close icon or
/// a middle-click closes. Tabs beyond the visible width scroll with the mouse
/// wheel or the scrollbar.
class RequestTabBar extends StatefulWidget {
  const RequestTabBar({super.key});

  @override
  State<RequestTabBar> createState() => _RequestTabBarState();
}

class _RequestTabBarState extends State<RequestTabBar> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // A horizontal scrollable ignores a plain mouse wheel (it reports only a
  // vertical delta), which would leave overflowed tabs out of reach. Claims the
  // event through the resolver so the scrollable's own handling (Shift+wheel,
  // horizontal deltas) still wins when it applies.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + event.scrollDelta.dy).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      _scrollController.jumpTo(target);
      event.respond(allowPlatformDefault: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellViewModel>();
    final ids = shell.openRequestIds;
    if (ids.isEmpty) return const SizedBox.shrink();

    return Container(
      height: _tabBarHeight,
      decoration: BoxDecoration(
        color: context.colors.sidebarBackground,
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final id in ids)
                  _RequestTab(
                    key: ValueKey(id),
                    summary: shell.tabSummary(id),
                    isActive: id == shell.selectedRequestId,
                    onSelect: () => shell.selectRequest(id),
                    onClose: () => shell.closeRequest(id),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestTab extends StatefulWidget {
  final RequestSummaryEntity? summary;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _RequestTab({
    super.key,
    required this.summary,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<_RequestTab> createState() => _RequestTabState();
}

class _RequestTabState extends State<_RequestTab> {
  @override
  void initState() {
    super.initState();
    if (widget.isActive) _scrollIntoView();
  }

  @override
  void didUpdateWidget(covariant _RequestTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _scrollIntoView();
  }

  // Deferred a frame: a freshly opened tab has no render box yet, and it is
  // appended at the far end of the strip, out of view.
  void _scrollIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scrollable.ensureVisible(context, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final summary = widget.summary;
    return GestureDetector(
      onTertiaryTapUp: (_) => widget.onClose(),
      child: InkWell(
        onTap: widget.onSelect,
        child: Container(
          constraints: const BoxConstraints(maxWidth: _maxTabWidth),
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: widget.isActive ? colors.surface : null,
            border: Border(
              right: BorderSide(color: colors.border),
              bottom: BorderSide(color: widget.isActive ? colors.mainAccent : Colors.transparent, width: 2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (summary != null) ...[
                Text(
                  summary.method.label,
                  style: TextStyle(
                    color: colors.forMethod(summary.method.label),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  summary?.name ?? '…',
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.body.copyWith(
                    color: widget.isActive ? colors.primaryText : colors.secondaryText,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                tooltip: 'Close',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
