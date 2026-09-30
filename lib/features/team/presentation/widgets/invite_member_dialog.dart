import 'package:flutter/material.dart';
import '../../domain/entities/member_role.dart';

/// Collects an email + role for [TeamViewModel.inviteMember] and returns
/// them as a record, or `null` if cancelled.
class InviteMemberDialog extends StatefulWidget {
  const InviteMemberDialog({super.key});

  static Future<(String, MemberRole)?> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const InviteMemberDialog());

  @override
  State<InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<InviteMemberDialog> {
  final _emailController = TextEditingController();
  MemberRole _role = MemberRole.editor;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite teammate'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MemberRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [for (final r in [MemberRole.editor, MemberRole.viewer]) DropdownMenuItem(value: r, child: Text(r.label))],
            onChanged: (r) => setState(() => _role = r ?? _role),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => _submit(context), child: const Text('Invite')),
      ],
    );
  }

  void _submit(BuildContext context) {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    Navigator.pop(context, (email, _role));
  }
}
