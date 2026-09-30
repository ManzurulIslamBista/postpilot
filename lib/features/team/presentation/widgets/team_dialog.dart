import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../auth/domain/entities/app_user_entity.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../../auth/presentation/widgets/account_dialog.dart';
import '../../domain/entities/cloud_collection_entity.dart';
import '../../domain/entities/collection_invite_entity.dart';
import '../view_models/team_view_model.dart';
import 'collection_detail_panel.dart';

class TeamDialog extends StatefulWidget {
  const TeamDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(context: context, builder: (_) => const TeamDialog());

  @override
  State<TeamDialog> createState() => _TeamDialogState();
}

class _TeamDialogState extends State<TeamDialog> {
  late final TeamViewModel _viewModel;
  int? _selectedCollectionId;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<TeamViewModel>();
    if (context.read<AuthViewModel>().currentUser != null) _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthViewModel>().currentUser;
    return Dialog(
      child: SizedBox(
        width: 720,
        height: 520,
        child: currentUser == null ? _buildSignedOut(context) : _buildSignedIn(context, currentUser),
      ),
    );
  }

  Widget _buildSignedOut(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sign in to use team collaboration', style: context.textStyles.heading, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _openSignIn(context), child: const Text('Sign in')),
          ],
        ),
      ),
    );
  }

  Future<void> _openSignIn(BuildContext context) async {
    await AccountDialog.show(context);
    if (!context.mounted) return;
    if (context.read<AuthViewModel>().currentUser != null) {
      _viewModel.load();
      setState(() {});
    }
  }

  Widget _buildSignedIn(BuildContext context, AppUserEntity currentUser) {
    return ChangeNotifierProvider<TeamViewModel>.value(
      value: _viewModel,
      child: Consumer<TeamViewModel>(
        builder: (context, vm, _) {
          CloudCollectionEntity? selected;
          for (final c in vm.collections) {
            if (c.id == _selectedCollectionId) {
              selected = c;
              break;
            }
          }
          return Row(
            children: [
              SizedBox(width: 260, child: _CollectionsPane(selectedId: _selectedCollectionId, onSelect: _select)),
              const VerticalDivider(width: 1),
              Expanded(
                child: vm.isLoading && vm.collections.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : selected == null
                        ? const Center(child: Text('Select a collection'))
                        : CollectionDetailPanel(collection: selected, currentUser: currentUser),
              ),
            ],
          );
        },
      ),
    );
  }

  void _select(int id) {
    setState(() => _selectedCollectionId = id);
    _viewModel.selectCollection(id);
  }
}

class _CollectionsPane extends StatelessWidget {
  final int? selectedId;
  final ValueChanged<int> onSelect;

  const _CollectionsPane({required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeamViewModel>();
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              if (vm.pendingInvites.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text('Pending invites', style: context.textStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                ),
                for (final invite in vm.pendingInvites) _PendingInviteTile(invite: invite),
                const Divider(height: 16),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Text('Collections', style: context.textStyles.caption.copyWith(fontWeight: FontWeight.bold)),
              ),
              if (vm.loadFailed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text("Couldn't load your teams", style: context.textStyles.caption)),
                      TextButton(onPressed: vm.isLoading ? null : vm.load, child: const Text('Retry')),
                    ],
                  ),
                )
              else if (vm.collections.isEmpty && !vm.isLoading)
                Padding(padding: const EdgeInsets.all(12), child: Text('No shared collections yet', style: context.textStyles.caption)),
              for (final collection in vm.collections)
                ListTile(
                  dense: true,
                  selected: collection.id == selectedId,
                  leading: const Icon(Icons.folder_shared_outlined, size: 18),
                  title: Text(collection.name, overflow: TextOverflow.ellipsis),
                  onTap: () => onSelect(collection.id),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New collection'),
            onPressed: () => _create(context),
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await showPromptDialog(context, title: 'New collection');
    if (name == null || !context.mounted) return;
    final ok = await context.read<TeamViewModel>().createCollection(name);
    if (context.mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create collection')));
    }
  }
}

/// Shown before acceptance, so only the invite's own columns (collection
/// name isn't visible yet — RLS only grants that once you're a member).
class _PendingInviteTile extends StatelessWidget {
  final CollectionInviteEntity invite;
  const _PendingInviteTile({required this.invite});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.mail_outline, size: 18),
      title: Text('Collection #${invite.collectionId}', overflow: TextOverflow.ellipsis),
      subtitle: Text('Role: ${invite.role.label}', style: context.textStyles.caption),
      trailing: TextButton(onPressed: () => _accept(context), child: const Text('Accept')),
    );
  }

  Future<void> _accept(BuildContext context) async {
    final ok = await context.read<TeamViewModel>().acceptInvite(invite.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Joined collection' : 'Failed to accept invite')));
    }
  }
}
