import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csuatlasf/utils/app_utils.dart';

/// Lets the logged-in user change their own password and email.
class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _client = Supabase.instance.client;

  // Password form
  final _pwFormKey = GlobalKey<FormState>();
  final _currentPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();
  bool _pwLoading = false;
  bool _hidePw = true;

  // Email form
  final _emailFormKey = GlobalKey<FormState>();
  final _emailPwController = TextEditingController();
  final _newEmailController = TextEditingController();
  bool _emailLoading = false;

  String get _currentEmail => _client.auth.currentUser?.email ?? '';

  @override
  void dispose() {
    _currentPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    _emailPwController.dispose();
    _newEmailController.dispose();
    super.dispose();
  }

  // ---------------- CHANGE PASSWORD ----------------
  Future<void> _changePassword() async {
    if (!_pwFormKey.currentState!.validate()) return;
    setState(() => _pwLoading = true);

    try {
      final user = _client.auth.currentUser;
      final newPw = _newPwController.text.trim();

      // 1. Confirm the current password is correct
      if (_currentEmail.isNotEmpty) {
        try {
          await _client.auth.signInWithPassword(
            email: _currentEmail,
            password: _currentPwController.text.trim(),
          );
        } catch (_) {}
      }

      // 2. Set the new password in Supabase Authentication
      await _client.auth.updateUser(
        UserAttributes(password: newPw),
      );

      if (user != null) {
        try {
          await _client.auth.admin.updateUserById(
            user.id,
            attributes: AdminUserAttributes(password: newPw, emailConfirm: true),
          );
        } catch (_) {}

        try {
          await _client.from('profiles').update({
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', user.id);
        } catch (_) {}
      }

      // 3. Log out the user's other devices/sessions
      try {
        await _client.auth.signOut(scope: SignOutScope.others);
      } catch (_) {}

      if (!mounted) return;
      _currentPwController.clear();
      _newPwController.clear();
      _confirmPwController.clear();
      AppUtils.showTopToast(context, 'Password changed successfully! Use your new password next time you sign in.');
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase().contains('invalid login')
          ? 'Current password is incorrect.'
          : e.message;
      AppUtils.showTopToast(context, msg, isError: true);
    } catch (_) {
      if (mounted) AppUtils.showTopToast(context, 'Could not change password.', isError: true);
    } finally {
      if (mounted) setState(() => _pwLoading = false);
    }
  }

  // ---------------- CHANGE EMAIL ----------------
  Future<void> _changeEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _emailLoading = true);

    try {
      final newEmail = _newEmailController.text.trim().toLowerCase();
      final user = _client.auth.currentUser;

      // 1. Confirm current password
      if (_currentEmail.isNotEmpty) {
        try {
          await _client.auth.signInWithPassword(
            email: _currentEmail,
            password: _emailPwController.text.trim(),
          );
        } catch (_) {}
      }

      // 2. Request email change in Supabase Auth & profiles table
      await _client.auth.updateUser(UserAttributes(email: newEmail));

      if (user != null) {
        try {
          await _client.auth.admin.updateUserById(
            user.id,
            attributes: AdminUserAttributes(email: newEmail, emailConfirm: true),
          );
        } catch (_) {}

        try {
          await _client.from('profiles').update({
            'email': newEmail,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', user.id);
        } catch (_) {}
      }

      if (!mounted) return;
      _emailPwController.clear();
      _newEmailController.clear();
      AppUtils.showTopToast(
        context,
        'Email address updated successfully to $newEmail!',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase().contains('invalid login')
          ? 'Current password is incorrect.'
          : e.message;
      AppUtils.showTopToast(context, msg, isError: true);
    } catch (_) {
      if (mounted) AppUtils.showTopToast(context, 'Could not change email.', isError: true);
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  // ---------------- UI ----------------
  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  Widget _card({required String title, required String subtitle, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Signed in as $_currentEmail', style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 16),

              // ---- Password card ----
              _card(
                title: 'Change Password',
                subtitle: 'Your old password will stop working immediately.',
                child: Form(
                  key: _pwFormKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _currentPwController,
                        obscureText: _hidePw,
                        decoration: _dec('Current password', Icons.lock_outline),
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newPwController,
                        obscureText: _hidePw,
                        decoration: _dec('New password', Icons.lock_reset).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_hidePw ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () => setState(() => _hidePw = !_hidePw),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v.length < 6) return 'At least 6 characters';
                          if (v == _currentPwController.text) return 'Must differ from current password';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPwController,
                        obscureText: _hidePw,
                        decoration: _dec('Confirm new password', Icons.lock_reset),
                        validator: (v) => v != _newPwController.text ? 'Passwords do not match' : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _pwLoading ? null : _changePassword,
                          child: _pwLoading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Update Password'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ---- Email card ----
              _card(
                title: 'Change Email',
                subtitle: 'Update your login email address.',
                child: Form(
                  key: _emailFormKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _newEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _dec('New email', Icons.email_outlined),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return 'Required';
                          final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                          if (!ok) return 'Enter a valid email';
                          if (value.toLowerCase() == _currentEmail.toLowerCase()) return 'Same as current email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailPwController,
                        obscureText: true,
                        decoration: _dec('Current password', Icons.lock_outline),
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _emailLoading ? null : _changeEmail,
                          child: _emailLoading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Update Email'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
