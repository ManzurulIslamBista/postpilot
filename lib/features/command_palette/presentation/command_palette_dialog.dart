import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/method_badge.dart';
import '../domain/entities/palette_item.dart';
import '../domain/services/palette_search.dart';

/// One search box for everything: tools, requests (by name, URL, method or
/// body), environments and app actions. Arrow keys move, Enter runs, Esc closes.
class CommandPaletteDialog extends StatefulWidget {
  /// Items known immediately (tools, app actions).
  final List<PaletteItem> items;

  /// Items that need loading (every request of every collection).
  final Future<List<PaletteItem>> Function()? loadMore;

  /// Context of the screen that opened the palette: where chosen actions run.
  final BuildContext hostContext;

  /// Whether the app runs in a browser, which decides what each entry can do; only a test passes it.
  final bool web;

  const CommandPaletteDialog({super.key, required this.items, required this.hostContext, this.loadMore, this.web = kIsWeb});

  static Future<void> show(
    BuildContext context, {
    required List<PaletteItem> items,
    Future<List<PaletteItem>> Function()? loadMore,
  }) =>
      showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => CommandPaletteDialog(items: items, loadMore: loadMore, hostContext: context),
      );

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  static const _rowHeight = 50.0;

  final _query = TextEditingController();
  final _scroll = ScrollController();
  late List<PaletteItem> _all = widget.items;
  List<PaletteHit> _hits = const [];
  int _selected = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    final more = widget.loadMore;
    if (more != null) {
      _loading = true;
      more().then((extra) {
        if (!mounted) return;
        setState(() {
          _all = [...widget.items, ...extra];
          _loading = false;
          _refresh();
        });
      }).catchError((Object _) {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    _hits = PaletteSearch.search(_all, _query.text);
    _selected = 0;
  }

  void _move(int delta) {
    if (_hits.isEmpty) return;
    setState(() => _selected = (_selected + delta) % _hits.length);
    if (_selected < 0) _selected += _hits.length;
    final top = _selected * _rowHeight;
    if (!_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + viewport) {
      _scroll.jumpTo(top + _rowHeight - viewport);
    }
  }

  void _run(PaletteItem item) {
    // An entry this platform cannot do stays listed with its reason (see `_row`); running it would only fail.
    if (item.unavailableReason(web: widget.web) != null) return;
    final host = widget.hostContext;
    Navigator.of(context).pop();
    if (host.mounted) item.run(host);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);
    final empty = _query.text.trim().isEmpty;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: size.height * 0.1, left: 12, right: 12),
        child: Material(
          color: colors.surface,
          elevation: 18,
          shadowColor: Colors.black,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 660,
            constraints: BoxConstraints(maxHeight: size.height * 0.7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: colors.border)),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
                const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 20, color: colors.mainAccent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _query,
                            autofocus: true,
                            style: context.textStyles.body.copyWith(fontSize: 15),
                            decoration: const InputDecoration(
                              hintText: 'Search requests, tools, environments and actions…',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                            onChanged: (_) => setState(_refresh),
                            onSubmitted: (_) {
                              if (_hits.isNotEmpty) _run(_hits[_selected].item);
                            },
                          ),
                        ),
                        if (_loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                        _KeyCap('Esc'),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colors.border),
                  Flexible(
                    child: _hits.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              _loading ? 'Looking through your requests…' : 'Nothing matches "${_query.text}"',
                              style: context.textStyles.body.copyWith(color: colors.secondaryText),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            shrinkWrap: true,
                            itemExtent: _rowHeight,
                            itemCount: _hits.length,
                            itemBuilder: (context, i) => _row(context, i, empty),
                          ),
                  ),
                  Divider(height: 1, color: colors.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    child: Row(
                      children: [
                        _KeyCap('↑↓'),
                        const SizedBox(width: 6),
                        Text('move', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                        const SizedBox(width: 14),
                        _KeyCap('Enter'),
                        const SizedBox(width: 6),
                        Text('open', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                        const Spacer(),
                        Text('${_hits.length} results', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int i, bool empty) {
    final colors = context.colors;
    final hit = _hits[i];
    final item = hit.item;
    final selected = i == _selected;
    final showHeader = empty && (i == 0 || _hits[i - 1].item.category != item.category);
    final unavailable = item.unavailableReason(web: widget.web);
    final base = context.textStyles.body.copyWith(fontWeight: FontWeight.w600, color: unavailable == null ? null : colors.secondaryText);
    final subtitle = unavailable ?? item.subtitle;
    return InkWell(
      onTap: unavailable == null ? () => _run(item) : null,
      onHover: (h) {
        if (h && _selected != i) setState(() => _selected = i);
      },
      child: Container(
        color: selected ? colors.mainAccent.withValues(alpha: 0.13) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: item.badge != null
                  ? MethodBadge(method: item.badge!, width: 40)
                  : Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: colors.mainAccent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                      child: Icon(unavailable == null ? item.icon : Icons.lock_outline, size: 16, color: unavailable == null ? colors.mainAccent : colors.secondaryText),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: _highlight(item.title, hit.titlePositions, base, colors.mainAccent)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                ],
              ),
            ),
            if (showHeader || !empty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(item.category.label, style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontSize: 10.5)),
              ),
            if (item.shortcut != null) Padding(padding: const EdgeInsets.only(left: 8), child: _KeyCap(item.shortcut!)),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _highlight(String text, List<int> positions, TextStyle base, Color accent) {
    if (positions.isEmpty) return [TextSpan(text: text, style: base)];
    final set = positions.toSet();
    return [
      for (var i = 0; i < text.length; i++)
        TextSpan(text: text[i], style: set.contains(i) ? base.copyWith(color: accent, fontWeight: FontWeight.w800) : base),
    ];
  }
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap(this.label);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Text(label, style: context.textStyles.mono.copyWith(fontSize: 10.5, color: colors.secondaryText)),
    );
  }
}
