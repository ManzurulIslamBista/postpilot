import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../shell/presentation/shell_view_model.dart';
import '../reopen_replaced_requests.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_sync_panel.dart';

class GitSyncDialog extends StatefulWidget {
  final int collectionId;
  final String collectionName;
  final RequestsReplacedCallback? onRequestsReplaced;

  const GitSyncDialog({
    super.key,
    required this.collectionId,
    required this.collectionName,
    this.onRequestsReplaced,
  });

  /// Without [onRequestsReplaced] the dialog keeps the open request tabs in line with what a pull, discard or
  /// branch switch rewrote, through the app-wide `ShellViewModel`.
  static Future<void> show(
    BuildContext context, {
    required int collectionId,
    required String collectionName,
    RequestsReplacedCallback? onRequestsReplaced,
  }) =>
      showDialog(
        context: context,
        builder: (_) => GitSyncDialog(
          collectionId: collectionId,
          collectionName: collectionName,
          onRequestsReplaced: onRequestsReplaced,
        ),
      );

  @override
  State<GitSyncDialog> createState() => _GitSyncDialogState();
}

class _GitSyncDialogState extends State<GitSyncDialog> {
  late final GitSyncViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<GitSyncViewModel>()
      ..onRequestsReplaced = _requestsReplacedHandler()
      ..load(widget.collectionId, collectionName: widget.collectionName);
  }

  RequestsReplacedCallback _requestsReplacedHandler() {
    final custom = widget.onRequestsReplaced;
    if (custom != null) return custom;
    final shell = context.read<ShellViewModel>();
    return (changed, deleted) => reopenReplacedRequests(shell, changed, deleted);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GitSyncViewModel>.value(
      value: _viewModel,
      // The barrier, Escape and the back button cannot dismiss the dialog while a commit, pull or switch is running.
      child: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, child) => PopScope(canPop: _viewModel.canClose, child: child!),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: SizedBox(
            width: 760,
            height: 600,
            child: GitSyncPanel(collectionId: widget.collectionId, collectionName: widget.collectionName),
          ),
        ),
      ),
    );
  }
}
