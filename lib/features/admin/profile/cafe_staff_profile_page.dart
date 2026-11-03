// cafe_staff_profile_page.dart
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'package:campresso/features/admin/profile/cafe_staff_account_page.dart';
import 'package:campresso/features/common/policies_page.dart';
import 'package:campresso/features/user/profile/about_us_page.dart';
import 'package:campresso/features/user/profile/contact_us_page.dart';
import 'package:campresso/features/user/profile/languages_page.dart';
import 'package:campresso/features/admin/profile/cafe_staff_help_center_page.dart';
import 'package:campresso/features/common/auth/login_page.dart';

class CafeStaffProfilePage extends StatefulWidget {
  final String cafeId;
  final String cafeName;
  final String cafeLogoAsset;

  final bool asTab;

  const CafeStaffProfilePage({
    super.key,
    required this.cafeId,
    required this.cafeName,
    required this.cafeLogoAsset,
    this.asTab = true,
  });

  @override
  State<CafeStaffProfilePage> createState() => _CafeStaffProfilePageState();
}

class _CafeStaffProfilePageState extends State<CafeStaffProfilePage> {
  Future<void> _confirmLogout() async {
    final t = AppLocalizations.of(context)!;

    final bool? confirm = Platform.isIOS
        ? await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(t.logoutConfirmTitle),
        content: Text(t.logoutConfirm),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.yes),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
        ],
      ),
    )
        : await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(t.logoutConfirmTitle),
        content: Text(t.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.yes, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
    );
  }

  Widget _tile({
    required String title,
    required VoidCallback onTap,
    Color? titleColor,
    Widget? trailing,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: titleColor ?? Colors.black87,
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.black38),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
      minLeadingWidth: 0,
      horizontalTitleGap: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    const divider = Divider(height: 1, thickness: 1, color: Color(0xFFEAEAEA));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          t.profile,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        automaticallyImplyLeading: !widget.asTab,
        leading: widget.asTab
            ? null
            : IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          divider,

          _tile(
            title: t.staffCafeAccount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CafeStaffAccountPage()),
              );
            },
          ),
          divider,
          _tile(
            title: t.aboutUs,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutUsPage()),
            ),
          ),
          divider,
          _tile(
            title: t.contactUs,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactUsPage()),
            ),
          ),
          divider,
          _tile(
            title: t.languages,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LanguagesPage()),
            ),
          ),
          divider,
          _tile(
            title: t.privacyPolicy,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PoliciesPage()),
            ),
          ),
          divider,
          _tile(
            title: t.helpCenter,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CafeStaffHelpCenterPage()),
            ),
          ),
          divider,

          // ✅ Logout as action (no chevron)
          _tile(
            title: t.logout,
            titleColor: const Color(0xFFD32F2F),
            trailing: const Icon(Icons.logout_rounded, color: Color(0xFFD32F2F)),
            onTap: _confirmLogout,
          ),
          divider,

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}