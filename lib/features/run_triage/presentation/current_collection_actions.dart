import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../shell/presentation/shell_view_model.dart';
import 'monitor_dialog.dart';
import 'run_history_dialog.dart';

/// The collection of the open request (the first collection when no tab is open), for the command palette; a message
/// when there is none.
Future<({int id, String name})?> _currentCollection(BuildContext context) async {
  final shell = context.read<ShellViewModel>();
  final collections = context.read<CollectionsViewModel>();
  final location = await shell.selectedRequestLocation();
  final entity = [
    for (final c in collections.collections)
      if (location == null || c.id == location.collectionId) c,
  ].firstOrNull;
  if (!context.mounted) return null;
  if (entity == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('There is no collection yet: create one first.')));
    return null;
  }
  return (id: entity.id, name: entity.name);
}

/// The run history of the current collection.
Future<void> showCurrentCollectionRunHistory(BuildContext context) async {
  final collection = await _currentCollection(context);
  if (collection == null || !context.mounted) return;
  await RunHistoryDialog.show(context, collectionId: collection.id, collectionName: collection.name);
}

/// The monitor of the current collection.
Future<void> showCurrentCollectionMonitor(BuildContext context) async {
  final collection = await _currentCollection(context);
  if (collection == null || !context.mounted) return;
  await MonitorDialog.show(context, collectionId: collection.id, collectionName: collection.name);
}
