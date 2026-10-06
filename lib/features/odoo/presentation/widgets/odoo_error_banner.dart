import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../data/odoo_doctor.dart';
import '../../domain/entities/odoo_request_shape.dart';
import '../../domain/services/odoo_error_parser.dart';

/// Appears above a response when it is an Odoo error, turning the raw
/// exception into a title, what it means, what to check, and the traceback
/// frames that matter. For the errors the error doctor knows (access denied, a missing required field, a duplicate
/// value, a record that does not exist...) it also offers to look into it on the live server, read-only, and says
/// what to do. Shows nothing for any other response.
class OdooErrorBanner extends StatefulWidget {
  final ApiResponseEntity response;

  /// The request that got the response; its URL or body names the model for the errors that do not.
  final ApiRequestEntity? request;

  /// The doctor to ask; the app's own when the dependencies are registered, none otherwise (a test).
  final OdooDoctor? doctor;
  const OdooErrorBanner({super.key, required this.response, this.request, this.doctor});

  @override
  State<OdooErrorBanner> createState() => _OdooErrorBannerState();
}

class _OdooErrorBannerState extends State<OdooErrorBanner> {
  OdooErrorInfo? _info;
  ApiResponseEntity? _parsedFor;
  bool _open = false;
  bool _asking = false;
  OdooDoctorAnswer? _answer;

  OdooErrorInfo? _parse() {
    if (identical(_parsedFor, widget.response)) return _info;
    _parsedFor = widget.response;
    _open = false;
    _answer = null;
    final r = widget.response;
    if (r.bodyBytes.isEmpty || r.bodyBytes.length > 512 * 1024 || r.bodyBytes.first != 0x7B) return _info = null;
    return _info = OdooErrorParser.parse(utf8.decode(r.bodyBytes, allowMalformed: true), statusCode: r.statusCode);
  }

  OdooDoctor? get _doctor {
    if (widget.doctor != null) return widget.doctor;
    return locator.isRegistered<OdooDoctor>() ? locator<OdooDoctor>() : null;
  }

  /// The model of the call that failed, from its URL or, for a `call_kw` to a bare path, from its body.
  String? get _model {
    final request = widget.request;
    if (request == null) return null;
    final fromUrl = OdooRequestShape.ofUrl(request.url)?.model;
    if (fromUrl != null && fromUrl.isNotEmpty) return fromUrl;
    return OdooRequestShape.read(request.url, request.body.rawText).shape?.model;
  }

  Future<void> _ask(OdooErrorInfo info) async {
    final doctor = _doctor;
    if (doctor == null) return;
    setState(() => _asking = true);
    OdooDoctorAnswer? answer;
    try {
      answer = await doctor.diagnose(info, model: _model);
    } catch (_) {
      answer = null;
    }
    if (mounted) {
      setState(() {
        _asking = false;
        _answer = answer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _parse();
    if (info == null) return const SizedBox.shrink();
    final colors = context.colors;
    final hasMore = info.frames.isNotEmpty || info.failingLine != null;
    final canAsk = info.diagnosis != null && _doctor != null;
    final answer = _answer;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.statusError.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.statusError.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bug_report_outlined, size: 18, color: colors.statusError),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Odoo: ${info.title}',
                      style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700, color: colors.statusError),
                    ),
                    if (info.message.isNotEmpty) SelectableText(info.message, style: context.textStyles.body),
                    if (info.hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(info.hint!, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                      ),
                  ],
                ),
              ),
              if (hasMore)
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? 'Hide details' : 'Details'),
                ),
            ],
          ),
          if (canAsk)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: _asking ? null : () => _ask(info),
                  child: BusyLabel(busy: _asking, icon: Icons.medical_services_outlined, iconSize: 16, label: 'Look it up on the server', busyLabel: 'Looking…'),
                ),
              ),
            ),
          if (answer != null) _AnswerView(answer: answer),
          if (_open) ...[
            const SizedBox(height: 6),
            if (info.exception.isNotEmpty) SelectableText(info.exception, style: context.textStyles.mono.copyWith(fontSize: 12, color: colors.syntaxKey)),
            for (final f in info.frames) SelectableText(f, style: context.textStyles.mono.copyWith(fontSize: 11.5, color: colors.secondaryText)),
            if (info.failingLine != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(info.failingLine!, style: context.textStyles.mono.copyWith(fontSize: 12, color: colors.statusError)),
              ),
          ],
        ],
      ),
    );
  }
}

/// What the live lookup found: the facts, the steps they make possible, and why it could not go further.
class _AnswerView extends StatelessWidget {
  final OdooDoctorAnswer answer;
  const _AnswerView({required this.answer});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final report = answer.report;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Looked up on ${SecretMasker.maskUrl(answer.server)} (the active environment):', style: caption),
          for (final fact in report.facts) Padding(padding: const EdgeInsets.only(top: 2), child: SelectableText('• $fact', style: context.textStyles.body)),
          for (final step in report.steps)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText('Next: $step', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
            ),
          if (report.notice != null) Padding(padding: const EdgeInsets.only(top: 2), child: SelectableText(report.notice!, style: caption)),
          if (report.isEmpty) Text('The server had nothing more to add.', style: caption),
        ],
      ),
    );
  }
}
