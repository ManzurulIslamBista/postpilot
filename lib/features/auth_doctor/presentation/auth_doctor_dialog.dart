import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/code_block.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../domain/entities/auth_finding.dart';
import '../domain/usecases/build_auth_doctor_input_usecase.dart';
import 'auth_doctor_view_model.dart';

/// "Why was I rejected?": what probably made the server answer 401, 403 or 407, as findings with a confidence, a plain
/// explanation, what to do and what in the exchange says so. Worked out offline from the request and the response; nothing is
/// sent.
class AuthDoctorDialog extends StatefulWidget {
  final AuthDoctorSubject subject;

  /// Turns the subject into the doctor's input; the app's own when null.
  final AuthDoctorInputBuilder? builder;

  const AuthDoctorDialog({super.key, required this.subject, this.builder});

  static Future<void> show(BuildContext context, {required AuthDoctorSubject subject, AuthDoctorInputBuilder? builder}) =>
      ToolDialog.show(context, (_) => AuthDoctorDialog(subject: subject, builder: builder));

  @override
  State<AuthDoctorDialog> createState() => _AuthDoctorDialogState();
}

class _AuthDoctorDialogState extends State<AuthDoctorDialog> {
  late final AuthDoctorViewModel _vm = AuthDoctorViewModel(widget.subject, builder: widget.builder ?? appAuthDoctorInputBuilder())..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthDoctorViewModel>.value(
      value: _vm,
      child: Consumer<AuthDoctorViewModel>(
        builder: (context, vm, _) => ToolDialog(
          icon: Icons.privacy_tip_outlined,
          title: 'Why was I rejected?',
          subtitle: '${vm.statusLine} · ${vm.requestLine}',
          width: 780,
          height: 640,
          child: switch (vm.status) {
            AuthDoctorStatus.loading => const Center(child: CircularProgressIndicator()),
            AuthDoctorStatus.failed => EmptyHint(icon: Icons.error_outline, title: 'The doctor could not run', message: vm.error),
            AuthDoctorStatus.ready => _Findings(vm: vm),
          },
        ),
      ),
    );
  }
}

class _Findings extends StatelessWidget {
  final AuthDoctorViewModel vm;
  const _Findings({required this.vm});

  @override
  Widget build(BuildContext context) {
    final findings = vm.findings;
    if (findings.isEmpty) {
      return EmptyHint(
        icon: Icons.check_circle_outline,
        title: 'Nothing was rejected',
        message: 'The response is ${vm.statusLine}, which is not a refusal the doctor explains (401, 403 and 407).',
      );
    }
    final unknown = vm.input?.requestKnown == false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InfoBanner(
          kind: unknown ? BannerKind.warning : BannerKind.info,
          message: unknown
              ? 'The request could not be rebuilt as it was sent (it may have been edited since), so nothing is said about the credential it carried.'
              : 'Worked out here, offline, from the request as it is saved now and the response you got. Nothing was sent. '
                  'A token is shown as its first four characters and its length, never in full.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            StatusChip(label: vm.statusLine, icon: Icons.error_outline, color: context.colors.forStatus(vm.subject.response.statusCode)),
            StatusChip(label: '${findings.length} ${findings.length == 1 ? 'finding' : 'findings'}', icon: Icons.fact_check_outlined),
          ],
        ),
        const SizedBox(height: 12),
        for (final (index, finding) in findings.indexed) _FindingCard(key: ValueKey('${finding.id}#$index'), finding: finding),
        const SizedBox(height: 4),
        ToolSection(
          title: 'Copy as text',
          hint: 'The same diagnosis for a bug report or a message to whoever runs the server. It holds no secret.',
          child: SizedBox(height: 180, child: CodeBlock(text: vm.report, label: 'Diagnosis', wrap: true, copyMessage: 'Diagnosis copied')),
        ),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  final AuthFinding finding;
  const _FindingCard({super.key, required this.finding});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    final tint = switch (finding.confidence) {
      FindingConfidence.certain => colors.mainAccent,
      FindingConfidence.likely => colors.methodPut,
      FindingConfidence.possible => null,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(label: finding.confidence.label, color: tint),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120),
                child: SelectableText(finding.title, style: textStyles.body.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(finding.explanation, style: textStyles.body),
          const SizedBox(height: 8),
          SelectableText.rich(
            TextSpan(
              style: textStyles.body,
              children: [
                const TextSpan(text: 'What to do: ', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: finding.fix),
              ],
            ),
          ),
          if (finding.evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('EVIDENCE', style: textStyles.caption.copyWith(color: colors.secondaryText, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9)),
            const SizedBox(height: 4),
            for (final line in finding.evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: SelectableText('• $line', style: textStyles.caption.copyWith(color: colors.secondaryText)),
              ),
          ],
        ],
      ),
    );
  }
}
