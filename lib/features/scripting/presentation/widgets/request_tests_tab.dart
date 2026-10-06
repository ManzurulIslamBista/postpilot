import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../defaults/presentation/widgets/request_inherited_sections.dart';
import '../view_models/request_scripts_view_model.dart';
import 'assertions_editor.dart';
import 'extractors_editor.dart';

/// The "Tests" tab of the request builder: assertions + extractors for one
/// request, auto-saved on every change. Designed to sit inside the page's
/// scroll view, so it lays out as a plain Column.
class RequestTestsTab extends StatefulWidget {
  final int requestId;
  const RequestTestsTab({super.key, required this.requestId});

  @override
  State<RequestTestsTab> createState() => _RequestTestsTabState();
}

class _RequestTestsTabState extends State<RequestTestsTab> {
  late final RequestScriptsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<RequestScriptsViewModel>();
    _viewModel.load(widget.requestId);
  }

  @override
  void didUpdateWidget(covariant RequestTestsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) {
      _viewModel.load(widget.requestId);
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RequestScriptsViewModel>.value(
      value: _viewModel,
      child: Consumer<RequestScriptsViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const Center(child: CircularProgressIndicator());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The tests of the folders and the collection, which run first (read-only; nothing outside a request).
              const RequestInheritedTests(),
              Text('Assertions', style: context.textStyles.heading),
              Text(
                'Checked after every send; results appear under the response. Values, paths and header names can use {{name}}.',
                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
              ),
              const SizedBox(height: 8),
              AssertionsEditor(items: vm.assertions, onChanged: vm.updateAssertions),
              const SizedBox(height: 24),
              Text('Extract variables', style: context.textStyles.heading),
              Text(
                'Copy a value from the response into a variable so the next request can use {{name}}.',
                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
              ),
              const SizedBox(height: 8),
              ExtractorsEditor(items: vm.extractors, onChanged: vm.updateExtractors),
            ],
          );
        },
      ),
    );
  }
}
