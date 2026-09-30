import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import 'view_models/import_export_view_model.dart';

/// Paste-an-OpenAPI/Swagger-document dialog. Returns the new collection's
/// id, or null if the user cancelled or the import failed.
class ImportOpenApiDialog extends StatefulWidget {
  const ImportOpenApiDialog({super.key});

  static Future<int?> show(BuildContext context) => showDialog<int>(context: context, builder: (_) => const ImportOpenApiDialog());

  @override
  State<ImportOpenApiDialog> createState() => _ImportOpenApiDialogState();
}

class _ImportOpenApiDialogState extends State<ImportOpenApiDialog> {
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
    final id = await _viewModel.importOpenApi(_controller.text);
    if (id == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API imported')));
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ImportExportViewModel>.value(
      value: _viewModel,
      child: Consumer<ImportExportViewModel>(
        // Esc and a barrier tap dismiss the dialog (and dispose the ViewModel)
        // even though Cancel is disabled, so block them while importing.
        builder: (context, vm, _) => PopScope(
          canPop: !vm.isImportingOpenApi,
          child: AlertDialog(
            title: const Text('Import OpenAPI/Swagger'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Paste an OpenAPI 3.x or Swagger 2.0 document (JSON or YAML) below.'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    maxLines: 10,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'openapi: 3.0.0\ninfo:\n  title: My API\npaths:\n  /users:\n    get: ...',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (vm.importOpenApiError != null) ...[
                    const SizedBox(height: 8),
                    Text(vm.importOpenApiError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: vm.isImportingOpenApi ? null : () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: vm.isImportingOpenApi || _controller.text.trim().isEmpty ? null : _import,
                child: vm.isImportingOpenApi
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Import'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
