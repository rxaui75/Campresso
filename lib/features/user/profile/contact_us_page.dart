import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class ContactUsPage extends StatefulWidget {
  const ContactUsPage({super.key});

  @override
  State<ContactUsPage> createState() => _ContactUsPageState();
}

class _ContactUsPageState extends State<ContactUsPage> {
  static const _primary = Color(0xFF0E6F73);
  static const _bg = Colors.white;

  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final authEmail = user.email ?? '';
    if (authEmail.isNotEmpty) _email.text = authEmail;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = snap.data();
      if (data == null) return;

      final fullName = (data['fullName'] ?? '').toString().trim();
      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();

      final computed = fullName.isNotEmpty
          ? fullName
          : [first, last].where((e) => e.isNotEmpty).join(' ');

      if (computed.isNotEmpty && mounted) {
        setState(() => _name.text = computed);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    setState(() => _loading = true);

    try {
      await FirebaseFirestore.instance.collection('contact_messages').add({
        'uid': user?.uid,
        'name': _name.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'message': _message.text.trim(),
        'status': 'new',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.messageSent),
          behavior: SnackBarBehavior.floating,
        ),
      );

      _message.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context)!.sendFailed}: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.black.withOpacity(0.30)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.10)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primary, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: Text(
          t.contactUs,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),

                Text(
                  t.letsTalk,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  t.contactDescription,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 26),

                _label(t.name),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  decoration: _dec(t.name),
                  validator: (v) =>
                  (v ?? '').trim().isEmpty ? t.enterName : null,
                ),

                const SizedBox(height: 18),

                _label(t.email),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _dec(t.email),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return t.enterEmail;
                    if (!value.contains('@')) return t.invalidEmail;
                    return null;
                  },
                ),

                const SizedBox(height: 18),

                _label(t.message),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _message,
                  maxLines: 6,
                  decoration: _dec(t.messageHint),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return t.writeMessage;
                    if (text.length < 10) return t.messageTooShort;
                    return null;
                  },
                ),

                const SizedBox(height: 22),

                Center(
                  child: SizedBox(
                    width: 220,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
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
                        t.send,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }
}
