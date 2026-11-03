import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  static const _primary = Color(0xFF0E6F73);
  static const _bg = Colors.white;

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
          t.aboutUs,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon / Illustration
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6FAFA),
                  borderRadius: BorderRadius.circular(65),
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/logocolor.png',
                    width: 90,
                    height: 90,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                t.whoWeAre,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                t.aboutUsDescription,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.6,
                  color: Colors.black.withOpacity(0.65),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
