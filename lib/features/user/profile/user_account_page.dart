import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'change_password_page.dart';

class MyAccountPage extends StatelessWidget {
  const MyAccountPage({super.key});

  static const _primary = Color(0xFF0E6F73);
  static const _bg = Colors.white;
  static const _labelColor = Color(0xFF8FB7BE);
  static const _divider = Color(0xFFEAEAEA);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text(t.noUserSignedIn)),
      );
    }

    final uid = user.uid;
    final email = user.email ?? t.noEmail;

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: Text(
          t.myAccount,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          String fullName = '—';
          String phoneNumber = '—';

          if (snap.hasData && snap.data!.data() != null) {
            final data = snap.data!.data()!;

            final storedFullName = (data['fullName'] ?? '').toString().trim();
            final firstName = (data['firstName'] ?? '').toString().trim();
            final lastName = (data['lastName'] ?? '').toString().trim();

            if (storedFullName.isNotEmpty) {
              fullName = storedFullName;
            } else if (firstName.isNotEmpty || lastName.isNotEmpty) {
              fullName = [firstName, lastName].where((e) => e.isNotEmpty).join(' ');
            }

            final storedPhone = (data['phoneNumber'] ?? '').toString().trim();
            if (storedPhone.isNotEmpty) phoneNumber = storedPhone;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            children: [
              _section(label: t.fullNameLabel, value: fullName),
              const SizedBox(height: 18),

              _section(label: t.emailAddressLabel, value: email),
              const SizedBox(height: 18),

              // ✅ Phone section (changeable)
              _sectionEditable(
                context: context,
                label: "PHONE NUMBER",
                value: phoneNumber,
                changeText: t.change,
                onChange: () => _showEditPhoneDialog(
                  context: context,
                  docRef: docRef,
                  currentValue: phoneNumber == '—' ? '' : phoneNumber,
                ),
              ),
              const SizedBox(height: 18),

              _sectionPassword(
                context: context,
                label: t.passwordLabel,
                maskedValue: '****************',
                onChange: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
                  );
                },
                changeText: t.change,
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // ✅ UI Sections
  // ============================================================
  Widget _section({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: _labelColor,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: Colors.black.withOpacity(0.65),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: _divider),
      ],
    );
  }

  Widget _sectionPassword({
    required BuildContext context,
    required String label,
    required String maskedValue,
    required VoidCallback onChange,
    required String changeText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: _labelColor,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                maskedValue,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black.withOpacity(0.65),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              onTap: onChange,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  changeText,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: _divider),
      ],
    );
  }

  Widget _sectionEditable({
    required BuildContext context,
    required String label,
    required String value,
    required VoidCallback onChange,
    required String changeText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: _labelColor,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black.withOpacity(0.65),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              onTap: onChange,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  changeText,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: _divider),
      ],
    );
  }

  // ============================================================
  // ✅ Edit Phone Dialog
  // ============================================================
  static Future<void> _showEditPhoneDialog({
    required BuildContext context,
    required DocumentReference<Map<String, dynamic>> docRef,
    required String currentValue,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    String normalizePhone(String input) {
      // keep + then digits only
      final trimmed = input.trim();
      if (trimmed.isEmpty) return '';
      if (trimmed.startsWith('+')) {
        final digits = trimmed.substring(1).replaceAll(RegExp(r'[^0-9]'), '');
        return '+$digits';
      }
      return trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    }

    String? validatePhone(String? v) {
      final raw = (v ?? '').trim();
      if (raw.isEmpty) return "Phone number is required";
      final n = normalizePhone(raw);
      final digits = n.startsWith('+') ? n.substring(1) : n;
      if (digits.length < 8 || digits.length > 15) {
        return "Enter a valid phone number";
      }
      return null;
    }

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                "Change phone number",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: "+9665xxxxxxxx or 05xxxxxxxx",
                  ),
                  validator: validatePhone,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _primary),
                  onPressed: saving
                      ? null
                      : () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;

                    setState(() => saving = true);

                    try {
                      final normalized = normalizePhone(controller.text);
                      await docRef.set(
                        {"phoneNumber": normalized},
                        SetOptions(merge: true),
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Phone number updated")),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error: $e")),
                        );
                      }
                    } finally {
                      if (context.mounted) setState(() => saving = false);
                    }
                  },
                  child: saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text("Save", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
