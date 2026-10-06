import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import 'postman_export_body.dart';
import 'view_models/import_export_view_model.dart';

/// Shows a collection serialized as Postman v2.1 JSON, ready to copy.
class ExportPostmanDialog extends StatefulWidget {
  final int collectionId;
  const ExportPostmanDialog({super.key, required this.collectionId});

  static Future<void> show(BuildContext context, {required int collectionId}) =>
      showDialog(context: context, builder: (_) => ExportPostmanDialog(collectionId: collectionId));

  @override
  State<ExportPostmanDialog> createState() => _ExportPostmanDialogState();
}

class _ExportPostmanDialogState extends State<ExportPostmanDialog> {
  late final ImportExportViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<ImportExportViewModel>();
    _viewModel.exportPostman(widget.collectionId);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ImportExportViewModel>.value(
      value: _viewModel,
      child: Consumer<ImportExportViewModel>(
        builder: (context, vm, _) => Dialog(
          child: SizedBox(
            width: 640,
            height: 560,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Export as Postman collection', style: context.textStyles.body.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: vm.exportError != null
                        ? Text(vm.exportError!, style: TextStyle(color: Theme.of(context).colorScheme.error))
                        : vm.exportedJson == null
                            ? const Center(child: CircularProgressIndicator())
                            : PostmanExportBody(json: vm.exportedJson!),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
