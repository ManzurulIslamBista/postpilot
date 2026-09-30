import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/services/tag_normalizer.dart';

/// Tag chips with a field to add more. A tag is added with Enter or a comma
/// (or when the field loses focus), removed with the chip's x; tags already in
/// use elsewhere are offered as suggestions.
class TagsEditor extends StatefulWidget {
  final List<String> tags;
  final List<String> suggestions;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  const TagsEditor({
    super.key,
    required this.tags,
    required this.suggestions,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  State<TagsEditor> createState() => _TagsEditorState();
}

class _TagsEditorState extends State<TagsEditor> {
  static const _maxSuggestions = 12;

  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.removeListener(_onTextChange);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChange() => setState(() {});

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit(_controller.text);
  }

  void _commit(String raw) {
    final tag = raw.trim();
    _controller.clear();
    if (tag.isNotEmpty) widget.onAdd(tag);
  }

  void _onChanged(String text) {
    if (!text.contains(',')) return;
    final parts = text.split(',');
    for (final part in parts.take(parts.length - 1)) {
      if (part.trim().isNotEmpty) widget.onAdd(part.trim());
    }
    final rest = parts.last;
    _controller.value = TextEditingValue(text: rest, selection: TextSelection.collapsed(offset: rest.length));
  }

  void _submit(String text) {
    _commit(text);
    _focus.requestFocus();
  }

  List<String> get _visibleSuggestions {
    final typed = _controller.text.trim().toLowerCase();
    return [
      for (final tag in widget.suggestions)
        if (!widget.tags.any((t) => TagNormalizer.same(t, tag)) && (typed.isEmpty || tag.toLowerCase().contains(typed))) tag,
    ].take(_maxSuggestions).toList();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _visibleSuggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in widget.tags)
                InputChip(
                  key: ValueKey('tag-$tag'),
                  label: Text(tag, style: context.textStyles.caption),
                  visualDensity: VisualDensity.compact,
                  deleteIcon: const Icon(Icons.close, size: 14),
                  deleteButtonTooltipMessage: 'Remove tag',
                  onDeleted: () => widget.onRemove(tag),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          key: const ValueKey('tags-editor-field'),
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Add a tag, then press Enter or type a comma',
            prefixIcon: Icon(Icons.sell_outlined, size: 16),
          ),
          onChanged: _onChanged,
          onSubmitted: _submit,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Suggestions', style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
              for (final tag in suggestions)
                ActionChip(
                  key: ValueKey('suggestion-$tag'),
                  label: Text(tag, style: context.textStyles.caption),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onAdd(tag),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
