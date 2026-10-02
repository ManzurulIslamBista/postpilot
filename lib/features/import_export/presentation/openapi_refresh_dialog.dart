import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injector.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_http_response.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/method_badge.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../domain/services/openapi_refresh_planner.dart';
import '../domain/usecases/refresh_openapi_usecase.dart';

/// Update a collection from a newer version of its OpenAPI spec: see what is
/// new and what left the spec, then apply. Existing requests are never changed.
class OpenApiRefreshDialog extends StatefulWidget {
  final int? collectionId;
  const OpenApiRefreshDialog({super.key, this.collectionId});

  static Future<void> show(BuildContext context, {int? collectionId}) =>
      ToolDialog.show(context, (_) => OpenApiRefreshDialog(collectionId: collectionId));

  @override
  State<OpenApiRefreshDialog> createState() => _OpenApiRefreshDialogState();
}

class _OpenApiRefreshDialogState extends State<OpenApiRefreshDialog> {
  final _url = TextEditingController();
  final _spec = TextEditingController();
  int? _collectionId;
  OpenApiRefreshPlan? _plan;
  bool _busy = false;
  String? _error;
  bool _markRemoved = true;
  String? _done;

  @override
  void initState() {
    super.initState();
    final collections = context.read<CollectionsViewModel>().collections;
    _collectionId = widget.collectionId ?? collections.firstOrNull?.id;
    _restoreSource();
  }

  @override
  void dispose() {
    _url.dispose();
    _spec.dispose();
    super.dispose();
  }

  String? get _collectionName {
    for (final c in context.read<CollectionsViewModel>().collections) {
      if (c.id == _collectionId) return c.name;
    }
    return null;
  }

  String get _prefKey => 'openapi.source.${_collectionName ?? ''}';

  Future<void> _restoreSource() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && mounted && _url.text.isEmpty) setState(() => _url.text = saved);
    } catch (_) {}
  }

  Future<void> _fetch() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await locator<ApiClient>().send(ApiRequestSpec(
        method: 'GET',
        url: url,
        headers: const {'Accept': 'application/json, application/yaml, */*'},
        options: const ApiRequestOptions(maxResponseBytes: 32 * 1024 * 1024),
      ));
      if (!response.isSuccess) {
        _error = 'The server answered ${response.statusCode} ${response.statusMessage}.';
      } else {
        _spec.text = utf8.decode(response.bodyBytes, allowMalformed: true);
        try {
          (await SharedPreferences.getInstance()).setString(_prefKey, url);
        } catch (_) {}
      }
    } catch (e) {
      _error = "Couldn't download the spec: $e";
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _compare() async {
    final id = _collectionId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _plan = null;
      _done = null;
    });
    try {
      _plan = await locator<RefreshOpenApiUseCase>().plan(id, _spec.text);
    } catch (e) {
      _error = '$e'.replaceFirst('ImportException: ', '');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _apply() async {
    final id = _collectionId;
    final plan = _plan;
    if (id == null || plan == null) return;
    setState(() => _busy = true);
    try {
      final added = await locator<RefreshOpenApiUseCase>().apply(id, plan, markRemoved: _markRemoved);
      _done = 'Added $added request${added == 1 ? '' : 's'}${_markRemoved && plan.removed.isNotEmpty ? ' and marked ${plan.removed.length} removed' : ''}.';
      _plan = null;
    } catch (e) {
      _error = "Couldn't update the collection: $e";
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final collections = context.watch<CollectionsViewModel>().collections;
    final plan = _plan;
    return ToolDialog(
      icon: Icons.sync_alt,
      title: 'Update from OpenAPI',
      subtitle: 'Add new endpoints without touching your edits',
      width: 860,
      height: 680,
      actions: [
        if (plan != null && !plan.isEmpty)
          FilledButton.icon(
            onPressed: _busy ? null : _apply,
            icon: const Icon(Icons.check, size: 16),
            label: Text('Apply (${plan.added.length} new${_markRemoved && plan.removed.isNotEmpty ? ', ${plan.removed.length} marked' : ''})'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One line on a wide dialog; on a phone the collection picker gets its own line above the URL.
            LayoutBuilder(builder: (context, box) {
              final narrow = box.maxWidth < 560;
              final collectionPicker = DropdownButtonFormField<int>(
                key: ValueKey(_collectionId),
                initialValue: collections.any((c) => c.id == _collectionId) ? _collectionId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Collection'),
                items: [for (final c in collections) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                onChanged: (id) {
                  setState(() {
                    _collectionId = id;
                    _plan = null;
                    _url.clear();
                  });
                  _restoreSource();
                },
              );
              final urlField = TextField(
                controller: _url,
                decoration: const InputDecoration(labelText: 'Spec URL', hintText: 'https://api.example.com/openapi.json', prefixIcon: Icon(Icons.link, size: 18)),
                onSubmitted: (_) => _fetch(),
              );
              final download = OutlinedButton(onPressed: _busy ? null : _fetch, child: const Text('Download'));
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    collectionPicker,
                    const SizedBox(height: 8),
                    Row(children: [Expanded(child: urlField), const SizedBox(width: 8), download]),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 220, child: collectionPicker),
                  const SizedBox(width: 10),
                  Expanded(child: urlField),
                  const SizedBox(width: 8),
                  download,
                ],
              );
            }),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _spec,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: context.textStyles.mono,
                decoration: const InputDecoration(hintText: 'Or paste the OpenAPI / Swagger document here (JSON or YAML)'),
                onChanged: (_) => setState(() => _plan = null),
              ),
            ),
            const SizedBox(height: 8),
            // Wraps the chip under the button when a phone cannot fit both on one line.
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: _busy || _spec.text.trim().isEmpty || _collectionId == null ? null : _compare,
                  child: BusyLabel(busy: _busy, icon: Icons.difference_outlined, label: 'Compare', busyLabel: 'Working…'),
                ),
                FilterChip(label: const Text('Mark endpoints removed from the spec'), selected: _markRemoved, onSelected: (v) => setState(() => _markRemoved = v)),
              ],
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(kind: BannerKind.error, message: _error!)),
            if (_done != null) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(kind: BannerKind.success, title: 'Updated', message: _done!)),
            if (plan != null) ...[
              const SizedBox(height: 10),
              Expanded(
                flex: 3,
                child: plan.isEmpty
                    ? InfoBanner(kind: BannerKind.success, title: 'Up to date', message: 'All ${plan.unchanged} endpoints of the spec are already in the collection.')
                    : Container(
                        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
                        clipBehavior: Clip.antiAlias,
                        child: ListView(
                          children: [
                            _header(context, '${plan.added.length} new in the spec', colors.statusSuccess),
                            for (final e in plan.added)
                              ListTile(dense: true, leading: MethodBadge(method: e.item.method.label, width: 44), title: Text(e.item.name), subtitle: Text('${e.folder ?? 'root'} · ${OpenApiRefreshPlanner.normalizePath(e.item.url)}', style: context.textStyles.caption)),
                            _header(context, '${plan.removed.length} no longer in the spec', colors.statusWarning),
                            for (final e in plan.removed)
                              ListTile(dense: true, leading: MethodBadge(method: e.method.label, width: 44), title: Text(e.name), subtitle: Text(OpenApiRefreshPlanner.normalizePath(e.url), style: context.textStyles.caption)),
                            _header(context, '${plan.unchanged} unchanged (kept as they are)', colors.secondaryText),
                          ],
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text, Color color) => Container(
        color: color.withValues(alpha: 0.10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}
