import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/method_badge.dart';
import 'mock_server_view_model.dart';

/// The routes the server answers, each with the scenario it is under, and the address a device reaches the server at.
class MockRoutesTab extends StatelessWidget {
  final MockServerViewModel vm;
  final String? lanIp;
  final Future<void> Function(String text, [String? what]) onCopy;

  const MockRoutesTab({super.key, required this.vm, required this.lanIp, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final routes = vm.routes;
    final addresses = vm.baseUrls(lanIp: lanIp);
    return ListView(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      children: [
        if (addresses.isNotEmpty)
          ToolSection(
            title: 'Base URL for each device',
            hint: 'localhost is the phone itself on an emulator or a phone: use the address that fits where the app runs.',
            child: Column(
              children: [
                for (final a in addresses)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.url, style: context.textStyles.mono),
                    subtitle: Text('${a.label}${a.note.isEmpty ? '' : ' · ${a.note}'}', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                    trailing: IconButton(icon: const Icon(Icons.copy, size: 16), tooltip: 'Copy ${a.url}', onPressed: () => onCopy(a.url)),
                  ),
              ],
            ),
          ),
        ToolSection(
          title: 'Routes (${routes.length})',
          padding: EdgeInsets.zero,
          child: routes.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: EmptyHint(
                    icon: Icons.alt_route,
                    title: vm.source == MockSourceKind.openApi ? 'No document loaded yet' : 'No routes yet',
                    message: vm.source == MockSourceKind.openApi
                        ? 'Open the From OpenAPI tab and load a document. Its operations become routes.'
                        : 'Press Start. Routes come from the saved examples of the collection\'s requests.',
                  ),
                )
              : Column(
                  children: [
                    for (final r in routes)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: MethodBadge(method: r.method, width: 44),
                        title: Text(r.path, style: context.textStyles.mono),
                        subtitle: Text(
                          [r.title, if (r.note.isNotEmpty) r.note, if (vm.scenarios.routes[r.key] case final s? when !s.isNormal) 'scenario: ${s.label}'].join(' · '),
                          style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                        ),
                        trailing: r.status == null ? null : Text('${r.status}', style: TextStyle(color: colors.forStatus(r.status!), fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
