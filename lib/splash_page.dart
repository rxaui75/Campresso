import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:campresso/features/common/onboarding/onboarding_page.dart';
import 'package:campresso/features/common/auth/login_page.dart';
import 'package:campresso/features/user/user_home_page.dart';
import 'package:campresso/features/admin/cafe_staff_dashboard_page.dart';

class SplashPage extends StatefulWidget {
  final bool seenOnboarding;

  const SplashPage({Key? key, required this.seenOnboarding}) : super(key: key);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _goNext();
  }

  Future<void> _goNext() async {
    await Future.delayed(const Duration(seconds: 4));

    if (!mounted) return;

    if (!widget.seenOnboarding) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingPage()),
      );
      return;
    }

    final user = await FirebaseAuth.instance.authStateChanges().first;

    if (!mounted) return;

    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }

    await _routeLoggedInUser(user.uid);
  }

  Future<void> _routeLoggedInUser(String uid) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('cafes')
          .where('adminUid', isEqualTo: uid)
          .limit(1)
          .get();

      if (!mounted) return;

      if (qs.docs.isNotEmpty) {
        final cafeDoc = qs.docs.first;
        final data = cafeDoc.data();

        final cafeName =
        (data['name_en'] ?? data['name'] ?? 'Cafe').toString();

        final logoAsset =
        (data['logoAsset'] ?? 'assets/images/logocolor.png').toString();

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
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UserHomePage()),
        );
      }
    } catch (_) {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UserHomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFF006D6F),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 120,
            ),
            const SizedBox(height: 20),
            const Text(
              'CAMPRESSO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}