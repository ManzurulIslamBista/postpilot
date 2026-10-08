import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../request_builder/domain/entities/api_request_entity.dart';
import '../../request_builder/domain/entities/api_response_entity.dart';
import '../../response_tools/domain/services/response_history.dart';
import '../domain/services/auth_doctor.dart';
import '../domain/usecases/build_auth_doctor_input_usecase.dart';
import 'auth_doctor_dialog.dart';
import 'auth_doctor_view_model.dart';

/// Whether [response] is a refusal the 401/403 doctor explains: 401, 403, 407, and the token errors that a few other statuses carry.
bool isRejectionToExplain(ApiResponseEntity response) {
  final status = response.statusCode;
  if (AuthDoctor.appliesTo(status)) return true;
  // Only a 400 needs its body read, and only the start of it.
  if (status != 400 || response.bodyBytes.isEmpty) return false;
  return AuthDoctor.appliesTo(status, utf8.decode(response.bodyBytes.take(64 * 1024).toList(), allowMalformed: true));
}

/// One small row above a response that was a refusal: "Why was I rejected? - 3 findings". It opens the doctor. Shows nothing for
/// any other response, so a working request never sees it.
class AuthDoctorBanner extends StatefulWidget {
  final ApiResponseEntity response;
  final ApiRequestEntity request;

  /// Works out the findings for the count; the app's own when null (no count without one).
  final AuthDoctorInputBuilder? builder;

  const AuthDoctorBanner({super.key, required this.response, required this.request, this.builder});

  @override
  State<AuthDoctorBanner> createState() => _AuthDoctorBannerState();
}

class _AuthDoctorBannerState extends State<AuthDoctorBanner> {
  ApiResponseEntity? _countedFor;
  int? _count;

  AuthDoctorInputBuilder? get _builder => widget.builder ?? appAuthDoctorInputBuilder();

  DateTime? get _receivedAt => locator.isRegistered<ResponseHistory>() ? locator<ResponseHistory>().receivedAt(widget.response) : null;

  @override
  void initState() {
    super.initState();
    _updateCount();
  }

  @override
  void didUpdateWidget(covariant AuthDoctorBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.response, widget.response)) _updateCount();
  }

  /// Counts the findings of the response on show, once per response. The count is a nicety: without it the row still opens the doctor.
  Future<void> _updateCount() async {
    final response = widget.response;
    _countedFor = response;
    _count = null;
    final builder = _builder;
    if (builder == null || !isRejectionToExplain(response)) return;
    int? count;
    try {
      final input = await builder(AuthDoctorSubject(request: widget.request, response: response, receivedAt: _receivedAt));
      count = AuthDoctor.diagnose(input).length;
    } catch (_) {
      count = null;
    }
    if (mounted && identical(_countedFor, response) && count != _count) setState(() => _count = count);
  }

  @override
  Widget build(BuildContext context) {
    if (!isRejectionToExplain(widget.response)) return const SizedBox.shrink();
    final colors = context.colors;
    final count = _count;
    final label = count == null ? 'Why was I rejected?' : 'Why was I rejected? - $count ${count == 1 ? 'finding' : 'findings'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: colors.statusWarning.withValues(alpha: 0.09),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.statusWarning.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AuthDoctorDialog.show(
            context,
            subject: AuthDoctorSubject(request: widget.request, response: widget.response, receivedAt: _receivedAt),
            builder: widget.builder,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.privacy_tip_outlined, size: 16, color: colors.statusWarning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.caption.copyWith(fontWeight: FontWeight.w700, color: colors.statusWarning),
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: colors.statusWarning),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
