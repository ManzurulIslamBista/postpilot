import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../../core/widgets/tool_dialog.dart';
import 'view_models/workspace_refactor_view_model.dart';
import 'workspace_refactor_dialog.dart';

/// Opens the workspace refactoring dialog (find and replace, rename a variable, unused and undefined variables) with a
/// view model of its own. The undo of the last change is shared by every opening of the session.
Future<void> showWorkspaceRefactorDialog(BuildContext context, {RefactorTab initialTab = RefactorTab.findReplace}) =>
    ToolDialog.show<void>(
      context,
      (_) => WorkspaceRefactorDialog(createViewModel: () => locator<WorkspaceRefactorViewModel>(), initialTab: initialTab),
    );
