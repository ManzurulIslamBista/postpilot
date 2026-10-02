import '../../../core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
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

  void _copy(String json) {
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exported to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ImportExportViewModel>.value(
      value: _viewModel,
      child: Consumer<ImportExportViewModel>(
        builder: (context, vm, _) => Dialog(
          child: SizedBox(
            width: 600,
            height: 480,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Export as Postman collection', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (vm.exportedJson != null)
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Copy',
                          onPressed: () => _copy(vm.exportedJson!),
                        ),
                      IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: vm.exportError != null
                        ? Text(vm.exportError!, style: TextStyle(color: Theme.of(context).colorScheme.error))
                        : vm.exportedJson == null
                            ? const Center(child: CircularProgressIndicator())
                            : SingleChildScrollView(
                                child: SelectableText(vm.exportedJson!, style: const TextStyle(fontFamily: AppFonts.monoFamily, fontFamilyFallback: AppFonts.monoFallback, fontSize: 12)),
                              ),
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
