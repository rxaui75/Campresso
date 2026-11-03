import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:campresso/features/common/auth/login_page.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';
import 'package:campresso/features/common/policies_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _obscure = true;
  bool _loading = false;
  bool _passwordTouched = false;
  bool _acceptedPolicies = false;
  bool _hasOpenedPolicies = false;

  static const _primary = Color(0xFF0E6F73);

  @override
  void initState() {
    super.initState();
    _password.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool _isPnuEmail(String email) {
    final e = email.trim().toLowerCase();
    return e.endsWith('@pnu.edu.sa');
  }

  String _buildFullName(String first, String last) {
    final f = first.trim();
    final l = last.trim();
    if (f.isEmpty && l.isEmpty) return '';
    if (l.isEmpty) return f;
    if (f.isEmpty) return l;
    return '$f $l';
  }

  bool _hasUppercase(String password) =>
      RegExp(r'[A-Z]').hasMatch(password.trim());

  bool _hasLowercase(String password) =>
      RegExp(r'[a-z]').hasMatch(password.trim());

  bool _hasDigit(String password) => RegExp(r'\d').hasMatch(password.trim());

  bool _hasSymbol(String password) =>
      RegExp(r'[^A-Za-z0-9]').hasMatch(password.trim());

  bool _isPasswordStrong(String password) {
    final p = password.trim();
    if (p.length < 8) return false;
    return _hasUppercase(p) && _hasSymbol(p);
  }

  String? _passwordValidator(String? v) {
    final t = AppLocalizations.of(context)!;
    final value = (v ?? '').trim();

    if (value.isEmpty) return t.enterPassword;
    if (value.length < 8) return t.passwordMustBeAtLeast8Chars;
    if (!_hasUppercase(value)) return t.passwordMustIncludeCapital;
    if (!_hasSymbol(value)) return t.passwordMustIncludeSymbol;

    return null;
  }

  int _passwordScore(String value) {
    final p = value.trim();
    if (p.isEmpty) return 0;

    int score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (_hasLowercase(p)) score++;
    if (_hasUppercase(p)) score++;
    if (_hasDigit(p)) score++;
    if (_hasSymbol(p)) score++;

    if (score > 6) score = 6;
    return score;
  }

  int _strengthLevel(String value) {
    final s = _passwordScore(value);
    if (s <= 2) return 1;
    if (s <= 4) return 2;
    return 3;
  }

  String _strengthText(AppLocalizations t, String value) {
    final lvl = _strengthLevel(value);
    if (lvl == 1) return t.passwordStrengthWeak;
    if (lvl == 2) return t.passwordStrengthMedium;
    return t.passwordStrengthStrong;
  }

  Color _strengthColor(String value) {
    final lvl = _strengthLevel(value);
    if (lvl == 1) return const Color(0xFFD64545);
    if (lvl == 2) return const Color(0xFFE6A23C);
    return const Color(0xFF1B7F3A);
  }

  Future<void> _openPoliciesPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PoliciesPage(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _hasOpenedPolicies = true;
    });
  }

  Widget _policiesAgreement() {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x220E6F73)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _acceptedPolicies,
            activeColor: _primary,
            onChanged: _hasOpenedPolicies
                ? (value) {
              setState(() => _acceptedPolicies = value ?? false);
            }
                : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment:
                isAr ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Wrap(
                    children: [
                      Text(
                        isAr
                            ? 'أوافق على الشروط وسياسة الخصوصية. '
                            : 'I agree to the Terms and Privacy Policy. ',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withOpacity(0.70),
                        ),
                      ),
                      GestureDetector(
                        onTap: _openPoliciesPage,
                        child: Text(
                          isAr ? 'قراءة السياسة' : 'Read Policy',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: _primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_hasOpenedPolicies) ...[
                    const SizedBox(height: 6),
                    Text(
                      isAr
                          ? 'يرجى قراءة السياسة أولاً قبل الموافقة.'
                          : 'Please read the policy first before agreeing.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withOpacity(0.45),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _strengthMeter(AppLocalizations t) {
    final value = _password.text.trim();
    final show = _passwordTouched || value.isNotEmpty;
    if (!show) return const SizedBox.shrink();

    final lvl = _strengthLevel(value);
    final color = _strengthColor(value);

    Widget seg(bool on) => Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 8,
        decoration: BoxDecoration(
          color: on ? color : Colors.black.withOpacity(0.10),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x220E6F73)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, size: 18, color: _primary),
              const SizedBox(width: 8),
              Text(
                t.passwordStrengthLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black.withOpacity(0.78),
                ),
              ),
              const Spacer(),
              Text(
                _strengthText(t, value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              seg(lvl >= 1),
              const SizedBox(width: 8),
              seg(lvl >= 2),
              const SizedBox(width: 8),
              seg(lvl >= 3),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t.passwordStrengthHint,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.black.withOpacity(0.60),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordHelper(AppLocalizations t) {
    final value = _password.text.trim();

    final lenOk = value.length >= 8;
    final capOk = _hasUppercase(value);
    final symOk = _hasSymbol(value);

    final allOk = lenOk && capOk && symOk;

    Color bg = const Color(0xFFF6FAFA);
    Color border = const Color(0x220E6F73);
    IconData icon = Icons.info_outline;

    if (_passwordTouched && value.isNotEmpty) {
      if (allOk) {
        bg = const Color(0xFFEFFAF3);
        border = const Color(0x331B7F3A);
        icon = Icons.check_circle_outline;
      } else {
        bg = const Color(0xFFFFF6E9);
        border = const Color(0x33B86A00);
        icon = Icons.error_outline;
      }
    }

    TextStyle style(bool ok) => TextStyle(
      fontSize: 12.8,
      fontWeight: FontWeight.w600,
      color: ok ? const Color(0xFF1B7F3A) : Colors.black.withOpacity(0.65),
    );

    Widget bullet(bool ok, String text) => Row(
      children: [
        Icon(
          ok ? Icons.check : Icons.circle,
          size: 16,
          color: ok ? const Color(0xFF1B7F3A) : Colors.black38,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style(ok))),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.passwordRequirementsTitle,
                  style: TextStyle(
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withOpacity(0.78),
                  ),
                ),
                const SizedBox(height: 8),
                bullet(lenOk, t.passwordReqMin8),
                const SizedBox(height: 6),
                bullet(capOk, t.passwordReqOneCapital),
                const SizedBox(height: 6),
                bullet(symOk, t.passwordReqOneSymbol),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final t = AppLocalizations.of(context)!;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    if (!_hasOpenedPolicies) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'يرجى قراءة الشروط وسياسة الخصوصية أولاً.'
                : 'Please read the Terms and Privacy Policy first.',
          ),
        ),
      );
      return;
    }

    if (!_acceptedPolicies) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'يجب الموافقة على الشروط وسياسة الخصوصية قبل إنشاء الحساب.'
                : 'You must agree to the Terms and Privacy Policy before creating an account.',
          ),
        ),
      );
      return;
    }

    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    final email = _email.text.trim().toLowerCase();
    final password = _password.text.trim();
    final firstName = _first.text.trim();
    final lastName = _last.text.trim();
    final phone = _phone.text.trim();

    final fullName = _buildFullName(firstName, lastName);

    if (!_isPnuEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.onlyPnuEmailsCanRegister)),
      );
      return;
    }

    if (!_isPasswordStrong(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.passwordPolicySnack)),
      );
      return;
    }

    setState(() => _loading = true);
    UserCredential? cred;
    try {
      cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user!;
      final uid = user.uid;

      await user.updateDisplayName(fullName);

      await db.collection('users').doc(uid).set({
        'uid': uid,
        'firstName': firstName,
        'lastName': lastName,
        'fullName': fullName,
        'email': email,
        'role': 'customer',
        'phoneNumber': phone,
        'phoneVerified': false,
        'deliveryAvailable': false,
        'ordersDelivered': 0,
        'earnings': 0,
        'acceptedPolicies': true,
        'acceptedPoliciesAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.accountCreatedPleaseLogin),
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoginPage(prefillEmail: email),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String msg = t.registrationFailed;

      if (e.code == 'email-already-in-use') msg = t.emailAlreadyInUse;
      if (e.code == 'invalid-email') msg = t.invalidEmail;
      if (e.code == 'weak-password') msg = t.passwordPolicySnack;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      try {
        await cred?.user?.delete();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.errorSavingUserData}: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    Alignment labelAlign() =>
        isAr ? Alignment.centerRight : Alignment.centerLeft;

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
                    children: [
                      const SizedBox(height: 24),
                      Image.asset('assets/images/logocolor.png', width: 110),
                      const SizedBox(height: 18),
                      Text(
                        t.signUpTitle,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(height: 26),

                      Align(alignment: labelAlign(), child: Text(t.firstNameLabel)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _first,
                        decoration: _inputDecoration(t.firstNameHint),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? t.enterFirstName
                            : null,
                      ),

                      const SizedBox(height: 16),

                      Align(alignment: labelAlign(), child: Text(t.lastNameLabel)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _last,
                        decoration: _inputDecoration(t.lastNameHint),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? t.enterLastName
                            : null,
                      ),

                      const SizedBox(height: 16),

                      Align(alignment: labelAlign(), child: Text(t.phoneNumberLabel)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: _inputDecoration(t.phoneNumberHint),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return t.enterPhoneNumber;
                          if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                            return t.phoneDigitsOnly;
                          }
                          if (value.length < 9) return t.phoneMin9Digits;
                          if (value.length > 10) return t.phoneMax10Digits;
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      Align(alignment: labelAlign(), child: Text(t.emailLabel)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        decoration: _inputDecoration(t.emailHint),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return t.enterYourEmail;
                          if (!_isPnuEmail(value)) {
                            return t.onlyPnuEmailsCanRegister;
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      Align(alignment: labelAlign(), child: Text(t.setPasswordLabel)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        onTap: () => setState(() => _passwordTouched = true),
                        onChanged: (_) =>
                            setState(() => _passwordTouched = true),
                        decoration: _inputDecoration(t.passwordHintDots).copyWith(
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: _passwordValidator,
                      ),

                      _strengthMeter(t),
                      _passwordHelper(t),
                      _policiesAgreement(),

                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _loading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                            t.registerButton,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            t.alreadyHaveAccountPrompt,
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.55),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LoginPage(
                                    prefillEmail: _email.text.trim(),
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              t.loginAction,
                              style: const TextStyle(
                                color: _primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
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

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.black.withOpacity(0.28),
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: const Color(0xFFF6FAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}