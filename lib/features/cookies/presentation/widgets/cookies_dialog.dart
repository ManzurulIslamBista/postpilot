import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/cookie_entity.dart';
import '../../domain/entities/domain_cookies_entity.dart';
import '../view_models/cookies_view_model.dart';

class CookiesDialog extends StatefulWidget {
  const CookiesDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(context: context, builder: (_) => const CookiesDialog());

  @override
  State<CookiesDialog> createState() => _CookiesDialogState();
}

class _CookiesDialogState extends State<CookiesDialog> {
  late final CookiesViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<CookiesViewModel>();
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CookiesViewModel>.value(
      value: _viewModel,
      child: Consumer<CookiesViewModel>(
        builder: (context, vm, _) => Dialog(
          child: SizedBox(
            width: 640,
            height: 480,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(child: Text('Cookies', style: context.textStyles.heading)),
                      if (vm.domains.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                          tooltip: 'Clear all cookies',
                          onPressed: () => _clearAll(context, vm),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: kIsWeb
                      ? const Center(child: Text('Cookies are managed by the browser on web.'))
                      : vm.domains.isEmpty
                          ? const Center(child: Text('No cookies stored yet'))
                          : ListView(children: [for (final group in vm.domains) _DomainGroup(group: group)]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _clearAll(BuildContext context, CookiesViewModel vm) async {
    final confirmed = await showConfirmDialog(context, title: 'Clear cookies', message: 'Delete all stored cookies?');
    if (confirmed) await vm.clearAll();
  }
}

class _DomainGroup extends StatelessWidget {
  final DomainCookiesEntity group;
  const _DomainGroup({required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${group.domain} (${group.cookies.length})',
                  style: context.textStyles.caption.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Clear cookies for this domain',
                onPressed: () => _clearDomain(context),
              ),
            ],
          ),
        ),
        for (final cookie in group.cookies) _CookieTile(cookie: cookie),
      ],
    );
  }

  Future<void> _clearDomain(BuildContext context) async {
    final confirmed =
        await showConfirmDialog(context, title: 'Clear cookies', message: 'Delete all cookies for "${group.domain}"?');
    if (confirmed && context.mounted) await context.read<CookiesViewModel>().clearDomain(group.domain);
  }
}

class _CookieTile extends StatelessWidget {
  final CookieEntity cookie;
  const _CookieTile({required this.cookie});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text('${cookie.name}=${cookie.value}', style: context.textStyles.mono, overflow: TextOverflow.ellipsis),
      subtitle: Text(_details(), style: context.textStyles.caption),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        tooltip: 'Delete cookie',
        onPressed: () => _delete(context),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    await context.read<CookiesViewModel>().deleteCookie(cookie);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted cookie "${cookie.name}"')));
    }
  }

  String _details() {
    final expires = cookie.expires;
    return [
      'Path ${cookie.path.isEmpty ? '/' : cookie.path}',
      expires == null ? 'Session' : 'Expires ${_formatTimestamp(expires)}',
      if (cookie.secure) 'Secure',
      if (cookie.httpOnly) 'HttpOnly',
    ].join(' · ');
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
