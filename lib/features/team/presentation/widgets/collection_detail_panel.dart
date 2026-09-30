import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../auth/domain/entities/app_user_entity.dart';
import '../../domain/entities/cloud_collection_entity.dart';
import '../../domain/entities/collection_invite_entity.dart';
import '../../domain/entities/collection_member_entity.dart';
import '../../domain/entities/member_role.dart';
import '../view_models/team_view_model.dart';
import 'invite_member_dialog.dart';
import 'request_tree.dart';

/// Members + folder/request tree for the collection selected in
/// [TeamDialog]. Controls are gated per the schema's RLS: only the owner
/// manages membership, only 'owner'/'editor' can write folders/requests.
class CollectionDetailPanel extends StatelessWidget {
  final CloudCollectionEntity collection;
  final AppUserEntity currentUser;

  const CollectionDetailPanel({super.key, required this.collection, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeamViewModel>();
    final isOwner = collection.ownerId == currentUser.id;
    final myRole = vm.myRole(currentUser.id);
    final canEditRequests = myRole == MemberRole.owner || myRole == MemberRole.editor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(collection.name, style: context.textStyles.heading, overflow: TextOverflow.ellipsis)),
              if (vm.canCopyCollection)
                IconButton(
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  tooltip: 'Copy to my collections',
                  onPressed: vm.isCopyingCollection || !vm.treeLoaded ? null : () => _copyToLocal(context),
                ),
              if (isOwner)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (action) => _handleCollectionAction(context, action),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (vm.collectionSyncFailed) _SyncErrorBanner(onRetry: vm.reloadCollection),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(tabs: [Tab(text: 'Members'), Tab(text: 'Requests')]),
                Expanded(
                  child: TabBarView(
                    children: [
                      _MembersTab(collection: collection, isOwner: isOwner, currentUser: currentUser),
                      CloudRequestTree(collection: collection, canEdit: canEditRequests),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Any member may copy: reading a shared collection is all it takes.
  Future<void> _copyToLocal(BuildContext context) async {
    final copied = await context.read<TeamViewModel>().copyCollectionToLocal(collection);
    if (!context.mounted) return;
    final message = copied == null
        ? 'Failed to copy "${collection.name}"'
        : 'Copied "${collection.name}" to your collections (${copied.description})';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleCollectionAction(BuildContext context, String action) async {
    final vm = context.read<TeamViewModel>();
    switch (action) {
      case 'rename':
        final name = await showPromptDialog(context, title: 'Rename collection', initialValue: collection.name);
        if (name == null || !context.mounted) return;
        final ok = await vm.renameCollection(collection.id, name);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Renamed to "$name"' : 'Failed to rename collection')));
        }
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete collection',
          message: 'Delete "${collection.name}" for every member? This cannot be undone.',
        );
        if (!confirmed || !context.mounted) return;
        final ok = await vm.deleteCollection(collection.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Deleted "${collection.name}"' : 'Failed to delete collection')));
        }
    }
  }
}

class _SyncErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _SyncErrorBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: context.colors.statusError),
          const SizedBox(width: 8),
          Expanded(child: Text('Lost connection to this collection', style: context.textStyles.caption)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Members are keyed by `auth.users` id, which RLS keeps unjoinable from the
/// client, so only the current user's own email is known. The owner also
/// sees the invites they sent (email + accepted/pending) underneath, which
/// is the closest thing to "who is that id" the schema allows.
class _MembersTab extends StatelessWidget {
  final CloudCollectionEntity collection;
  final bool isOwner;
  final AppUserEntity currentUser;

  const _MembersTab({required this.collection, required this.isOwner, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeamViewModel>();
    final sectionStyle = context.textStyles.caption.copyWith(fontWeight: FontWeight.bold);
    return Column(
      children: [
        Expanded(
          child: !vm.membersLoaded
              ? Center(child: vm.collectionSyncFailed ? const Text("Couldn't load members") : const CircularProgressIndicator())
              : vm.members.isEmpty
              ? const Center(child: Text('No members yet'))
              : ListView(
                  children: [
                    for (final member in vm.members)
                      _MemberTile(
                        member: member,
                        collection: collection,
                        isOwner: isOwner,
                        selfEmail: member.userId == currentUser.id ? currentUser.email : null,
                      ),
                    if (vm.collectionInvites.isNotEmpty) ...[
                      const Divider(height: 16),
                      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text('Invites', style: sectionStyle)),
                      for (final invite in vm.collectionInvites) _InviteTile(invite: invite),
                    ],
                  ],
                ),
        ),
        if (isOwner)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              icon: const Icon(Icons.person_add_alt_outlined, size: 16),
              label: const Text('Invite'),
              onPressed: () => _invite(context),
            ),
          ),
      ],
    );
  }

  Future<void> _invite(BuildContext context) async {
    final result = await InviteMemberDialog.show(context);
    if (result == null || !context.mounted) return;
    final (email, role) = result;
    final ok = await context.read<TeamViewModel>().inviteMember(collection.id, email, role);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Invited $email' : 'Failed to invite $email')));
    }
  }
}

class _MemberTile extends StatelessWidget {
  final CollectionMemberEntity member;
  final CloudCollectionEntity collection;
  final bool isOwner;

  /// Non-null only for the current user's own row.
  final String? selfEmail;

  const _MemberTile({required this.member, required this.collection, required this.isOwner, required this.selfEmail});

  @override
  Widget build(BuildContext context) {
    final canManage = isOwner && member.role != MemberRole.owner;
    final email = selfEmail;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.person_outline, size: 18),
      title: Text(email != null ? '$email (You)' : _shortId(member.userId), overflow: TextOverflow.ellipsis),
      subtitle: email != null ? null : Tooltip(message: member.userId, child: Text('User id', style: context.textStyles.caption)),
      trailing: canManage
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<MemberRole>(
                  value: member.role,
                  underline: const SizedBox.shrink(),
                  items: [for (final r in [MemberRole.editor, MemberRole.viewer]) DropdownMenuItem(value: r, child: Text(r.label))],
                  onChanged: (role) {
                    if (role != null) _updateRole(context, role);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.person_remove_outlined, size: 16),
                  tooltip: 'Remove member',
                  onPressed: () => _remove(context),
                ),
              ],
            )
          : Text(member.role.label, style: context.textStyles.caption),
    );
  }

  String _shortId(String userId) => userId.length > 8 ? '${userId.substring(0, 8)}…' : userId;

  Future<void> _updateRole(BuildContext context, MemberRole role) async {
    final ok = await context.read<TeamViewModel>().updateMemberRole(collection.id, member.userId, role);
    if (context.mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update role')));
    }
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showConfirmDialog(context, title: 'Remove member', message: 'Remove this member from "${collection.name}"?');
    if (!confirmed || !context.mounted) return;
    final ok = await context.read<TeamViewModel>().removeMember(collection.id, member.userId);
    if (context.mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove member')));
    }
  }
}

class _InviteTile extends StatelessWidget {
  final CollectionInviteEntity invite;
  const _InviteTile({required this.invite});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(invite.accepted ? Icons.mark_email_read_outlined : Icons.mail_outline, size: 18),
      title: Text(invite.email, overflow: TextOverflow.ellipsis),
      subtitle: Text('${invite.role.label} · ${invite.accepted ? 'Accepted' : 'Pending'}', style: context.textStyles.caption),
    );
  }
}
