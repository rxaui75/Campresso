// cafe_staff_help_center_page.dart
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class CafeStaffHelpCenterPage extends StatefulWidget {
  final bool asTab; // لو تفتحيها من البروفايل خليها false
  const CafeStaffHelpCenterPage({super.key, this.asTab = false});

  @override
  State<CafeStaffHelpCenterPage> createState() => _CafeStaffHelpCenterPageState();
}

class _CafeStaffHelpCenterPageState extends State<CafeStaffHelpCenterPage> {
  static const _teal = Color(0xFF0E6F73);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final faqs = <_FaqItem>[
      _FaqItem(
        q: t.staffHelpQLogin,
        a: t.staffHelpALogin,
      ),
      _FaqItem(
        q: t.staffHelpQForgotPassword,
        a: t.staffHelpAForgotPassword,
      ),
      _FaqItem(
        q: t.staffHelpQWhenOrdersAppear,
        a: t.staffHelpAWhenOrdersAppear,
      ),
      _FaqItem(
        q: t.staffHelpQViewNewOrders,
        a: t.staffHelpAViewNewOrders,
      ),
      _FaqItem(
        q: t.staffHelpQUpdateStatus,
        a: t.staffHelpAUpdateStatus,
      ),
      _FaqItem(
        q: t.staffHelpQCancelOrder,
        a: t.staffHelpACancelOrder,
      ),
      _FaqItem(
        q: t.staffHelpQDeliveryOrders,
        a: t.staffHelpADeliveryOrders,
      ),
      _FaqItem(
        q: t.staffHelpQNoOrders,
        a: t.staffHelpANoOrders,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          t.helpCenter,
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
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
        itemCount: faqs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, i) {
          final item = faqs[i];
          return _FaqCard(
            question: item.q,
            answer: item.a,
            accent: _teal,
          );
        },
      ),
    );
  }
}

class _FaqItem {
  final String q;
  final String a;
  _FaqItem({required this.q, required this.a});
}

class _FaqCard extends StatefulWidget {
  final String question;
  final String answer;
  final Color accent;

  const _FaqCard({
    required this.question,
    required this.answer,
    required this.accent,
  });

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF0E6F73).withOpacity(0.15);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        color: Colors.white,
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !_open),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(14),
                  bottom: Radius.circular(_open ? 0 : 14),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.black.withOpacity(0.75),
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    color: Colors.black.withOpacity(0.55),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Text(
                widget.answer,
                style: TextStyle(
                  height: 1.35,
                  color: Colors.black.withOpacity(0.60),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}