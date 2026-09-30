import 'package:flutter/material.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/request_body.dart';
import 'json_body_format.dart';
import 'key_value_editor.dart';

/// Plain-text body editor for the MVP. A syntax-highlighted code editor
/// (e.g. re_editor) is a good drop-in upgrade later — verify its exact
/// controller API before wiring it in.
///
/// The raw field has a controller (Beautify/Minify replace its text), which
/// stays the source of truth while the user types: it is only overwritten
/// from [body] when [body] holds different text than the field does, i.e.
/// when something other than this field changed it.
class BodyEditor extends StatefulWidget {
  final RequestBody body;
  final ValueChanged<RequestBody> onChanged;

  const BodyEditor({super.key, required this.body, required this.onChanged});

  @override
  State<BodyEditor> createState() => _BodyEditorState();
}

class _BodyEditorState extends State<BodyEditor> {
  late final _rawController = TextEditingController(text: widget.body.rawText);
  final _rawFocus = FocusNode();
  String? _jsonError;

  @override
  void didUpdateWidget(covariant BodyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.body.rawText;
    if (text != _rawController.text) _setRawText(text);
    if (oldWidget.body.type != widget.body.type || oldWidget.body.rawContentType != widget.body.rawContentType) {
      _jsonError = null;
    }
  }

  @override
  void dispose() {
    _rawController.dispose();
    _rawFocus.dispose();
    super.dispose();
  }

  void _setRawText(String text) {
    _rawController.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _onRawChanged(String text) {
    if (_jsonError != null) setState(() => _jsonError = null);
    widget.onChanged(widget.body.copyWith(rawText: text));
  }

  void _reformat(JsonFormatResult Function(String source) format) {
    final result = format(_rawController.text);
    final formatted = result.text;
    if (formatted == null) {
      setState(() => _jsonError = result.error);
      return;
    }
    final changed = formatted != _rawController.text;
    if (changed) _setRawText(formatted);
    _rawFocus.requestFocus();
    setState(() => _jsonError = null);
    if (changed) widget.onChanged(widget.body.copyWith(rawText: formatted));
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    final isJson = body.type == BodyType.raw && body.rawContentType == RawContentType.json;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<BodyType>(
              value: body.type,
              onChanged: (t) => t == null ? null : widget.onChanged(body.copyWith(type: t)),
              items: [for (final t in BodyType.values) DropdownMenuItem(value: t, child: Text(t.label))],
            ),
            if (body.type == BodyType.raw)
              DropdownButton<RawContentType>(
                value: body.rawContentType,
                onChanged: (t) => t == null ? null : widget.onChanged(body.copyWith(rawContentType: t)),
                items: [
                  for (final t in RawContentType.values) DropdownMenuItem(value: t, child: Text(t.name.toUpperCase())),
                ],
              ),
            if (isJson) ...[
              TextButton.icon(
                onPressed: () => _reformat(JsonBodyFormat.beautify),
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Beautify'),
              ),
              TextButton.icon(
                onPressed: () => _reformat(JsonBodyFormat.minify),
                icon: const Icon(Icons.compress, size: 16),
                label: const Text('Minify'),
              ),
            ],
          ],
        ),
        if (_jsonError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(_jsonError!, style: context.textStyles.caption.copyWith(color: context.colors.statusError)),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(child: _editorFor(context)),
      ],
    );
  }

  Widget _editorFor(BuildContext context) {
    final body = widget.body;
    return switch (body.type) {
      BodyType.none => const SizedBox.shrink(),
      BodyType.raw => TextFormField(
          controller: _rawController,
          focusNode: _rawFocus,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: context.textStyles.mono,
          decoration: const InputDecoration(border: OutlineInputBorder(), alignLabelWithHint: true),
          onChanged: _onRawChanged,
        ),
      // Distinct keys: both are the same widget at the same spot, and a state
      // left in "Bulk edit" must not carry over from one list to the other.
      BodyType.formData => SingleChildScrollView(
          key: const ValueKey('form-data-fields'),
          child: KeyValueEditor(items: body.formFields, onChanged: (v) => widget.onChanged(body.copyWith(formFields: v))),
        ),
      BodyType.urlEncoded => SingleChildScrollView(
          key: const ValueKey('url-encoded-fields'),
          child: KeyValueEditor(
            items: body.urlEncodedFields,
            onChanged: (v) => widget.onChanged(body.copyWith(urlEncodedFields: v)),
          ),
        ),
      BodyType.graphql => _graphqlEditor(context),
    };
  }

  Widget _graphqlEditor(BuildContext context) {
    final body = widget.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Query', style: context.textStyles.caption),
        const SizedBox(height: 4),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: body.graphqlQuery,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: context.textStyles.mono,
            decoration: const InputDecoration(border: OutlineInputBorder(), alignLabelWithHint: true),
            onChanged: (v) => widget.onChanged(body.copyWith(graphqlQuery: v)),
          ),
        ),
        const SizedBox(height: 12),
        Text('Variables (JSON)', style: context.textStyles.caption),
        const SizedBox(height: 4),
        Expanded(
          child: TextFormField(
            initialValue: body.graphqlVariables,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: context.textStyles.mono,
            decoration: const InputDecoration(border: OutlineInputBorder(), alignLabelWithHint: true),
            onChanged: (v) => widget.onChanged(body.copyWith(graphqlVariables: v)),
          ),
        ),
      ],
    );
  }
}
