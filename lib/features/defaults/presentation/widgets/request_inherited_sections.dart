import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../domain/entities/defaults_origin.dart';
import '../defaults_dialog.dart';
import '../view_models/inherited_defaults_view_model.dart';
import 'inherited_headers_list.dart';
import 'origin_chip.dart';

/// Opens the defaults dialog at the level that set a value: the folder, or the collection.
Future<void> _editOrigin(BuildContext context, InheritedDefaultsViewModel vm, DefaultsOrigin origin) {
  final collectionId = vm.collectionId;
  if (collectionId == null) return Future.value();
  return showDefaultsDialog(context, collectionId: collectionId, folderId: origin.isFolder ? origin.id : null);
}

/// Above a request's own headers: the ones it inherits from its folders and collection, read-only,
/// with where each comes from and the actions to override one for this request or turn it off.
/// Renders nothing when the request inherits no header, or outside an [InheritedDefaultsViewModel].
class RequestInheritedHeaders extends StatelessWidget {
  final List<KeyValueItem> requestHeaders;
  final ValueChanged<List<KeyValueItem>> onChanged;

  const RequestInheritedHeaders({super.key, required this.requestHeaders, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InheritedDefaultsViewModel?>();
    if (vm == null || vm.inherited.headers.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'INHERITED HEADERS',
                style: context.textStyles.caption.copyWith(
                  color: colors.secondaryText,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'Sent with this request. A header you add below with the same name replaces one.',
                  style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InheritedHeadersList(
            headers: vm.inherited.headers,
            own: requestHeaders,
            onOverride: (h) => onChanged([...requestHeaders, KeyValueItem(key: h.item.key, value: h.item.value)]),
            onSwitchOff: (h) => onChanged([...requestHeaders, KeyValueItem(key: h.item.key, value: '', enabled: false)]),
            onEditOrigin: (origin) => _editOrigin(context, vm, origin),
          ),
        ],
      ),
    );
  }
}

/// On a request set to "Inherit from parent": which auth that is and where it comes from, with an
/// action that copies it into the request so it can be changed there. Renders nothing for any other
/// auth type, or outside an [InheritedDefaultsViewModel].
class RequestInheritedAuth extends StatelessWidget {
  final RequestAuth auth;
  final ValueChanged<RequestAuth> onOverride;

  const RequestInheritedAuth({super.key, required this.auth, required this.onOverride});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InheritedDefaultsViewModel?>();
    if (auth.type != AuthType.inherit || vm == null || !vm.isLoaded) return const SizedBox.shrink();
    final inherited = vm.inherited.auth;
    final origin = vm.inherited.authOrigin;
    final String message;
    if (inherited == null || origin == null) {
      message = 'No folder above this request and not the collection sets authentication, so none is sent.';
    } else if (inherited.type == AuthType.none) {
      message = 'The ${origin.label} sets No Auth, so none is sent.';
    } else {
      message = 'Sends ${inherited.type.label} from the ${origin.label}.';
    }
    final overridable = inherited != null && inherited.type != AuthType.none;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InfoBanner(
        message: message,
        trailing: Wrap(
          spacing: 4,
          children: [
            if (origin != null)
              TextButton(onPressed: () => _editOrigin(context, vm, origin), child: const Text('Edit where it is set')),
            if (overridable) TextButton(onPressed: () => onOverride(inherited), child: const Text('Override')),
          ],
        ),
      ),
    );
  }
}

/// At the top of a request's Tests tab: the tests it inherits, read-only, each level's with its origin,
/// in the order they run (collection first), all before the request's own.
class RequestInheritedTests extends StatelessWidget {
  const RequestInheritedTests({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InheritedDefaultsViewModel?>();
    if (vm == null || vm.inherited.tests.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final textStyles = context.textStyles;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inherited tests', style: textStyles.heading),
          Text(
            'Run before this request\'s own, collection first. Change them where they are set.',
            style: textStyles.caption.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: 8),
          for (final level in vm.inherited.tests)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.sidebarBackground.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          OriginChip(origin: level.origin),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _editOrigin(context, vm, level.origin),
                            child: const Text('Edit'),
                          ),
                        ],
                      ),
                      for (final a in level.assertions)
                        _TestLine(icon: Icons.check_circle_outline, text: a.name),
                      for (final x in level.extractors)
                        _TestLine(
                          icon: Icons.download_outlined,
                          text: '${x.source.label} ${x.path} → {{${x.variableKey}}} (${x.scope.label.toLowerCase()})',
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TestLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TestLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 15, color: context.colors.secondaryText),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: context.textStyles.body, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}
