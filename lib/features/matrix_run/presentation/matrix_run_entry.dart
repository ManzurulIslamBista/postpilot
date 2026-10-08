import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../shell/presentation/shell_view_model.dart';
import 'matrix_run_dialog.dart';
import 'matrix_run_view_model.dart';

/// Opens the matrix run on [collectionId] (the collection menu), or on the collection of the open request (the command
/// palette): the first collection when no request is open. The dialog lets the person pick another one.
Future<void> showMatrixRun(BuildContext context, {int? collectionId}) async {
  final id = collectionId ?? await _currentCollectionId(context);
  if (!context.mounted) return;
  final viewModel = locator<MatrixRunViewModel>();
  await ToolDialog.show<void>(context, (_) => MatrixRunDialog(viewModel: viewModel, collectionId: id));
}

Future<int?> _currentCollectionId(BuildContext context) async {
  final shell = context.read<ShellViewModel>();
  final collections = context.read<CollectionsViewModel>();
  final location = await shell.selectedRequestLocation();
  return [
    for (final c in collections.collections)
      if (location == null || c.id == location.collectionId) c,
  ].firstOrNull?.id;
}
