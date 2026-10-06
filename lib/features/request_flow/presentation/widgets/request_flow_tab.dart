import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../domain/services/retry_planner.dart';
import '../view_models/request_flow_view_model.dart';
import 'flow_section.dart';
import 'pagination_editor.dart';
import 'poll_editor.dart';
import 'retry_editor.dart';
import 'run_if_editor.dart';

/// The "Flow" tab of the request builder: what the request does around being sent, without a script. Retry when
/// it fails, poll until a condition holds, fetch every page of a list, and (in a run) send it only if something
/// holds or even after a failure. Everything is off until switched on, and saved on every change. Designed to sit
/// inside the page's scroll view, so it lays out as a plain Column.
class RequestFlowTab extends StatefulWidget {
  final int requestId;
  final HttpMethod method;

  /// The request and the response it last got, for "Detect from the last response".
  final ApiRequestEntity? request;
  final ApiResponseEntity? response;

  const RequestFlowTab({super.key, required this.requestId, required this.method, this.request, this.response});

  @override
  State<RequestFlowTab> createState() => _RequestFlowTabState();
}

class _RequestFlowTabState extends State<RequestFlowTab> {
  late final RequestFlowViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<RequestFlowViewModel>();
    _viewModel.load(widget.requestId);
  }

  @override
  void didUpdateWidget(covariant RequestFlowTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) _viewModel.load(widget.requestId);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RequestFlowViewModel>.value(
      value: _viewModel,
      child: Consumer<RequestFlowViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const Center(child: CircularProgressIndicator());
          final flow = vm.flow;
          final pagination = vm.pagination;
          final repeats = flow.retry.enabled || flow.poll.enabled || pagination.enabled;
          final needsTick = RepeatSafety.needsConfirmation(widget.method);
          final muted = context.textStyles.caption.copyWith(color: context.colors.secondaryText);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Flow', style: context.textStyles.heading),
              Text(
                'Retry, poll, skip and fetch pages without writing a script. Everything here is off until you switch it on.',
                style: muted,
              ),
              const SizedBox(height: 10),
              FlowSection(
                key: const ValueKey('flow-retry'),
                title: 'Retry',
                summary: flow.retry.enabled ? flow.retry.summary : 'Try again when the network or the server fails',
                enabled: flow.retry.enabled,
                onToggle: (on) => vm.setRetry(flow.retry.copyWith(enabled: on)),
                child: RetryEditor(policy: flow.retry, onChanged: vm.setRetry),
              ),
              FlowSection(
                key: const ValueKey('flow-poll'),
                title: 'Poll until',
                summary: flow.poll.enabled ? flow.poll.summary : 'Send again until the response meets a condition',
                enabled: flow.poll.enabled,
                onToggle: (on) => vm.setPoll(flow.poll.copyWith(enabled: on)),
                child: PollEditor(policy: flow.poll, onChanged: vm.setPoll),
              ),
              FlowSection(
                key: const ValueKey('flow-pages'),
                title: 'Fetch all pages',
                summary: pagination.enabled ? pagination.summary : 'Follow a paged list to its end and merge it into one response',
                enabled: pagination.enabled,
                onToggle: (on) => vm.setPagination(pagination.copyWith(enabled: on)),
                child: PaginationEditor(
                  settings: pagination,
                  onChanged: vm.setPagination,
                  onUseDetection: vm.useDetection,
                  request: widget.request,
                  response: widget.response,
                ),
              ),
              if (needsTick && repeats) ...[
                const SizedBox(height: 2),
                FlowCheckbox(
                  key: const ValueKey('flow-repeat-unsafe'),
                  title: 'I know repeating this request is safe',
                  description:
                      '${widget.method.label} can create, change or delete something each time it is sent. Until this is ticked '
                      'the request is sent once and retry, poll and more pages are left out.',
                  value: flow.repeatUnsafe,
                  onChanged: vm.setRepeatUnsafe,
                ),
                if (!flow.repeatUnsafe)
                  InfoBanner(
                    key: const ValueKey('flow-repeat-warning'),
                    kind: BannerKind.warning,
                    message: 'Not repeated yet: ${widget.method.label} is only repeated once you tick the box above.',
                  ),
              ],
              const SizedBox(height: 14),
              Text('In a collection run or from the command line', style: context.textStyles.heading),
              Text('These only matter when requests are run one after the other. Sending by hand always sends.', style: muted),
              const SizedBox(height: 8),
              FlowSection(
                key: const ValueKey('flow-run-if'),
                title: 'Run if',
                summary: flow.runIf.enabled
                    ? flow.runIf.summary
                    : 'Send only when a variable, the environment or the previous result matches',
                enabled: flow.runIf.enabled,
                onToggle: (on) => vm.setRunIf(flow.runIf.copyWith(enabled: on)),
                child: RunIfEditor(policy: flow.runIf, onChanged: vm.setRunIf),
              ),
              FlowCheckbox(
                key: const ValueKey('flow-always-run'),
                title: 'Always run, even after a failure',
                description:
                    'For cleanup: when "stop on failure" ends a run, this request is still sent (its Run if still applies). '
                    'Stopping a run yourself stops it too.',
                value: flow.alwaysRun,
                onChanged: vm.setAlwaysRun,
              ),
              if (vm.saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(vm.saveError!, style: muted.copyWith(color: context.colors.statusError)),
                ),
            ],
          );
        },
      ),
    );
  }
}
