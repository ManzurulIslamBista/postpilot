import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/entities/refactor_scope.dart';
import '../view_models/workspace_refactor_view_model.dart';
import 'preview_layout.dart';
import 'refactor_chrome.dart';

/// Find and replace across the whole workspace: what to look for, where, and a preview of every occurrence with a
/// checkbox, grouped collection > folder > request. Nothing is written until "Replace selected".
class FindReplacePane extends StatefulWidget {
  final WorkspaceRefactorViewModel viewModel;
  const FindReplacePane({super.key, required this.viewModel});

  @override
  State<FindReplacePane> createState() => _FindReplacePaneState();
}

class _FindReplacePaneState extends State<FindReplacePane> {
  WorkspaceRefactorViewModel get vm => widget.viewModel;
  late final TextEditingController _query = TextEditingController(text: vm.query);
  late final TextEditingController _replacement = TextEditingController(text: vm.replacement);
  bool _showScopes = false;

  @override
  void dispose() {
    _query.dispose();
    _replacement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (vm.snapshot == null) return WorkspaceLoading(viewModel: vm);
        return PreviewLayout(
          controls: _controls(context),
          rows: vm.findRows,
          isTicked: vm.isTicked,
          onTick: vm.setManyTicked,
          empty: _empty(context),
          footer: _footer(context),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    if (vm.findPlan.error != null) return const SizedBox.shrink();
    if (vm.query.isEmpty) {
      return const EmptyHint(
        icon: Icons.find_replace,
        title: 'Find and replace in every collection',
        message: 'Type what to look for. Every match is listed here with what it would become; nothing changes until you press Replace selected.',
      );
    }
    final skipped = vm.findPlan.secretSkipped;
    return EmptyHint(
      icon: Icons.search_off,
      title: 'No matches',
      message: skipped > 0
          ? 'Nothing matched. $skipped secret values were not searched: tick "Include secret values" to search them too.'
          : 'Nothing matched in the areas selected above.',
    );
  }

  Widget _controls(BuildContext context) {
    final find = TextField(
      controller: _query,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Find', prefixIcon: Icon(Icons.search, size: 18)),
      onChanged: vm.setQuery,
    );
    final replace = TextField(
      controller: _replacement,
      decoration: InputDecoration(
        labelText: 'Replace with',
        prefixIcon: const Icon(Icons.edit_outlined, size: 18),
        helperText: vm.regex ? r'$1 $2 are the groups, $& the whole match, $$ a dollar sign' : null,
      ),
      onChanged: vm.setReplacement,
    );
    final everywhere = vm.scopes.length == RefactorScope.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 560
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: find), const SizedBox(width: 12), Expanded(child: replace)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [find, const SizedBox(height: 10), replace]),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(label: const Text('Regex'), selected: vm.regex, onSelected: (v) => vm.setOptions(regex: v)),
            FilterChip(label: const Text('Match case'), selected: vm.caseSensitive, onSelected: (v) => vm.setOptions(caseSensitive: v)),
            FilterChip(label: const Text('Whole word'), selected: vm.wholeWord, onSelected: (v) => vm.setOptions(wholeWord: v)),
            FilterChip(
              avatar: const Icon(Icons.lock_outline, size: 14),
              label: const Text('Include secret values'),
              selected: vm.includeSecret,
              onSelected: (v) => vm.setOptions(includeSecret: v),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _showScopes = !_showScopes),
              icon: Icon(_showScopes ? Icons.expand_less : Icons.expand_more, size: 18),
              label: Text(everywhere ? 'Where: everywhere' : 'Where: ${vm.scopes.length} of ${RefactorScope.values.length} areas'),
            ),
          ],
        ),
        if (_showScopes) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final scope in RefactorScope.values)
                Tooltip(
                  message: scope.hint,
                  child: FilterChip(label: Text(scope.label), selected: vm.scopes.contains(scope), onSelected: (_) => vm.toggleScope(scope)),
                ),
              TextButton(onPressed: () => vm.setAllScopes(true), child: const Text('All')),
              TextButton(onPressed: () => vm.setAllScopes(false), child: const Text('None')),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _summary(context),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final plan = vm.findPlan;
    final caption = context.textStyles.caption.copyWith(color: context.colors.secondaryText);
    final error = plan.error;
    if (error != null) return InfoBanner(kind: BannerKind.error, message: error);
    if (vm.query.isEmpty) return Text('Secret values are masked here and left alone unless you tick "Include secret values".', style: caption);
    final places = plan.changes.length;
    return Text.rich(
      TextSpan(
        style: caption,
        children: [
          TextSpan(text: '${plan.editCount} ${plan.editCount == 1 ? 'match' : 'matches'} in $places ${places == 1 ? 'place' : 'places'}'),
          if (plan.secretSkipped > 0) TextSpan(text: '  ·  ${plan.secretSkipped} secret values not searched'),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final plan = vm.findPlan;
    final hasMatches = plan.editCount > 0;
    return RefactorFooter(
      leading: Text(
        hasMatches ? '${vm.tickedCount} of ${plan.editCount} ticked. Undo stays available until PostPilot closes.' : 'Nothing is written until you press Replace selected.',
        style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
      ),
      actions: [
        TextButton(onPressed: hasMatches ? () => vm.tickAll(true) : null, child: const Text('Select all')),
        TextButton(onPressed: hasMatches ? () => vm.tickAll(false) : null, child: const Text('Select none')),
        FilledButton(
          onPressed: vm.canReplace ? vm.applyFind : null,
          child: BusyLabel(busy: vm.isApplying, label: 'Replace selected (${vm.tickedCount})', busyLabel: 'Replacing…', icon: Icons.find_replace),
        ),
      ],
    );
  }
}
