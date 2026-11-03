import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class PoliciesPage extends StatelessWidget {
  const PoliciesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const teal = Color(0xFF0E6F73);

    // تقدري تغيري التاريخ لاحقاً من config أو Firestore أو ثابت
    const lastUpdateDate = "25/11/2025";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          t.privacyPolicyTitle,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            t.policiesLastUpdate(lastUpdateDate),
            style: const TextStyle(
              color: Color(0xFF6B7A86),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t.policiesIntro,
            style: TextStyle(
              height: 1.45,
              color: Colors.black.withOpacity(0.62),
              fontWeight: FontWeight.w600,
              fontSize: 13.2,
            ),
          ),
          const SizedBox(height: 20),

          _TitleH2(text: t.termsAndConditionsTitle),
          const SizedBox(height: 10),
          Text(
            t.termsAndConditionsIntro,
            style: TextStyle(
              height: 1.45,
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w600,
              fontSize: 13.2,
            ),
          ),
          const SizedBox(height: 16),

          _PolicyItem(num: "1.", title: t.policy1Title, body: t.policy1Body),
          const SizedBox(height: 14),
          _PolicyItem(num: "2.", title: t.policy2Title, body: t.policy2Body),
          const SizedBox(height: 14),
          _PolicyItem(num: "3.", title: t.policy3Title, body: t.policy3Body),
          const SizedBox(height: 14),
          _PolicyItem(num: "4.", title: t.policy4Title, body: t.policy4Body),
          const SizedBox(height: 14),
          _PolicyItem(num: "5.", title: t.policy5Title, body: t.policy5Body),
          const SizedBox(height: 14),
          _PolicyItem(num: "6.", title: t.policy6Title, body: t.policy6Body),
          const SizedBox(height: 14),
          _PolicyItem(num: "7.", title: t.policy7Title, body: t.policy7Body),

          const SizedBox(height: 10),
          Divider(color: Colors.black.withOpacity(0.08)),
          const SizedBox(height: 4),

          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: teal, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.policiesFooter,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.45),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TitleH2 extends StatelessWidget {
  final String text;
  const _TitleH2({required this.text});

  @override
  Widget build(BuildContext context) {
    return const Text(
      "",
    ).copyWith(text); // placeholder to keep widget simple
  }
}

extension _TextCopy on Text {
  Widget copyWith(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0E6F73),
        fontWeight: FontWeight.w900,
        fontSize: 20,
      ),
    );
  }
}

class _PolicyItem extends StatelessWidget {
  final String num;
  final String title;
  final String body;

  const _PolicyItem({
    required this.num,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          num,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.black87,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  height: 1.45,
                  color: Colors.black.withOpacity(0.65),
                  fontWeight: FontWeight.w600,
                  fontSize: 13.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
