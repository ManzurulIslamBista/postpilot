import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../../domain/entities/odoo_model_info.dart';
import '../../domain/entities/odoo_request_shape.dart';
import '../../domain/services/odoo_snippets.dart';
import '../view_models/odoo_check_view_model.dart';
import '../view_models/odoo_studio_view_model.dart';
import 'odoo_check_tab.dart';

/// Two buttons for the body of a request that calls Odoo: "Check" compares the body with the live schema of the model
/// (with one-click fixes), and "Fields" lists the model's fields to put one into the body, since the body editor itself
/// cannot offer suggestions while typing. Shows nothing for a request that is not an Odoo call.
class OdooBodyTools extends StatelessWidget {
  final String url;

  /// The body as it is now; read when a button is pressed.
  final String Function() bodyText;

  /// A checked body that the person accepted.
  final ValueChanged<String> onReplaceBody;

  /// A field the person picked, as JSON text for a body (`"name": ""`).
  final ValueChanged<String> onInsert;

  const OdooBodyTools({super.key, required this.url, required this.bodyText, required this.onReplaceBody, required this.onInsert});

  @override
  Widget build(BuildContext context) {
    if (!OdooRequestShape.looksLikeOdoo(url) || !locator.isRegistered<OdooStudioViewModel>()) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: () async {
            final fixed = await OdooCheckDialog.show(context, url: url, body: bodyText());
            if (fixed != null) onReplaceBody(fixed);
          },
          icon: const Icon(Icons.fact_check_outlined, size: 16),
          label: const Text('Check against Odoo'),
        ),
        TextButton.icon(
          onPressed: () async {
            final snippet = await OdooFieldPickerDialog.show(context, url: url);
            if (snippet != null) onInsert(snippet);
          },
          icon: const Icon(Icons.list_alt_outlined, size: 16),
          label: const Text('Odoo fields'),
        ),
      ],
    );
  }
}

/// The request checker for one request: its URL says the model and the method, its body is what is checked. Closing
/// with "Use this body" hands the (fixed) body back.
class OdooCheckDialog extends StatefulWidget {
  final String url;
  final String body;
  const OdooCheckDialog({super.key, required this.url, required this.body});

  /// The body to put into the request, or null when the person closed without taking one.
  static Future<String?> show(BuildContext context, {required String url, required String body}) =>
      ToolDialog.show<String>(context, (_) => OdooCheckDialog(url: url, body: body));

  @override
  State<OdooCheckDialog> createState() => _OdooCheckDialogState();
}

class _OdooCheckDialogState extends State<OdooCheckDialog> {
  late final OdooStudioViewModel _studio = locator<OdooStudioViewModel>();
  late final OdooCheckViewModel _vm = OdooCheckViewModel(_studio, url: widget.url, body: widget.body);

  @override
  void initState() {
    super.initState();
    // The active environment says which server to ask; then the request is checked at once.
    _studio.loadFromActiveEnvironment().then((_) {
      if (mounted) _vm.run();
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    _studio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => ToolDialog(
        icon: Icons.fact_check_outlined,
        title: 'Check against Odoo',
        subtitle: 'The body compared with the fields the server describes',
        width: 980,
        height: 640,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: _vm.bodyChanged ? () => Navigator.pop(context, _vm.bodyText) : null,
            child: const Text('Use this body'),
          ),
        ],
        footerLeading: Text(
          _studio.connection.missing ?? 'Server: ${_studio.connection.normalizedUrl}${_studio.connection.database.isEmpty ? '' : ' · ${_studio.connection.database}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
        ),
        child: OdooCheckPanel(viewModel: _vm),
      ),
    );
  }
}

/// Lists the fields of the model a request calls, to put one into the body. The model comes from the URL; the fields
/// are the ones the server describes (remembered per server, with a refresh).
class OdooFieldPickerDialog extends StatefulWidget {
  final String url;
  const OdooFieldPickerDialog({super.key, required this.url});

  /// The JSON text of the field picked (`"name": ""`), or null.
  static Future<String?> show(BuildContext context, {required String url}) =>
      ToolDialog.show<String>(context, (_) => OdooFieldPickerDialog(url: url));

  @override
  State<OdooFieldPickerDialog> createState() => _OdooFieldPickerDialogState();
}

class _OdooFieldPickerDialogState extends State<OdooFieldPickerDialog> {
  late final OdooStudioViewModel _studio = locator<OdooStudioViewModel>();
  final _filter = TextEditingController();
  OdooModelInfo? _info;
  String? _error;
  bool _loading = true;

  String get _model => OdooRequestShape.ofUrl(widget.url)?.model ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    await _studio.loadFromActiveEnvironment();
    final missing = _studio.connection.missing;
    if (_model.isEmpty) {
      _error = 'The model is not known yet: the URL holds a variable where the model goes.';
    } else if (missing != null) {
      _error = missing;
    } else {
      final found = await _studio.schema.fields(_studio.connection, _model, refresh: refresh);
      _info = found.value;
      _error = found.error;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _filter.dispose();
    _studio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = _info;
    final q = _filter.text.trim().toLowerCase();
    final fields = info == null ? const <OdooField>[] : [for (final f in info.fields) if (!f.isMagic && (q.isEmpty || f.name.contains(q) || f.label.toLowerCase().contains(q))) f];
    return ToolDialog(
      icon: Icons.list_alt_outlined,
      title: 'Fields of ${_model.isEmpty ? 'the model' : _model}',
      subtitle: 'Pick one to put it into the body at the cursor',
      width: 560,
      height: 600,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: TextField(controller: _filter, decoration: const InputDecoration(isDense: true, hintText: 'Filter fields', prefixIcon: Icon(Icons.search, size: 16)), onChanged: (_) => setState(() {}))),
                IconButton(icon: const Icon(Icons.refresh, size: 18), tooltip: 'Read the fields again from the server', onPressed: _loading ? null : () => _load(refresh: true)),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null) InfoBanner(kind: BannerKind.warning, message: _error!),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: fields.length,
                      itemBuilder: (context, i) {
                        final f = fields[i];
                        return ListTile(
                          dense: true,
                          title: Row(
                            children: [
                              Flexible(child: Text(f.name, overflow: TextOverflow.ellipsis, style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w600))),
                              if (f.required) Text(' *', style: TextStyle(color: colors.statusError, fontWeight: FontWeight.w800)),
                            ],
                          ),
                          subtitle: Text(
                            '${f.type}${f.relation != null ? ' → ${f.relation}' : ''} · ${f.label}${f.readonly ? ' · read-only' : ''}${f.stored ? '' : ' · computed'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, OdooSnippets.fieldSnippet(f)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
