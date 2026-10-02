import '../../../core/widgets/busy_label.dart';
import '../../../core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../domain/usecases/import_curl_usecase.dart';
import 'view_models/import_export_view_model.dart';

/// Paste-a-cURL-command dialog. Returns the new request's id, or null if the
/// user cancelled or the import failed.
class ImportCurlDialog extends StatefulWidget {
  final int collectionId;
  final int? folderId;
  const ImportCurlDialog({super.key, required this.collectionId, required this.folderId});

  static Future<int?> show(BuildContext context, {required int collectionId, int? folderId}) => showDialog<int>(
    context: context,
    builder: (_) => ImportCurlDialog(collectionId: collectionId, folderId: folderId),
  );

  @override
  State<ImportCurlDialog> createState() => _ImportCurlDialogState();
}

class _ImportCurlDialogState extends State<ImportCurlDialog> {
  final _controller = TextEditingController();
  late final ImportExportViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<ImportExportViewModel>();
  }

  @override
  void dispose() {
    _controller.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final id = await _viewModel.importCurl(
      ImportCurlParams(collectionId: widget.collectionId, folderId: widget.folderId, curlCommand: _controller.text),
    );
    if (id == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request imported')));
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ImportExportViewModel>.value(
      value: _viewModel,
      child: Consumer<ImportExportViewModel>(
        builder: (context, vm, _) => AlertDialog(
          title: const Text('Import cURL command'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  maxLines: 8,
                  style: const TextStyle(
                    fontFamily: AppFonts.monoFamily,
                    fontFamilyFallback: AppFonts.monoFallback,
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "curl -X GET https://api.example.com",
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (vm.importCurlError != null) ...[
                  const SizedBox(height: 8),
                  Text(vm.importCurlError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: vm.isImportingCurl ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: vm.isImportingCurl || _controller.text.trim().isEmpty ? null : _import,
              child: BusyLabel(busy: vm.isImportingCurl, label: 'Import', busyLabel: 'Importing…'),
            ),
          ],
        ),
      ),
    );
  }
}
