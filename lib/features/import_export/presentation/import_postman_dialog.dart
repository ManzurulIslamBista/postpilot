import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import 'view_models/import_export_view_model.dart';

/// Paste-a-Postman-v2.1-export dialog. Returns the new collection's id, or
/// null if the user cancelled or the import failed.
class ImportPostmanDialog extends StatefulWidget {
  const ImportPostmanDialog({super.key});

  static Future<int?> show(BuildContext context) => showDialog<int>(context: context, builder: (_) => const ImportPostmanDialog());

  @override
  State<ImportPostmanDialog> createState() => _ImportPostmanDialogState();
}

class _ImportPostmanDialogState extends State<ImportPostmanDialog> {
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
    final id = await _viewModel.importPostman(_controller.text);
    if (id == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Collection imported')));
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ImportExportViewModel>.value(
      value: _viewModel,
      child: Consumer<ImportExportViewModel>(
        builder: (context, vm, _) => AlertDialog(
          title: const Text('Import Postman collection'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Paste the exported Collection v2.1 JSON below.'),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  maxLines: 10,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '{ "info": { "name": "..." }, "item": [...] }'),
                  onChanged: (_) => setState(() {}),
                ),
                if (vm.importPostmanError != null) ...[
                  const SizedBox(height: 8),
                  Text(vm.importPostmanError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: vm.isImportingPostman ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: vm.isImportingPostman || _controller.text.trim().isEmpty ? null : _import,
              child: vm.isImportingPostman
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }
}
