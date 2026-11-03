import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'package:campresso/features/common/auth/login_page.dart';
import 'package:campresso/features/user/delivery/delivery_controller.dart';

import 'user_account_page.dart';
import 'payment_method_page.dart';
import 'about_us_page.dart';
import 'contact_us_page.dart';
import 'languages_page.dart';
import 'package:campresso/features/common/policies_page.dart';
import 'help_center_page.dart';
import 'tips_page.dart';

class ProfilePage extends StatefulWidget {
  final bool asTab;
  const ProfilePage({super.key, this.asTab = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Timer? _heartbeatTimer;
  bool _isTogglingDelivery = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _userRef {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  void dispose() {
    _stopHeartbeat();
    super.dispose();
  }

  // ✅ Heartbeat: keep deliveryLastActiveAt fresh while availableForDelivery = true
  void _startHeartbeat() {
    if (_heartbeatTimer != null) return;

    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final ref = _userRef;
      if (ref == null) return;

      try {
        await ref.update({
          'deliveryLastActiveAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // ignore - offline / permissions / etc.
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _setDeliveryAvailability(bool value) async {
    if (_isTogglingDelivery) return;

    setState(() => _isTogglingDelivery = true);

    try {
      if (value) {
        await DeliveryController.instance.setAvailable(true);
        _startHeartbeat();
      } else {
        _stopHeartbeat();
        await DeliveryController.instance.setAvailable(false);
      }
    } catch (e) {
      debugPrint('❌ set delivery availability failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isTogglingDelivery = false);
      }
    }
  }

  // ✅ Overlay Logout like the screenshot (iOS style on iOS)
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
            child: Text(
              t.yes,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm != true) return;

    try {
      await DeliveryController.instance.setAvailable(false);
    } catch (_) {}

    _stopHeartbeat();

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  // ✅ Tips stream (active tips for CURRENT user only)
  Stream<QuerySnapshot<Map<String, dynamic>>> _tipsStream() {
    final uid = _uid;
    if (uid == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('delivery_tips')
        .where('active', isEqualTo: true)
        .where('deliveryPartnerId', isEqualTo: uid)
        .snapshots();
  }

  // ✅ User stream (for switch state)
  Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream() {
    final ref = _userRef;
    if (ref == null) {
      return const Stream.empty();
    }
    return ref.snapshots();
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

          // ===== Delivery Toggle Section =====
          _sectionHeader(t.delivery),

          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _userStream(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? {};
              final bool available = (data['availableForDelivery'] == true);

              // إذا ON تأكدي إن heartbeat شغال
              if (available && _heartbeatTimer == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _startHeartbeat();
                });
              }

              // إذا OFF أوقفي heartbeat
              if (!available && _heartbeatTimer != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _stopHeartbeat();
                });
              }

              final bool canToggle = snap.hasData && !_isTogglingDelivery;

              return _switchTile(
                title: t.availableForDelivery,
                subtitle: t.deliveryToggleHint,
                value: available,
                onChanged: canToggle ? _setDeliveryAvailability : null,
              );
            },
          ),

          // ✅ Tips tile (Firestore count)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _tipsStream(),
            builder: (context, snap) {
              final int tipsCount = snap.hasData ? snap.data!.docs.length : 0;

              return _menuTile(
                title: t.tipsTitle,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyTipsPage()),
                  );
                },
                trailing: _badgeTrailing(
                  count: tipsCount,
                  showArrow: true,
                ),
              );
            },
          ),

          divider,

          // ===== Main Items =====
          _sectionHeader(t.settings),
          _menuTile(
            title: t.myAccount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyAccountPage()),
              );
            },
          ),
          divider,
          _menuTile(
            title: t.paymentMethod,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentMethodPage()),
              );
            },
          ),
          divider,
          _menuTile(
            title: t.aboutUs,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutUsPage()),
              );
            },
          ),
          divider,
          _menuTile(
            title: t.contactUs,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactUsPage()),
              );
            },
          ),
          divider,
          _menuTile(
            title: t.languages,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LanguagesPage()),
              );
            },
          ),
          divider,
          _menuTile(
            title: t.privacyPolicy,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PoliciesPage()),
              );
            },
          ),
          divider,
          _menuTile(
            title: t.helpCenter,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpCenterPage()),
              );
            },
          ),
          divider,

          // ✅ Logout as action (no chevron)
          _menuTile(
            title: t.logout,
            titleColor: const Color(0xFFD32F2F),
            onTap: _confirmLogout,
            trailing: const Icon(Icons.logout_rounded, color: Color(0xFFD32F2F)),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------- UI Helpers ----------

  Widget _sectionHeader(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      color: Colors.white,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _menuTile({
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
      trailing:
      trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.black38),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 0,
      horizontalTitleGap: 0,
      dense: true,
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF0E7C86),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget _badgeTrailing({
    required int count,
    required bool showArrow,
  }) {
    final showBadge = count > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0E6F73),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              "$count",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        if (showArrow) ...[
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right_rounded, color: Colors.black38),
        ],
      ],
    );
  }
}