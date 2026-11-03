import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:campresso/features/user/register_page.dart';

// غيّري المسارات حسب مشروعك
import 'package:campresso/features/admin/cafe_staff_dashboard_page.dart';
import 'package:campresso/features/user/user_home_page.dart';

import '/flutter_gen/gen_l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  final String? prefillEmail;
  const LoginPage({super.key, this.prefillEmail});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscure = true; // 👁️ زر العين يتحكم
  bool _loading = false;

  static const _primary = Color(0xFF0E6F73);

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null && widget.prefillEmail!.isNotEmpty) {
      _email.text = widget.prefillEmail!;
    }
  }

  /// ✅ Save FCM token right after successful login
  /// IMPORTANT:
  /// - Save as MAP {token:true} in `fcmTokens` to match Cloud Functions.
  /// - Keep `fcmToken` as a simple fallback string (optional but helpful).
  Future<void> _saveFcmTokenForUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // iOS permission (safe on Android too)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    await userRef.set({
      'fcmToken': token,

      'fcmTokens': {token: true},

      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// After login:
  /// - If uid matches cafes.adminUid -> Staff (open CafeStaffDashboardPage)
  /// - else -> Customer (open UserHomePage)
  Future<void> _routeAfterLogin() async {
    final t = AppLocalizations.of(context)!;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.loginRouteMissingUser)),
      );
      return;
    }

    try {
      final qs = await FirebaseFirestore.instance
          .collection('cafes')
          .where('adminUid', isEqualTo: uid)
          .limit(1)
          .get();

      // Staff account
      if (qs.docs.isNotEmpty) {
        final cafeDoc = qs.docs.first;
        final data = cafeDoc.data();

        final isAr = Localizations.localeOf(context).languageCode == 'ar';

        final cafeName = isAr
            ? (data['name_ar'] ?? data['name'] ?? t.staffDefaultCafeName)
            .toString()
            : (data['name_en'] ?? data['name'] ?? t.staffDefaultCafeName)
            .toString();

        final logoAsset =
        (data['logoAsset'] ?? 'assets/images/logocolor.png').toString();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CafeStaffDashboardPage(
              cafeId: cafeDoc.id,
              cafeName: cafeName,
              cafeLogoAsset: logoAsset,
            ),
          ),
        );
        return;
      }

      // Customer account (default)
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UserHomePage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final auth = FirebaseAuth.instance;

      await auth.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      // ✅ IMPORTANT: save token right after login
      await _saveFcmTokenForUser();

      await _routeAfterLogin();
    } on FirebaseAuthException catch (e) {
      final t = AppLocalizations.of(context)!;
      String msg = t.loginFailed;

      if (e.code == 'user-not-found') {
        msg = t.noUserFoundForThisEmail;
      } else if (e.code == 'wrong-password') {
        msg = t.incorrectPassword;
      } else if (e.code == 'invalid-email') {
        msg = t.invalidEmailAddress;
      } else if (e.code == 'user-disabled') {
        msg = t.loginUserDisabled;
      } else if (e.code == 'too-many-requests') {
        msg = t.loginTooManyRequests;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.loginFailed)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final t = AppLocalizations.of(context)!;

    final email = _email.text.trim();


    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.enterYourEmail)),
      );
      return;
    }

    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.invalidEmail)),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.resetPasswordEmailSent)),
      );
    } on FirebaseAuthException catch (e) {
      String msg = t.loginFailed;

      if (e.code == 'user-not-found') {
        msg = t.noUserFoundForThisEmail;
      } else if (e.code == 'invalid-email') {
        msg = t.invalidEmailAddress;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.loginFailed)),
      );
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 22),
                      Image.asset(
                        'assets/images/logocolor.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        t.loginTitle,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Align(
                        alignment: isAr
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Text(
                          t.emailLabel,
                          style: const TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        decoration: InputDecoration(
                          hintText: t.emailHint,
                          hintStyle:
                          TextStyle(color: Colors.black.withOpacity(0.35)),
                          filled: true,
                          fillColor: const Color(0xFFF6FAFA),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return t.enterYourEmail;
                          if (!value.contains('@')) return t.invalidEmail;
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: isAr
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Text(
                          t.passwordLabel,
                          style: const TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        obscuringCharacter: '•',
                        enableSuggestions: false,
                        autocorrect: false,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        textDirection:
                        isAr ? TextDirection.rtl : TextDirection.ltr,
                        textAlign: isAr ? TextAlign.right : TextAlign.left,
                        decoration: InputDecoration(
                          hintText: t.passwordHintDots,
                          hintStyle:
                          TextStyle(color: Colors.black.withOpacity(0.35)),
                          filled: true,
                          fillColor: const Color(0xFFF6FAFA),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.black.withOpacity(0.45),
                            ),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return t.enterYourPassword;
                          return null;
                        },
                        onFieldSubmitted: (_) => _loading ? null : _login(),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment:
                        isAr ? Alignment.centerLeft : Alignment.centerRight,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: Text(
                            t.forgotPassword,
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.55),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 46),
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
                            onPressed: _loading ? null : _login,
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
                                valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                                : Text(
                              t.loginButton,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            t.noAccountPrompt,
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SignUpPage()),
                              );
                            },
                            child: Text(
                              t.createAccountAction,
                              style: const TextStyle(
                                color: _primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}