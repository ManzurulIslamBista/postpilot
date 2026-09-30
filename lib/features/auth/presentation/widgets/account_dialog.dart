import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/auth_view_model.dart';

class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const AccountDialog());

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    return Dialog(
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: vm.currentUser == null ? _buildSignedOut(context, vm) : _buildSignedIn(context, vm),
        ),
      ),
    );
  }

  Widget _buildSignedOut(BuildContext context, AuthViewModel vm) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_isSignUp ? 'Sign up' : 'Sign in', style: context.textStyles.heading),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          onSubmitted: (_) => vm.isLoading ? null : _submit(context, vm),
        ),
        if (vm.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(vm.errorMessage!, style: TextStyle(color: context.colors.statusError)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: vm.isLoading ? null : () => _submit(context, vm),
          child: vm.isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isSignUp ? 'Sign up' : 'Sign in'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: vm.isLoading ? null : () => setState(() => _isSignUp = !_isSignUp),
          child: Text(_isSignUp ? 'Already have an account? Sign in' : "Don't have an account? Sign up"),
        ),
      ],
    );
  }

  Widget _buildSignedIn(BuildContext context, AuthViewModel vm) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Account', style: context.textStyles.heading),
        const SizedBox(height: 16),
        Text(vm.currentUser!.email),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: vm.isLoading ? null : vm.signOut,
          child: vm.isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign out'),
        ),
      ],
    );
  }

  Future<void> _submit(BuildContext context, AuthViewModel vm) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an email and password')));
      return;
    }
    if (_isSignUp) {
      await vm.signUp(email, password);
    } else {
      await vm.signIn(email, password);
    }
    if (!context.mounted || vm.infoMessage == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.infoMessage!)));
  }
}
