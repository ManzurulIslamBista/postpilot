import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../../../ai_assistant/presentation/ai_tab.dart';
import '../../../dart_codegen/domain/services/dart_names.dart';
import '../../../dart_codegen/presentation/widgets/dart_model_pane.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../../domain/services/response_history.dart';
import '../view_models/response_tools_view_model.dart';
import 'compare_tab.dart';
import 'decode_tab.dart';
import 'explore_tab.dart';
import 'schema_tab.dart';
import 'share_tab.dart';
import 'table_tab.dart';
import 'timing_tab.dart';

/// Everything a developer wants to do with a response beyond reading it:
/// explore it as a tree and pull values out, see it as a table, decode tokens
/// and timestamps, compare it with an earlier one, check it against a schema,
/// turn it into Dart classes, or write it up for an issue.
class ResponseToolsDialog extends StatefulWidget {
  final ResponseToolsData data;
  const ResponseToolsDialog({super.key, required this.data});

  static Future<void> show(
    BuildContext context, {
    required int requestId,
    required String requestName,
    required ApiResponseEntity response,
  }) =>
      ToolDialog.show(
        context,
        (_) => ResponseToolsDialog(
          data: ResponseToolsData.from(requestId: requestId, requestName: requestName, response: response),
        ),
      );

  @override
  State<ResponseToolsDialog> createState() => _ResponseToolsDialogState();
}

class _ResponseToolsDialogState extends State<ResponseToolsDialog> {
  late final ResponseToolsViewModel _vm = ResponseToolsViewModel(
    locator<RequestRepository>(),
    locator<RequestScriptsRepository>(),
    locator<ResponseExampleRepository>(),
    locator<ResponseHistory>(),
    widget.data,
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  String _size(int bytes) => bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final r = data.response;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => ToolDialog(
        icon: Icons.auto_fix_high,
        title: 'Response tools',
        subtitle: '${data.requestName} · ${r.statusCode} ${r.statusMessage} · ${r.duration.inMilliseconds} ms · ${_size(r.sizeBytes)}',
        width: 1000,
        height: 700,
        child: ToolTabs(
          tabs: [
            ToolTab(label: 'Explore', icon: Icons.account_tree_outlined, child: ExploreTab(viewModel: _vm)),
            ToolTab(label: 'Table', icon: Icons.table_chart_outlined, child: TableTab(viewModel: _vm)),
            ToolTab(label: 'Decode', icon: Icons.lock_open_outlined, child: DecodeTab(viewModel: _vm)),
            ToolTab(label: 'Compare', icon: Icons.compare_arrows, child: CompareTab(viewModel: _vm)),
            ToolTab(label: 'Timing', icon: Icons.speed, child: TimingTab(viewModel: _vm)),
            ToolTab(label: 'Schema', icon: Icons.rule, child: SchemaTab(viewModel: _vm)),
            ToolTab(
              label: 'Dart model',
              icon: Icons.flutter_dash,
              child: data.isJson
                  ? DartModelPane(initialJson: data.bodyText, initialName: DartNames.pascal(data.requestName, fallback: 'Root'))
                  : const EmptyHint(icon: Icons.flutter_dash, title: 'This response is not JSON', message: 'Dart classes are generated from JSON bodies.'),
            ),
            ToolTab(label: 'Ask AI', icon: Icons.auto_awesome, child: AiTab(viewModel: _vm)),
            ToolTab(label: 'Share', icon: Icons.ios_share, child: ShareTab(viewModel: _vm)),
          ],
        ),
      ),
    );
  }
}
