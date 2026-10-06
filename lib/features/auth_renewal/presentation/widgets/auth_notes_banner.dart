import 'package:flutter/material.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/services/relogin_policy.dart';

/// Above a response: what the app did to the authentication around this send (a token renewed, a re-login
/// run and the request sent again), so nothing happens silently. Renders nothing when [notes] is empty.
class AuthNotesBanner extends StatelessWidget {
  final List<String> notes;

  const AuthNotesBanner({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InfoBanner(
        kind: notes.any(ReloginPolicy.isProblem) ? BannerKind.warning : BannerKind.info,
        message: notes.join('\n'),
      ),
    );
  }
}
