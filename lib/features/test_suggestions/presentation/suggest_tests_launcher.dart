import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../request_builder/domain/repositories/request_repository.dart';
import '../../response_tools/domain/services/response_history.dart';
import '../../response_tools/presentation/widgets/response_tools_dialog.dart';
import 'widgets/suggest_tests_tab.dart';

/// Whether the last response of [requestId] is still in memory, so tests can be suggested from it.
bool hasResponseToSuggestFrom(int requestId) =>
    locator.isRegistered<ResponseHistory>() && locator<ResponseHistory>().of(requestId).isNotEmpty;

/// Opens the response tools on the Suggest tests tab for the last response of [requestId]: the button of the Tests
/// tab, the Drift chip and the command palette all come here. Without a response it says what to do first.
Future<void> openSuggestTests(BuildContext context, {required int requestId, TestsSection section = TestsSection.suggestions}) async {
  final response = locator.isRegistered<ResponseHistory>() ? locator<ResponseHistory>().of(requestId).firstOrNull : null;
  if (response == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Send the request first: tests are suggested from a real response.')),
    );
    return;
  }
  final request = locator.isRegistered<RequestRepository>() ? await locator<RequestRepository>().findById(requestId) : null;
  if (!context.mounted) return;
  await ResponseToolsDialog.show(
    context,
    requestId: requestId,
    requestName: request?.name ?? 'Request',
    response: response,
    initialTab: SuggestTestsTab.label,
    testsSection: section,
  );
}
