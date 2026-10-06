import 'package:flutter/material.dart';
import '../../../../core/widgets/tool_dialog.dart';
import 'api_layer_pane.dart';
import 'api_tests_pane.dart';
import 'dart_model_pane.dart';

/// Everything a Flutter developer wants from an API, generated: Dart classes
/// from a JSON response, and a whole API layer from a collection.
class DartStudioDialog extends StatelessWidget {
  final String initialJson;
  final String initialName;
  final int? collectionId;
  final int initialTab;

  const DartStudioDialog({super.key, this.initialJson = '', this.initialName = 'Root', this.collectionId, this.initialTab = 0});

  static Future<void> show(
    BuildContext context, {
    String initialJson = '',
    String initialName = 'Root',
    int? collectionId,
    int initialTab = 0,
  }) =>
      ToolDialog.show(
        context,
        (_) => DartStudioDialog(initialJson: initialJson, initialName: initialName, collectionId: collectionId, initialTab: initialTab),
      );

  @override
  Widget build(BuildContext context) {
    return ToolDialog(
      icon: Icons.flutter_dash,
      title: 'Dart Studio',
      subtitle: 'Models, API layers and their tests for Flutter, generated from real responses',
      width: 980,
      height: 680,
      child: ToolTabs(
        initialIndex: initialTab,
        tabs: [
          ToolTab(
            label: 'JSON to models',
            icon: Icons.data_object,
            child: DartModelPane(initialJson: initialJson, initialName: initialName),
          ),
          ToolTab(
            label: 'Collection to API layer',
            icon: Icons.account_tree_outlined,
            child: ApiLayerPane(initialCollectionId: collectionId),
          ),
          ToolTab(
            label: 'Tests',
            icon: Icons.science_outlined,
            child: ApiTestsPane(initialCollectionId: collectionId),
          ),
        ],
      ),
    );
  }
}
