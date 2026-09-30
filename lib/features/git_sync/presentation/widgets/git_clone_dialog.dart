import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../view_models/git_clone_view_model.dart';
import 'git_clone_panel.dart';

class GitCloneDialog extends StatefulWidget {
  const GitCloneDialog({super.key});

  /// The id of the newly created local collection, or null when the user cancelled.
  static Future<int?> show(BuildContext context) =>
      showDialog<int>(context: context, builder: (_) => const GitCloneDialog());

  @override
  State<GitCloneDialog> createState() => _GitCloneDialogState();
}

class _GitCloneDialogState extends State<GitCloneDialog> {
  late final GitCloneViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<GitCloneViewModel>()..load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GitCloneViewModel>.value(
      value: _viewModel,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: 600,
          height: 620,
          child: GitClonePanel(onCloned: (collectionId) => Navigator.pop(context, collectionId)),
        ),
      ),
    );
  }
}
