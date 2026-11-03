import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:campresso/features/common/auth/login_page.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  static const _primary = Color(0xFF0E6F73);
  static const _labelColor = Color(0xFF8FB7BE);
  static const _divider = Color(0xFFEAEAEA);

  final _formKey = GlobalKey<FormState>();

  final _current = TextEditingController();
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _loading = false;

  @override
  void dispose() {
    _current.dispose();
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    final t = AppLocalizations.of(context)!;

    switch (e.code) {
      case 'wrong-password':
        return t.errWrongPassword;
      case 'weak-password':
        return t.errWeakPassword;
      case 'requires-recent-login':
        return t.errRequiresRecentLogin;
      case 'too-many-requests':
        return t.errTooManyRequests;
      default:
        return e.message ?? t.errGeneric;
    }
  }

  Future<void> _changePassword() async {
    final t = AppLocalizations.of(context)!;

    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.noSignedInUserFound)),
      );
      return;
    }

    setState(() => _loading = true);
    final email = user.email ?? '';

    try {
      // 1) Re-authenticate (Secure)
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _current.text.trim(),
      );

      await user.reauthenticateWithCredential(credential);

      // 2) Update password
      await user.updatePassword(_newPass.text.trim());

      // 3) Clear fields
      _current.clear();
      _newPass.clear();
      _confirm.clear();

      if (!mounted) return;

      // ✅ Sign out after password change
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.passwordUpdatedLoginAgain),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // ✅ Go to Login and remove all previous pages
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginPage(prefillEmail: email),
        ),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyAuthError(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.errorPrefix}: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.black.withOpacity(0.35)),
      filled: true,
      fillColor: const Color(0xFFF6FAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: Text(
          t.changePasswordTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.securityCheckTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: _labelColor,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _current,
                  obscureText: _obscureCurrent,
                  decoration: _dec(
                    t.currentPasswordHint,
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                      icon: Icon(
                        _obscureCurrent
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.black.withOpacity(0.45),
                      ),
                    ),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return t.enterCurrentPassword;
                    if (value.length < 6) return t.passwordTooShort;
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: _divider),
                const SizedBox(height: 18),

                Text(
                  t.newPasswordTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: _labelColor,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _newPass,
                  obscureText: _obscureNew,
                  decoration: _dec(
                    t.newPasswordHint,
                    suffix: IconButton(
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                      icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility,
                        color: Colors.black.withOpacity(0.45),
                      ),
                    ),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return t.enterNewPassword;
                    if (value.length < 6) return t.minSixChars;
                    if (value == _current.text.trim()) {
                      return t.newPasswordMustBeDifferent;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                Text(
                  t.confirmNewPasswordTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: _labelColor,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _confirm,
                  obscureText: _obscureConfirm,
                  decoration: _dec(
                    t.confirmNewPasswordHint,
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.black.withOpacity(0.45),
                      ),
                    ),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return t.confirmNewPassword;
                    if (value != _newPass.text.trim()) {
                      return t.passwordsDoNotMatch;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0E6F73), Color(0xFF2E8F93)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                          color: Colors.black.withOpacity(0.10),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _loading ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                          : Text(
                        t.updatePassword,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
