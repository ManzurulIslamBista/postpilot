import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/context_theme_extensions.dart';

/// A read-only, selectable code panel with a language label and a Copy button,
/// used wherever a tool produces text (generated Dart, cURL, a bug report).
class CodeBlock extends StatefulWidget {
  final String text;

  /// Shown top-left, e.g. "Dart" or "JSON".
  final String? label;

  /// Wraps long lines instead of scrolling sideways.
  final bool wrap;
  final String copyMessage;

  /// Extra buttons placed beside Copy.
  final List<Widget> actions;

  const CodeBlock({
    super.key,
    required this.text,
    this.label,
    this.wrap = false,
    this.copyMessage = 'Copied',
    this.actions = const [],
  });

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = SelectableText(widget.text, style: context.textStyles.mono);
    return Container(
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Row(
              children: [
                // The label gives way (and ends in "…") when a long one, such as a file path, meets a narrow screen.
                Expanded(
                  child: Text(
                    (widget.label ?? '').toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.caption.copyWith(
                      color: colors.secondaryText,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...widget.actions,
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: _copied ? colors.statusSuccess : colors.secondaryText,
                  ),
                  onPressed: widget.text.isEmpty ? null : _copy,
                  icon: Icon(_copied ? Icons.check : Icons.copy, size: 14),
                  label: Text(_copied ? widget.copyMessage : 'Copy', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: widget.wrap
                    ? text
                    : SingleChildScrollView(scrollDirection: Axis.horizontal, child: text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
