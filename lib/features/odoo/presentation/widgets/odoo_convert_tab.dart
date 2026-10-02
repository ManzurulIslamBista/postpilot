import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/code_block.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../domain/services/odoo_json2.dart';
import '../../domain/services/odoo_rpc_converter.dart';
import '../view_models/odoo_studio_view_model.dart';

/// Migrates old calls. Paste an `execute_kw` line, a `/jsonrpc` body or a
/// `/web/dataset/call_kw` body and get the equivalent JSON-2 request.
class OdooConvertTab extends StatefulWidget {
  final OdooStudioViewModel viewModel;
  const OdooConvertTab({super.key, required this.viewModel});

  @override
  State<OdooConvertTab> createState() => _OdooConvertTabState();
}

class _OdooConvertTabState extends State<OdooConvertTab> {
  static const _example =
      "models.execute_kw(db, uid, password, 'res.partner', 'search_read',\n"
      "    [[['is_company', '=', True]]], {'fields': ['name', 'email'], 'limit': 5})";

  final _input = TextEditingController();
  int? _collectionId;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _curl(OdooRequestDraft d) {
    final b = StringBuffer("curl -X POST '${d.url}'");
    d.headers.forEach((k, v) => b.write(" \\\n  -H '$k: $v'"));
    b.write(" \\\n  -d '${d.bodyText.replaceAll("'", r"'\''")}'");
    return b.toString();
  }

  Future<void> _add(OdooRequestDraft draft) async {
    final id = _collectionId ?? context.read<CollectionsViewModel>().collections.firstOrNull?.id;
    if (id == null) return;
    final created = await widget.viewModel.addRequest(id, draft);
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${draft.name}" to your collection')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final collections = context.watch<CollectionsViewModel>().collections;
    final result = _input.text.trim().isEmpty ? null : OdooRpcConverter.convert(_input.text);
    final conversion = result?.conversion;
    final draft = conversion == null ? null : OdooJson2.draft(conversion.call);
    final input = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Old call', style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontWeight: FontWeight.w700))),
            TextButton(
              onPressed: () => setState(() => _input.text = _example),
              child: const Text('Insert example'),
            ),
          ],
        ),
        Expanded(
          child: TextField(
            controller: _input,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: context.textStyles.mono,
            decoration: const InputDecoration(
              hintText: "models.execute_kw(db, uid, password, 'res.partner', 'search_read', [[]], {'limit': 5})\n\n"
                  'or a JSON-RPC body:\n{"jsonrpc": "2.0", "method": "call", "params": {"service": "object", …}}',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
    final output = result == null
        ? const EmptyHint(icon: Icons.swap_horiz, title: 'Paste an old call', message: 'XML-RPC and JSON-RPC are deprecated in Odoo 19 and removed later. The JSON-2 version appears here.')
        : result.error != null
            ? Align(alignment: Alignment.topCenter, child: InfoBanner(kind: BannerKind.warning, message: result.error!))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final n in conversion!.notes) Padding(padding: const EdgeInsets.only(bottom: 6), child: InfoBanner(kind: BannerKind.warning, message: n)),
                  Text('POST ${draft!.url}', style: context.textStyles.mono.copyWith(color: colors.mainAccent, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Expanded(child: CodeBlock(text: draft.bodyText, label: 'JSON-2 body · from ${conversion.source}')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _curl(draft)));
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('cURL copied')));
                        },
                        icon: const Icon(Icons.terminal, size: 16),
                        label: const Text('Copy cURL'),
                      ),
                      if (collections.isNotEmpty) ...[
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(_collectionId),
                            initialValue: collections.any((c) => c.id == _collectionId) ? _collectionId : collections.first.id,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Collection'),
                            items: [for (final c in collections) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                            onChanged: (v) => setState(() => _collectionId = v),
                          ),
                        ),
                        FilledButton.icon(onPressed: () => _add(draft), icon: const Icon(Icons.add_task, size: 16), label: const Text('Add as request')),
                      ],
                    ],
                  ),
                ],
              );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 760
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: input), const SizedBox(width: 14), Expanded(child: output)])
            : Column(children: [Expanded(flex: 2, child: input), const SizedBox(height: 10), Expanded(flex: 3, child: output)]),
      ),
    );
  }
}
