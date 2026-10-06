import 'variables/variable_text_controller.dart';
import 'variables/variable_text_form_field.dart';
import 'package:flutter/material.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/network/upload_file_source.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../graphql/presentation/graphql_explorer_dialog.dart';
import '../view_models/request_builder_view_model.dart';
import '../../domain/entities/key_value_item.dart';
import '../../domain/entities/request_body.dart';
import '../file_picker_service.dart';
import 'file_field.dart';
import '../../../odoo/domain/services/odoo_snippets.dart';
import '../../../odoo/presentation/widgets/odoo_request_tools.dart';
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

  /// Opens the file dialog for a form-data file row and a binary body; the platform's own when null.
  final FilePickerService? picker;

  /// Looks at the files of file rows and of a binary body; the platform's own when null.
  final UploadFileSource? uploadSource;

  const BodyEditor({super.key, required this.body, required this.onChanged, this.picker, this.uploadSource});

  @override
  State<BodyEditor> createState() => _BodyEditorState();
}

class _BodyEditorState extends State<BodyEditor> {
  late final _rawController = VariableTextEditingController(text: widget.body.rawText);
  late final FilePickerService _picker = widget.picker ?? FileSelectorPicker();
  final _rawFocus = FocusNode();
  String? _jsonError;

  /// Bumped when the schema explorer replaces the query, so the fields show the new text.
  int _graphqlRevision = 0;

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
    _rawController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onRawChanged(String text) {
    if (_jsonError != null) setState(() => _jsonError = null);
    widget.onChanged(widget.body.copyWith(rawText: text));
  }

  /// Puts [snippet] (a field picked from the Odoo fields list) into the body where the cursor is.
  void _insertSnippet(String snippet) {
    final selection = _rawController.selection;
    final text = _rawController.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final inserted = OdooSnippets.insert(text, start, end, snippet);
    _rawController.value = TextEditingValue(text: inserted.text, selection: TextSelection.collapsed(offset: inserted.cursor));
    _rawFocus.requestFocus();
    widget.onChanged(widget.body.copyWith(rawText: inserted.text));
  }

  /// The URL of the request being edited, when it is a call to Odoo: the body then gets the "Check against Odoo" and
  /// "Odoo fields" buttons. Null outside a request page.
  String? _odooUrl() {
    try {
      return context.read<RequestBuilderViewModel?>()?.request?.url;
    } on ProviderNotFoundException {
      return null;
    }
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
              if (_odooUrl() case final url?)
                OdooBodyTools(
                  url: url,
                  bodyText: () => _rawController.text,
                  onReplaceBody: (text) {
                    _setRawText(text);
                    widget.onChanged(widget.body.copyWith(rawText: text));
                  },
                  onInsert: _insertSnippet,
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
      BodyType.raw => VariableTextFormField(
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
        child: KeyValueEditor(
          items: body.formFields,
          allowFiles: true,
          picker: _picker,
          uploadSource: widget.uploadSource,
          onChanged: (v) => widget.onChanged(body.copyWith(formFields: v)),
        ),
      ),
      BodyType.urlEncoded => SingleChildScrollView(
        key: const ValueKey('url-encoded-fields'),
        child: KeyValueEditor(
          items: body.urlEncodedFields,
          onChanged: (v) => widget.onChanged(body.copyWith(urlEncodedFields: v)),
        ),
      ),
      BodyType.graphql => _graphqlEditor(context),
      BodyType.binary => SingleChildScrollView(key: const ValueKey('binary-body'), child: _binaryEditor(context)),
    };
  }

  /// One file sent as the whole body. Its reference is a nameless file row of the form fields (see
  /// [RequestBody.binaryFile]); emptying it removes the row again.
  Widget _binaryEditor(BuildContext context) {
    final file = widget.body.binaryFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The file is sent as the whole request body, byte for byte (an S3 PUT, an octet-stream upload). '
          'Set a Content-Type header to send another type than the one below.',
          style: context.textStyles.caption,
        ),
        const SizedBox(height: 8),
        FileField(
          key: const ValueKey('binary-file'),
          path: file?.value ?? '',
          fileName: file?.fileName ?? '',
          contentType: file?.contentType ?? '',
          picker: _picker,
          source: widget.uploadSource,
          showFileName: false,
          onChanged: ({path, fileName, contentType}) {
            final current = widget.body.binaryFile ?? KeyValueItem(key: '', value: '', kind: FormFieldKind.file);
            final next = current.copyWith(value: path, fileName: fileName, contentType: contentType);
            final empty = next.value.isEmpty && next.fileName.isEmpty && next.contentType.isEmpty;
            widget.onChanged(widget.body.withBinaryFile(empty ? null : next));
          },
        ),
      ],
    );
  }

  /// Opens the schema explorer for this request's endpoint; "Use in request" fills the query and variables.
  void _exploreSchema() {
    String url = '';
    var headers = '';
    try {
      final request = context.read<RequestBuilderViewModel>().request;
      url = request?.url ?? '';
      headers = [for (final h in request?.headers ?? const []) if (h.enabled && h.key.isNotEmpty) '${h.key}: ${h.value}'].join('\n');
    } on ProviderNotFoundException {
      // Used outside a request page: the explorer simply starts empty.
    }
    GraphqlExplorerDialog.show(
      context,
      initialUrl: url,
      initialHeaders: headers,
      onUse: (query, variables) {
        widget.onChanged(widget.body.copyWith(graphqlQuery: query, graphqlVariables: variables));
        setState(() => _graphqlRevision++);
      },
    );
  }

  Widget _graphqlEditor(BuildContext context) {
    final body = widget.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Query', style: context.textStyles.caption),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: _exploreSchema,
              icon: const Icon(Icons.hexagon_outlined, size: 15),
              label: const Text('Explore schema'),
            ),
          ],
        ),
        Expanded(
          flex: 2,
          child: VariableTextFormField(
            key: ValueKey('gq-$_graphqlRevision'),
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
          child: VariableTextFormField(
            key: ValueKey('gv-$_graphqlRevision'),
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
