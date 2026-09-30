import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../documentation/presentation/widgets/request_docs_tab.dart';
import '../../scripting/presentation/widgets/request_tests_tab.dart';
import '../../scripting/presentation/widgets/script_results_view.dart';
import '../../settings/presentation/widgets/request_settings_tab.dart';
import '../../shell/presentation/shell_view_model.dart';
import 'view_models/request_builder_view_model.dart';
import 'widgets/auth_editor.dart';
import 'widgets/body_editor.dart';
import 'widgets/code_snippet_dialog.dart';
import 'widgets/key_value_editor.dart';
import 'widgets/method_dropdown.dart';
import 'widgets/response_viewer.dart';

class RequestBuilderPage extends StatefulWidget {
  final int requestId;
  const RequestBuilderPage({required this.requestId}) : super(key: const ValueKey('request-builder'));

  @override
  State<RequestBuilderPage> createState() => _RequestBuilderPageState();
}

class _RequestBuilderPageState extends State<RequestBuilderPage> {
  late final RequestBuilderViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<RequestBuilderViewModel>();
    _viewModel.load(widget.requestId);
    locator<ShellViewModel>().registerSender(widget.requestId, _viewModel.send);
  }

  @override
  void didUpdateWidget(covariant RequestBuilderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) {
      _viewModel.load(widget.requestId);
      locator<ShellViewModel>()
        ..unregisterSender(oldWidget.requestId, _viewModel.send)
        ..registerSender(widget.requestId, _viewModel.send);
    }
  }

  @override
  void dispose() {
    locator<ShellViewModel>().unregisterSender(widget.requestId, _viewModel.send);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RequestBuilderViewModel>.value(
      value: _viewModel,
      child: Consumer<RequestBuilderViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading || vm.request == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _RequestBuilderBody(vm: vm);
        },
      ),
    );
  }
}

class _RequestBuilderBody extends StatelessWidget {
  final RequestBuilderViewModel vm;
  const _RequestBuilderBody({required this.vm});

  @override
  Widget build(BuildContext context) {
    final request = vm.request!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              MethodDropdown(value: request.method, onChanged: vm.updateMethod),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: request.url,
                  decoration: const InputDecoration(hintText: 'https://api.example.com/{{path}}', isDense: true),
                  onChanged: vm.updateUrl,
                  onFieldSubmitted: (_) => vm.send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.code, size: 18),
                tooltip: 'Generate code',
                onPressed: () => CodeSnippetDialog.show(context, vm),
              ),
              const SizedBox(width: 4),
              if (vm.isSending)
                OutlinedButton.icon(
                  onPressed: vm.cancelSend,
                  icon: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  label: const Text('Cancel'),
                )
              else
                FilledButton(onPressed: vm.send, child: const Text('Send')),
            ],
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 7,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Params'),
                    Tab(text: 'Headers'),
                    Tab(text: 'Body'),
                    Tab(text: 'Auth'),
                    Tab(text: 'Tests'),
                    Tab(text: 'Settings'),
                    Tab(text: 'Docs'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _scrollable(KeyValueEditor(items: request.queryParams, onChanged: vm.updateQueryParams)),
                      _scrollable(KeyValueEditor(items: request.headers, onChanged: vm.updateHeaders)),
                      _padded(BodyEditor(body: request.body, onChanged: vm.updateBody)),
                      _scrollable(AuthEditor(auth: request.auth, collectionId: request.collectionId, onChanged: vm.updateAuth)),
                      _scrollable(RequestTestsTab(requestId: request.id)),
                      _scrollable(RequestSettingsTab(requestId: request.id)),
                      _scrollable(RequestDocsTab(requestId: request.id)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (vm.errorMessage != null)
          Container(
            width: double.infinity,
            color: context.colors.statusError.withValues(alpha: 0.1),
            child: vm.errorDetail == null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(vm.errorMessage!, style: TextStyle(color: context.colors.statusError)),
                  )
                : ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(vm.errorMessage!, style: TextStyle(color: context.colors.statusError)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(vm.errorDetail!, style: TextStyle(color: context.colors.statusError)),
                        ),
                      ),
                    ],
                  ),
          ),
        if (vm.lastScriptResult != null) ScriptResultsView(result: vm.lastScriptResult!),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.border))),
            child: ResponseViewer(response: vm.response, requestId: request.id, requestName: request.name),
          ),
        ),
      ],
    );
  }

  Widget _padded(Widget child) => Padding(padding: const EdgeInsets.all(12), child: child);

  Widget _scrollable(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.all(12), child: child);
}
