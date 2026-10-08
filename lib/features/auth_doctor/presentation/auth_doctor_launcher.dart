import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../command_palette/domain/entities/palette_item.dart';
import '../../request_builder/domain/repositories/request_repository.dart';
import '../../response_tools/domain/services/response_history.dart';
import '../../shell/presentation/shell_view_model.dart';
import '../domain/usecases/build_auth_doctor_input_usecase.dart';
import 'auth_doctor_banner.dart';
import 'auth_doctor_dialog.dart';

/// Whether the last response of [requestId] is a refusal that is still in memory, so the doctor can explain it.
bool hasRejectionToExplain(int requestId) {
  if (!locator.isRegistered<ResponseHistory>()) return false;
  final response = locator<ResponseHistory>().of(requestId).firstOrNull;
  return response != null && isRejectionToExplain(response);
}

/// Opens the doctor for the last response of [requestId]: the palette entry and the banner come here. Without a response, or
/// with one that was no refusal, it says what to do instead of opening an empty dialog.
Future<void> openAuthDoctor(BuildContext context, {required int requestId}) async {
  final messenger = ScaffoldMessenger.of(context);
  final history = locator.isRegistered<ResponseHistory>() ? locator<ResponseHistory>() : null;
  final response = history?.of(requestId).firstOrNull;
  if (response == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Send the request first: the doctor explains a real response.')));
    return;
  }
  if (!isRejectionToExplain(response)) {
    final status = '${response.statusCode} ${response.statusMessage}'.trim();
    messenger.showSnackBar(SnackBar(content: Text('The last response was $status: it was not a rejection.')));
    return;
  }
  final request = locator.isRegistered<RequestRepository>() ? await locator<RequestRepository>().findById(requestId) : null;
  if (request == null) {
    messenger.showSnackBar(const SnackBar(content: Text('The request is no longer saved, so the doctor has nothing to read.')));
    return;
  }
  if (!context.mounted) return;
  await AuthDoctorDialog.show(
    context,
    subject: AuthDoctorSubject(request: request, response: response, receivedAt: history?.receivedAt(response)),
  );
}

/// The command palette's entry for the doctor. It is listed only while the open request has a rejected response in memory.
List<PaletteItem> authDoctorPaletteItems() {
  final open = locator.isRegistered<ShellViewModel>() ? locator<ShellViewModel>().selectedRequestId : null;
  if (open == null || !hasRejectionToExplain(open)) return const [];
  return [
    PaletteItem(
      id: 'auth.doctor',
      title: '401/403 Doctor: explain the last rejection',
      subtitle: 'Why the server said no: the credential, the token, the environment, a firewall. Offline, nothing is sent',
      icon: Icons.privacy_tip_outlined,
      keywords: const ['401', '403', '407', 'unauthorized', 'forbidden', 'rejected', 'token', 'expired', 'auth', 'why', 'denied', 'doctor', 'jwt'],
      run: (c) => openAuthDoctor(c, requestId: open),
    ),
  ];
}
