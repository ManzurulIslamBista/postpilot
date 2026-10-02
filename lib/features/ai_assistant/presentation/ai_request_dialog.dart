import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/enums/body_type.dart';
import '../../../core/enums/http_method.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/code_block.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/method_badge.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../request_builder/domain/entities/key_value_item.dart';
import '../../request_builder/domain/entities/request_body.dart';
import '../../request_builder/domain/repositories/request_repository.dart';
import '../../shell/presentation/shell_view_model.dart';
import '../data/ai_client.dart';
import '../domain/ai_tasks.dart';
import 'ai_key_setup.dart';

/// Describe a call in words ("create a customer called Ann in Odoo") and get a
/// request you can review and add to a collection.
class AiRequestDialog extends StatefulWidget {
  const AiRequestDialog({super.key});

  static Future<void> show(BuildContext context) => ToolDialog.show(context, (_) => const AiRequestDialog());

  @override
  State<AiRequestDialog> createState() => _AiRequestDialogState();
}

class _AiRequestDialogState extends State<AiRequestDialog> {
  final _client = locator<AiClient>();
  final _description = TextEditingController();
  bool? _hasKey;
  bool _busy = false;
  String? _error;
  AiRequestSpec? _spec;
  int? _collectionId;
  bool _settings = false;

  @override
  void initState() {
    super.initState();
    _collectionId = context.read<CollectionsViewModel>().collections.firstOrNull?.id;
    _refreshKey();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _refreshKey() async {
    final has = await _client.hasKey;
    if (mounted) setState(() => _hasKey = has);
  }

  Future<void> _generate() async {
    if (_description.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _spec = null;
    });
    try {
      final reply = await _client.complete(system: AiTasks.requestSystem, user: _description.text.trim(), maxTokens: 1200);
      final spec = AiTasks.parseRequest(reply);
      if (spec == null) {
        _error = "The answer could not be read as a request. Try describing it differently.";
      } else {
        _spec = spec;
      }
    } on AiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _add() async {
    final spec = _spec;
    final collectionId = _collectionId;
    if (spec == null || collectionId == null) return;
    final repo = locator<RequestRepository>();
    final shell = context.read<ShellViewModel>();
    final collectionsVm = context.read<CollectionsViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final id = await repo.createRequest(collectionId: collectionId, name: spec.name);
    final created = await repo.findById(id);
    if (created != null) {
      final body = spec.body;
      final looksJson = body != null && (body.trimLeft().startsWith('{') || body.trimLeft().startsWith('['));
      await repo.saveRequest(created.copyWith(
        method: HttpMethod.fromString(spec.method),
        url: spec.url,
        headers: [for (final e in spec.headers.entries) KeyValueItem(key: e.key, value: e.value)],
        body: body == null ? created.body : RequestBody(type: BodyType.raw, rawContentType: looksJson ? RawContentType.json : RawContentType.text, rawText: body),
      ));
    }
    collectionsVm.expandCollection(collectionId);
    shell.selectRequest(id);
    messenger.showSnackBar(SnackBar(content: Text('Added "${spec.name}"')));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final collections = context.watch<CollectionsViewModel>().collections;
    final spec = _spec;
    return ToolDialog(
      icon: Icons.auto_awesome,
      title: 'Create a request with AI',
      subtitle: 'Describe the call in words',
      width: 780,
      height: 640,
      headerActions: [
        if (_hasKey == true) IconButton(icon: const Icon(Icons.tune, size: 18), tooltip: 'AI settings', onPressed: () => setState(() => _settings = !_settings)),
      ],
      child: _hasKey == null
          ? const Center(child: CircularProgressIndicator())
          : (_hasKey == false || _settings)
              ? ListView(padding: const EdgeInsets.all(16), children: [AiKeySetup(hasKey: _hasKey == true, onChanged: () async {
                  await _refreshKey();
                  if (mounted) setState(() => _settings = false);
                })])
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _description,
                        minLines: 3,
                        maxLines: 5,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Create a customer named Ann Lee with email ann@example.com in Odoo\nor: POST a new post to jsonplaceholder with a title',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          FilledButton(onPressed: _busy ? null : _generate, child: BusyLabel(busy: _busy, icon: Icons.auto_awesome, label: 'Generate request', busyLabel: 'Thinking…')),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Only your description is sent.', style: context.textStyles.caption.copyWith(color: colors.secondaryText))),
                        ],
                      ),
                      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: InfoBanner(kind: BannerKind.error, message: _error!)),
                      if (spec != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            MethodBadge(method: spec.method, width: 52),
                            const SizedBox(width: 10),
                            Expanded(child: SelectableText(spec.url, style: context.textStyles.mono.copyWith(color: colors.mainAccent))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(spec.name, style: context.textStyles.heading),
                        const SizedBox(height: 8),
                        Expanded(
                          child: CodeBlock(
                            text: [
                              for (final e in spec.headers.entries) '${e.key}: ${e.value}',
                              if (spec.body != null) ...['', spec.body!],
                            ].join('\n'),
                            label: 'Headers and body',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (collections.isNotEmpty)
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<int>(
                                  key: ValueKey(_collectionId),
                                  initialValue: collections.any((c) => c.id == _collectionId) ? _collectionId : collections.first.id,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Add to collection'),
                                  items: [for (final c in collections) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                                  onChanged: (v) => setState(() => _collectionId = v),
                                ),
                              ),
                            const Spacer(),
                            FilledButton.icon(onPressed: collections.isEmpty ? null : _add, icon: const Icon(Icons.add_task, size: 16), label: const Text('Add to collection')),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Review before sending: AI can be wrong.', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                      ] else
                        const Expanded(child: EmptyHint(icon: Icons.auto_awesome, title: 'Describe a request', message: 'The model proposes the method, URL, headers and body. You review it, then add it.')),
                    ],
                  ),
                ),
    );
  }
}
