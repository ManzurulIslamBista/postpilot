import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../view_models/workspace_refactor_view_model.dart';

/// The bar under a pane: a line on the left and the pane's buttons on the right, wrapping on a narrow screen. Looks like
/// the footer of a `ToolDialog`, which has one for the whole dialog; each tab here has its own buttons.
class RefactorFooter extends StatelessWidget {
  final Widget leading;
  final List<Widget> actions;
  const RefactorFooter({super.key, required this.leading, required this.actions});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.sidebarBackground.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, c) {
          final wrapActions = Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: actions);
          // The line and the buttons share a row when there is room; on a phone the buttons go under the line.
          if (c.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [leading, const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: wrapActions)],
            );
          }
          return Row(children: [Expanded(flex: 2, child: leading), const SizedBox(width: 12), Flexible(flex: 5, child: wrapActions)]);
        },
      ),
    );
  }
}

/// What a pane shows while the workspace is being read, and if it could not be read.
class WorkspaceLoading extends StatelessWidget {
  final WorkspaceRefactorViewModel viewModel;
  const WorkspaceLoading({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final error = viewModel.loadError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: InfoBanner(
            kind: BannerKind.error,
            message: error,
            trailing: TextButton(onPressed: viewModel.load, child: const Text('Try again')),
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 12),
          Text('Reading the workspace…', style: context.textStyles.body.copyWith(color: context.colors.secondaryText)),
        ],
      ),
    );
  }
}

/// A short field label above a group of controls, in the style of the other tools.
class RefactorHint extends StatelessWidget {
  final String text;
  const RefactorHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(text, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText));
}
