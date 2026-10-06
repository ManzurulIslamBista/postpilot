import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../odoo/presentation/widgets/smart_reference_hover_card.dart';
import '../../view_models/variable_scope.dart';
import '../json_syntax.dart' show maxHighlightedChars;
import 'variable_hover_card.dart';
import 'variable_text_controller.dart';

/// A [TextFormField] that understands `{{variables}}`: each token is coloured
/// (accent when defined, red when not) and hovering one shows its current value
/// and where it comes from. A drop-in for `TextFormField(initialValue: ...)`:
/// the typed text is the raw `{{name}}` text, nothing is substituted.
///
/// Outside a [VariableScope] (a dialog that is not about a request) it behaves
/// as a plain text field.
class VariableTextFormField extends StatefulWidget {
  final String? initialValue;

  /// Use instead of [initialValue] when the caller keeps the controller. Tokens
  /// are only coloured when it is a [VariableTextEditingController]; the hover
  /// works with any.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextStyle? style;
  final bool obscureText;
  final int? maxLines;
  final bool expands;
  final TextAlignVertical? textAlignVertical;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  const VariableTextFormField({
    super.key,
    this.initialValue,
    this.controller,
    this.focusNode,
    this.decoration,
    this.style,
    this.obscureText = false,
    this.maxLines = 1,
    this.expands = false,
    this.textAlignVertical,
    this.onChanged,
    this.onFieldSubmitted,
  }) : assert(initialValue == null || controller == null, 'Pass either initialValue or controller');

  @override
  State<VariableTextFormField> createState() => _VariableTextFormFieldState();
}

class _VariableTextFormFieldState extends State<VariableTextFormField> {
  static const _hoverDelay = Duration(milliseconds: 280);

  late final TextEditingController _controller;
  late final bool _ownsController;
  VariableScope? _scope;

  Timer? _hoverTimer;
  OverlayEntry? _card;
  String? _hoverKey;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? VariableTextEditingController(text: widget.initialValue);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `read`, not `watch`: the scope repaints the tokens itself, through the controller.
    _scope = context.read<VariableScope?>();
    final controller = _controller;
    if (controller is VariableTextEditingController) controller.scope = _scope;
  }

  @override
  void dispose() {
    _hide();
    final controller = _controller;
    if (controller is VariableTextEditingController) controller.scope = null;
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _onHover,
      onExit: (_) => _hide(),
      child: TextFormField(
        controller: _controller,
        focusNode: widget.focusNode,
        decoration: widget.decoration,
        style: widget.style,
        obscureText: widget.obscureText,
        maxLines: widget.obscureText ? 1 : widget.maxLines,
        expands: widget.expands,
        textAlignVertical: widget.textAlignVertical,
        onChanged: (value) {
          _hide();
          widget.onChanged?.call(value);
        },
        onFieldSubmitted: widget.onFieldSubmitted,
      ),
    );
  }

  // --- hover ----------------------------------------------------------------

  void _onHover(PointerHoverEvent event) {
    if (_scope == null) return;
    final token = _tokenAt(event.position);
    if (token == null) {
      _hide();
      return;
    }
    // Still on the token already shown, or already waiting to show.
    if (token.key == _hoverKey) return;
    _hide();
    _hoverKey = token.key;
    _hoverTimer = Timer(_hoverDelay, () => _show(token));
  }

  Future<void> _show(_Token token) async {
    final scope = _scope;
    if (scope == null) return;
    // Fresh values, in case a variable was edited since the scope last looked. (An Odoo reference has no value to read.)
    if (!token.smart) await scope.refresh();
    if (!mounted || _hoverKey != token.key) return;
    final screen = MediaQuery.sizeOf(context);
    final cardWidth = token.smart ? SmartReferenceHoverCard.width : VariableHoverCard.width;
    final left = token.rect.left.clamp(8.0, math.max(8.0, screen.width - cardWidth - 8)).toDouble();
    // Under the token, or over it when there is no room below.
    final below = token.rect.bottom + 6;
    final fitsBelow = below + 150 < screen.height;
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: fitsBelow ? below : null,
        bottom: fitsBelow ? null : screen.height - token.rect.top + 6,
        child: token.smart ? SmartReferenceHoverCard(keyText: token.name) : VariableHoverCard(info: scope.describe(token.name)),
      ),
    );
    Overlay.of(context).insert(entry);
    _card = entry;
  }

  void _hide() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _hoverKey = null;
    _card?.remove();
    _card = null;
  }

  /// The `{{token}}` under [globalPosition], or null when the pointer is over
  /// plain text, empty space, or a masked (password) field.
  _Token? _tokenAt(Offset globalPosition) {
    if (widget.obscureText) return null;
    final text = _controller.text;
    if (!text.contains('{{') || text.length > maxHighlightedChars) return null;
    final render = _editable()?.renderEditable;
    if (render == null || !render.attached || !render.hasSize) return null;

    final local = render.globalToLocal(globalPosition);
    for (final match in VariableTextEditingController.tokenPattern.allMatches(text)) {
      final boxes = render.getBoxesForSelection(TextSelection(baseOffset: match.start, extentOffset: match.end));
      for (final box in boxes) {
        final rect = box.toRect();
        if (!rect.inflate(2).contains(local)) continue;
        return _Token(
          key: '${match.start}:${match[1] ?? match[2]}',
          name: match[1] ?? match[2]!,
          smart: match[1] == null,
          rect: Rect.fromPoints(render.localToGlobal(rect.topLeft), render.localToGlobal(rect.bottomRight)),
        );
      }
    }
    return null;
  }

  /// The text input inside the field; Flutter exposes no handle to it.
  EditableTextState? _editable() {
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }
}

class _Token {
  /// Start offset + name: two uses of one variable are different hover targets.
  final String key;
  final String name;

  /// An Odoo smart reference (`xmlid:base.main_company`), whose [name] is the whole inner text.
  final bool smart;

  /// The token's box on screen.
  final Rect rect;
  const _Token({required this.key, required this.name, this.smart = false, required this.rect});
}
