import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../defaults/presentation/view_models/inherited_defaults_view_model.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../domain/entities/auth_owner.dart';
import '../../domain/services/token_status.dart';
import '../view_models/inherited_oauth2_status_view_model.dart';

/// On the Auth tab of a request that inherits OAuth 2.0 from a folder or the collection: the same token
/// status the auth has where it is set (is there a token, when it ends, whether it renews itself) and a
/// "Renew now". Renders nothing for any other auth, or outside an [InheritedDefaultsViewModel].
class InheritedOAuth2Status extends StatefulWidget {
  /// The request's own auth; only an "Inherit from parent" request shows the line.
  final RequestAuth requestAuth;

  const InheritedOAuth2Status({super.key, required this.requestAuth});

  @override
  State<InheritedOAuth2Status> createState() => _InheritedOAuth2StatusState();
}

class _InheritedOAuth2StatusState extends State<InheritedOAuth2Status> {
  // Made only when there is an inherited OAuth 2.0 auth to show: most requests never need it.
  InheritedOAuth2StatusViewModel? _created;
  InheritedOAuth2StatusViewModel get _vm => _created ??= locator<InheritedOAuth2StatusViewModel>();

  @override
  void dispose() {
    _created?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaults = context.watch<InheritedDefaultsViewModel?>();
    final inherited = defaults?.inherited.auth;
    final collectionId = defaults?.collectionId;
    if (widget.requestAuth.type != AuthType.inherit ||
        defaults == null ||
        !defaults.isLoaded ||
        collectionId == null ||
        inherited == null ||
        inherited.type != AuthType.oauth2) {
      return const SizedBox.shrink();
    }
    final origin = defaults.inherited.authOrigin;
    final owner = AuthOwner.of(
      ownsAuth: false,
      requestId: 0,
      requestName: '',
      collectionId: collectionId,
      collectionName: origin?.name ?? '',
      origin: origin,
    );
    final status = TokenStatus.of(inherited, DateTime.now());
    final colors = context.colors;
    final color = switch (status.health) {
      TokenHealth.missing => colors.secondaryText,
      TokenHealth.expired => colors.statusError,
      TokenHealth.expiring => colors.statusWarning,
      TokenHealth.valid || TokenHealth.noExpiry => colors.statusSuccess,
    };

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(status.isUsable ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${status.headline}${origin == null ? '' : ' (${origin.label})'}',
                    key: const ValueKey('inherited-oauth2-status'),
                    style: context.textStyles.caption.copyWith(color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                if (status.selfRenewing)
                  TextButton(
                    key: const ValueKey('inherited-oauth2-renew'),
                    onPressed: _vm.isRenewing
                        ? null
                        : () => _vm.renew(inherited, owner, collectionId: collectionId, folderId: defaults.folderId),
                    child: BusyLabel(busy: _vm.isRenewing, label: 'Renew now', busyLabel: 'Renewing…'),
                  ),
              ],
            ),
            Text(status.renewalLine, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
            if (_vm.errorMessage case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(error, style: context.textStyles.caption.copyWith(color: colors.statusError)),
              ),
          ],
        ),
      ),
    );
  }
}
