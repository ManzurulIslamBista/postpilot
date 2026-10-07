import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../domain/services/noise_filter.dart';
import '../domain/services/recording_collection_builder.dart';
import '../domain/usecases/create_collection_from_recording_usecase.dart';
import 'traffic_recorder_view_model.dart';

/// "Create collection from recording": the noise filter and grouping choices, a preview of what would be made (so nothing
/// is a surprise), then the collection. The calls are the ticked ones, or every call the table shows.
class RecordingCollectionDialog extends StatefulWidget {
  final TrafficRecorderViewModel vm;

  const RecordingCollectionDialog({super.key, required this.vm});

  static Future<void> show(BuildContext context, TrafficRecorderViewModel vm) =>
      ToolDialog.show(context, (_) => RecordingCollectionDialog(vm: vm));

  @override
  State<RecordingCollectionDialog> createState() => _RecordingCollectionDialogState();
}

class _RecordingCollectionDialogState extends State<RecordingCollectionDialog> {
  late final _name = TextEditingController(text: widget.vm.suggestedCollectionName);
  late final _source = widget.vm.exportSource;
  late RecordingOptions _options = RecordingOptions(collectionName: _name.text);
  RecordedCollectionResult? _result;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _set(RecordingOptions Function(RecordingOptions o) change) => setState(() => _options = change(_options));

  Future<void> _create() async {
    final result = await widget.vm.createCollection(_options.copyWith(collectionName: _name.text.trim()), source: _source);
    if (!mounted || result == null) return;
    // The new collection opens in the sidebar when there is one (the dialog is also used where there is no sidebar).
    try {
      context.read<CollectionsViewModel>().expandCollection(result.collectionId);
    } catch (_) {}
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = widget.vm;
    final options = _options.copyWith(collectionName: _name.text.trim());
    final plan = vm.previewPlan(options, source: _source);
    final result = _result;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => ToolDialog(
        icon: Icons.create_new_folder_outlined,
        title: 'Create collection from recording',
        subtitle: '${_source.length} recorded call${_source.length == 1 ? '' : 's'}${vm.hasTicked ? ' (the ones you ticked)' : ''}',
        width: 680,
        height: 700,
        footerLeading: result != null || vm.error == null
            ? null
            : Text('Not created', style: context.textStyles.caption.copyWith(color: colors.statusError)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(result == null ? 'Cancel' : 'Close')),
          if (result == null)
            GradientButton(
              label: 'Create collection',
              icon: Icons.check,
              loading: vm.isBusy,
              onPressed: plan.isEmpty || _name.text.trim().isEmpty ? null : _create,
            ),
        ],
        child: result != null ? _done(context, result) : _form(context, plan),
      ),
    );
  }

  Widget _done(BuildContext context, RecordedCollectionResult result) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InfoBanner(
          kind: BannerKind.success,
          title: 'Created "${result.collectionName}"',
          message: '${_plural(result.requests, 'request')}, ${_plural(result.folders, 'folder')}, ${_plural(result.examples, 'saved example')}. '
              'It is in the sidebar now.',
          margin: const EdgeInsets.only(bottom: 12),
        ),
        for (final note in result.notes) Padding(padding: const EdgeInsets.only(bottom: 8), child: InfoBanner(message: note)),
      ],
    );
  }

  Widget _form(BuildContext context, RecordingPlan plan) {
    final colors = context.colors;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    final vm = widget.vm;
    Widget toggle(String title, String hint, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(hint, style: caption),
          value: value,
          onChanged: onChanged,
        );
    final counts = plan.counts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ToolSection(
          title: 'Name',
          child: TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: 'Recorded from api.example.com'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        ToolSection(
          title: 'Preview',
          child: plan.isEmpty
              ? InfoBanner(
                  kind: BannerKind.warning,
                  message: counts.selected == 0
                      ? 'There are no recorded calls to build from.'
                      : 'Nothing is left after leaving out ${counts.skippedTotal} call${counts.skippedTotal == 1 ? '' : 's'}${_skippedText(plan)}. '
                          'Switch a filter off, or record more calls.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoBanner(
                      kind: BannerKind.success,
                      title: '${_plural(counts.requests, 'request')} in ${_plural(counts.folders, 'folder')}, ${_plural(counts.examples, 'saved example')}',
                      message: [
                        if (counts.merged > 0) '${_plural(counts.merged, 'repeated call')} merged into earlier requests.',
                        if (counts.skippedTotal > 0) 'Left out: ${_skippedText(plan, withoutParens: true)}.',
                        'Credentials are never saved: ${plan.secretVariables.isEmpty ? 'none were found in these calls' : 'they become the empty secret variables ${plan.secretVariables.join(', ')}'}.',
                        'The server address becomes the baseUrl variable (${vm.baseUrl ?? ''}).',
                      ].join(' '),
                    ),
                    for (final note in plan.notes) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(kind: BannerKind.warning, message: note)),
                  ],
                ),
        ),
        ToolSection(
          title: 'Leave out',
          child: Column(
            children: [
              toggle('Static files', 'Scripts, styles, images, fonts.', _options.skipAssets, (v) => _set((o) => o.copyWith(skipAssets: v))),
              toggle('Analytics and crash reporting', 'Calls to hosts such as Google Analytics, Sentry, Mixpanel.', _options.skipAnalytics,
                  (v) => _set((o) => o.copyWith(skipAnalytics: v))),
              toggle('CORS preflights', 'The OPTIONS calls a browser sends before the real call.', _options.skipPreflights,
                  (v) => _set((o) => o.copyWith(skipPreflights: v))),
            ],
          ),
        ),
        ToolSection(
          title: 'Shape',
          child: Column(
            children: [
              toggle(
                'Merge repeated calls',
                'One request per method and path; ids and UUIDs in the path become {{variables}}. The first call is the request, later answers become saved examples.',
                _options.mergeDuplicates,
                (v) => _set((o) => o.copyWith(mergeDuplicates: v)),
              ),
              toggle('Group into folders', 'One folder per first path segment (users, orders, ...).', _options.groupIntoFolders,
                  (v) => _set((o) => o.copyWith(groupIntoFolders: v))),
              toggle('Add a status check to every request', 'A "Status equals" test with the status the call got.', _options.addStatusAssertions,
                  (v) => _set((o) => o.copyWith(addStatusAssertions: v))),
            ],
          ),
        ),
        if (vm.error != null) InfoBanner(kind: BannerKind.error, message: vm.error!),
      ],
    );
  }

  static String _skippedText(RecordingPlan plan, {bool withoutParens = false}) {
    final parts = [
      for (final reason in NoiseReason.values)
        if (plan.counts.skipped[reason] case final n? when n > 0) '$n ${reason.label}',
    ];
    if (parts.isEmpty) return '';
    return withoutParens ? parts.join(', ') : ' (${parts.join(', ')})';
  }

  static String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
}
