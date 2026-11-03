// cafe_staff_account_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class CafeStaffAccountPage extends StatelessWidget {
  final String? overrideEmail; // optional لو بدك تعرضي ايميل الكافيه من مكان ثاني

  const CafeStaffAccountPage({
    super.key,
    this.overrideEmail,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final authEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final emailToShow = (overrideEmail != null && overrideEmail!.trim().isNotEmpty)
        ? overrideEmail!.trim()
        : authEmail;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          t.staffCafeAccountTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          _SectionLabel(text: t.staffEmailAddressLabel),
          const SizedBox(height: 8),
          _ValueRow(
            value: emailToShow.isNotEmpty ? emailToShow : t.staffEmailUnknown,
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFEAEAEA)),

          _SectionLabel(text: t.staffPasswordLabel),
          const SizedBox(height: 8),
          _ValueRow(
            value: "••••••••••••••••", // masked only
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFEAEAEA)),

          const SizedBox(height: 10),
          Text(
            t.staffPasswordManagedNote,
            style: TextStyle(
              color: Colors.black.withOpacity(0.55),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        letterSpacing: 0.6,
        color: const Color(0xFF0E6F73).withOpacity(0.75),
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String value;
  const _ValueRow({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }
}