import 'package:flutter/material.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../dart_codegen/presentation/widgets/generated_files_view.dart';
import '../../domain/services/odoo_dart_generator.dart';
import '../view_models/odoo_studio_view_model.dart';

/// A Dart class for the explored model that reads Odoo's real JSON, with the
/// support file it needs (`false` for empty values, `[id, name]` for relations).
class OdooDartTab extends StatefulWidget {
  final OdooStudioViewModel viewModel;
  const OdooDartTab({super.key, required this.viewModel});

  @override
  State<OdooDartTab> createState() => _OdooDartTabState();
}

class _OdooDartTabState extends State<OdooDartTab> {
  bool _selectedOnly = true;
  bool _computed = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final info = vm.info;
        if (info == null) {
          return const EmptyHint(
            icon: Icons.flutter_dash,
            title: 'Read a model first',
            message: 'Open the Explorer tab, read the fields of a model (or paste a fields_get response), tick the fields you want and come back here.',
          );
        }
        final files = const OdooDartGenerator().generate(
          info,
          options: OdooDartOptions(
            fieldNames: _selectedOnly && vm.chosenFields.isNotEmpty ? vm.chosenFields : null,
            includeComputed: _computed,
          ),
        );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text('Only the ${vm.chosenFields.length} selected fields'),
                    selected: _selectedOnly,
                    onSelected: (v) => setState(() => _selectedOnly = v),
                  ),
                  FilterChip(label: const Text('Include computed fields'), selected: _computed, onSelected: (v) => setState(() => _computed = v)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(child: GeneratedFilesView(files: files)),
            ],
          ),
        );
      },
    );
  }
}
