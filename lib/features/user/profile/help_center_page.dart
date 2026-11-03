import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'contact_us_page.dart'; // ✅ تأكدي المسار صحيح

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  int? _expandedIndex;

  void _goToContactUs() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ContactUsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const teal = Color(0xFF0E6F73);
    final cardBg = const Color(0xFFD9ECEE); // قريب من اللون بالصورة

    final items = <_FaqItem>[
      _FaqItem(q: t.helpQ1, a: t.helpA1),
      _FaqItem(q: t.helpQ2, a: t.helpA2),
      _FaqItem(q: t.helpQ3, a: t.helpA3),

      // ✅ هذا السؤال يروح لصفحة Contact Us مباشرة
      _FaqItem(
        q: t.helpQ4, // مثال: "How do I contact support?"
        a: t.helpA4,
        onTap: _goToContactUs,
      ),

      _FaqItem(q: t.helpQ5, a: t.helpA5),
      _FaqItem(q: t.helpQ6, a: t.helpA6),
      _FaqItem(q: t.helpQ7, a: t.helpA7),
      _FaqItem(q: t.helpQ8, a: t.helpA8),
      _FaqItem(q: t.helpQ9, a: t.helpA9),

      // ✅ هذا السؤال (تغيير اللغة) يروح Contact Us بدل ما يفتح Answer
      _FaqItem(
        q: t.helpQ10, // "How do I change the app language?"
        a: t.helpA10,
        onTap: _goToContactUs,
      ),
    ];

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
          t.helpCenterTitle,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          final expanded = _expandedIndex == i;
          final isNav = it.onTap != null;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (isNav) {
                      it.onTap!.call();
                      return;
                    }
                    setState(() => _expandedIndex = expanded ? null : i);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.vertical(
                        top: const Radius.circular(14),
                        bottom: Radius.circular((!isNav && expanded) ? 0 : 14),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            it.q,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Icon(
                          isNav
                              ? Icons.arrow_forward_ios
                              : (expanded ? Icons.keyboard_arrow_down : Icons.arrow_forward_ios),
                          size: (!isNav && expanded) ? 22 : 16,
                          color: Colors.black.withOpacity(0.55),
                        ),
                      ],
                    ),
                  ),
                ),

                // ✅ إذا Navigation Item ما نعرض أي Answer
                if (!isNav)
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                      child: Text(
                        it.a,
                        style: TextStyle(
                          height: 1.45,
                          color: Colors.black.withOpacity(0.65),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    crossFadeState:
                    expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 180),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: teal,
        onPressed: _goToContactUs, // ✅ بدل Snackbar
        child: const Icon(Icons.support_agent, color: Colors.white),
      ),
    );
  }
}

class _FaqItem {
  final String q;
  final String a;
  final VoidCallback? onTap; // ✅ جديد

  _FaqItem({
    required this.q,
    required this.a,
    this.onTap,
  });
}
