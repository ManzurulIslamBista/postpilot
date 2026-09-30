import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import 'simple_markdown.dart';

/// A text box for Markdown with an Edit / Preview switch. It takes its text
/// once, from [initialValue], and reports every change; it grows with its text
/// and is meant to sit inside a scroll view.
class MarkdownEditor extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
  final String hintText;
  final int minLines;

  const MarkdownEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.hintText = 'Write in Markdown: **bold**, `code`, lists, tables, [links](https://…)',
    this.minLines = 8,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);
  bool _preview = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.edit_outlined, size: 16), label: Text('Edit')),
            ButtonSegment(value: true, icon: Icon(Icons.visibility_outlined, size: 16), label: Text('Preview')),
          ],
          selected: {_preview},
          onSelectionChanged: (selection) => setState(() => _preview = selection.first),
        ),
        const SizedBox(height: 8),
        if (_preview)
          Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: widget.minLines * 20.0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: context.colors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _controller.text.trim().isEmpty
                ? Text('Nothing to preview yet.', style: context.textStyles.caption.copyWith(color: context.colors.secondaryText))
                : SimpleMarkdown(data: _controller.text),
          )
        else
          TextField(
            key: const ValueKey('markdown-editor-field'),
            controller: _controller,
            minLines: widget.minLines,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: context.textStyles.mono,
            decoration: InputDecoration(hintText: widget.hintText),
            onChanged: widget.onChanged,
          ),
      ],
    );
  }
}
