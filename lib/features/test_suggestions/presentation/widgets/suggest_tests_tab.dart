import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/usecases/send_request_usecase.dart';
import '../../../response_tools/presentation/view_models/response_tools_view_model.dart';
import '../../../safety/domain/services/production_guard.dart';
import '../../../safety/presentation/production_confirm_dialog.dart';
import '../../../scripting/presentation/view_models/request_scripts_view_model.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../../domain/repositories/request_baseline_repository.dart';
import '../../domain/usecases/export_baselines_usecase.dart';
import '../view_models/baseline_view_model.dart';
import '../view_models/suggestions_view_model.dart';
import 'baseline_view.dart';
import 'suggestions_view.dart';

/// The two halves of the Suggest tests tab.
enum TestsSection { suggestions, baseline }

/// The "Suggest tests" tab of the response tools: proposals for tests written from the response, and the baseline
/// the response is compared with. One panel, two views, because both start from the same response and the baseline
/// uses what the stability probe of the suggestions learned.
class SuggestTestsPanel extends StatefulWidget {
  final SuggestionsViewModel suggestions;

  /// Null where the baselines cannot be kept (the app has no database for them).
  final BaselineViewModel? baseline;
  final TestsSection initialSection;

  const SuggestTestsPanel({super.key, required this.suggestions, this.baseline, this.initialSection = TestsSection.suggestions});

  @override
  State<SuggestTestsPanel> createState() => _SuggestTestsPanelState();
}

class _SuggestTestsPanelState extends State<SuggestTestsPanel> {
  late TestsSection _section = widget.initialSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SegmentedButton<TestsSection>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TestsSection.suggestions, icon: Icon(Icons.checklist, size: 16), label: Text('Suggestions')),
              ButtonSegment(value: TestsSection.baseline, icon: Icon(Icons.fact_check_outlined, size: 16), label: Text('Baseline & drift')),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() => _section = s.first),
          ),
        ),
        Expanded(
          child: _section == TestsSection.suggestions
              ? SuggestionsView(viewModel: widget.suggestions)
              : widget.baseline == null
                  ? const EmptyHint(
                      icon: Icons.fact_check_outlined,
                      title: 'Baselines are not available here',
                      message: 'A baseline is kept in the database of this device.',
                    )
                  : ListenableBuilder(
                      listenable: widget.suggestions,
                      builder: (context, _) => BaselineView(viewModel: widget.baseline!, probed: widget.suggestions.probed),
                    ),
        ),
      ],
    );
  }
}

/// [SuggestTestsPanel] for the response in the response tools, wired to the app's repositories.
class SuggestTestsTab extends StatefulWidget {
  /// The tab's label in the response tools dialog.
  static const label = 'Suggest tests';

  final ResponseToolsViewModel viewModel;
  final TestsSection initialSection;

  const SuggestTestsTab({super.key, required this.viewModel, this.initialSection = TestsSection.suggestions});

  @override
  State<SuggestTestsTab> createState() => _SuggestTestsTabState();
}

class _SuggestTestsTabState extends State<SuggestTestsTab> {
  SuggestionsViewModel? _suggestions;
  BaselineViewModel? _baseline;

  @override
  void initState() {
    super.initState();
    // A harness that has not set up the repositories gets a tab that says so instead of an error.
    if (!locator.isRegistered<RequestScriptsRepository>()) return;
    final data = widget.viewModel.data;
    final suggestions = _suggestions = SuggestionsViewModel(
      requestId: data.requestId,
      response: data.response,
      scripts: locator<RequestScriptsRepository>(),
      request: () => widget.viewModel.request,
      send: locator.isRegistered<SendRequestUseCase>() ? (request) => locator<SendRequestUseCase>()(request) : null,
      confirmSend: _confirmSend,
      afterWrite: RequestScriptsViewModel.reloadOnScreen,
    )..load();
    if (locator.isRegistered<RequestBaselineRepository>() && locator.isRegistered<RequestSettingsRepository>()) {
      _baseline = BaselineViewModel(
        requestId: data.requestId,
        response: data.response,
        baselines: locator<RequestBaselineRepository>(),
        settings: locator<RequestSettingsRepository>(),
        export: locator.isRegistered<ExportBaselinesUseCase>() ? locator<ExportBaselinesUseCase>().call : null,
        stability: () => suggestions.stability,
        saveFile: _saveFile,
      )..load();
    }
  }

  /// The production lock, as for any send: a request that changes data is asked about while a production
  /// environment is active.
  Future<bool> _confirmSend(ApiRequestEntity request) async {
    if (!locator.isRegistered<ProductionGuard>()) return true;
    final guard = locator<ProductionGuard>();
    final warning = await guard.checkRequest(request);
    if (warning == null || !mounted) return true;
    return confirmProductionSend(context, warning, onSilence: () => guard.silenceForSession(warning.environmentName));
  }

  Future<String?> _saveFile(String fileName, Uint8List bytes) =>
      downloadFile(fileName: fileName, bytes: bytes, mimeType: 'application/json');

  @override
  void dispose() {
    _suggestions?.dispose();
    _baseline?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    if (suggestions == null) {
      return const EmptyHint(icon: Icons.checklist, title: 'Test suggestions are not available here', message: 'They need the request\'s saved tests.');
    }
    // The saved request loads after the tab opens; the proposals' "Send again" waits for it.
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) => SuggestTestsPanel(suggestions: suggestions, baseline: _baseline, initialSection: widget.initialSection),
    );
  }
}
