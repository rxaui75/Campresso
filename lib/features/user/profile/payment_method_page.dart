import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'add_card_page.dart';

class PaymentMethodPage extends StatelessWidget {
  const PaymentMethodPage({super.key});

  static const _primary = Color(0xFF0E6F73);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(body: Center(child: Text(t.noUserSignedIn)));
    }

    final cardsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('cards')
        .orderBy('createdAt', descending: true);

    Future<void> _addCardFlow() async {
      final added = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AddCardPage()),
      );

      if (added == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.cardAddedSuccessfully),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: Text(
          t.paymentMethod,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: cardsRef.snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final hasCards = docs.isNotEmpty;

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!hasCards) {
            return _EmptyCardsState(onAdd: _addCardFlow);
          }

          return _CardsListState(
            cards: docs,
            onAdd: _addCardFlow,
          );
        },
      ),
    );
  }
}

class _EmptyCardsState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyCardsState({required this.onAdd});

  static const _primary = Color(0xFF0E6F73);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
      child: Column(
        children: [
          const Spacer(flex: 2),

          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFFF6FAFA),
              borderRadius: BorderRadius.circular(55),
            ),
            child: Center(
              child: Container(
                width: 74,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3D7A6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 12,
                      top: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(
                          3,
                              (_) => Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            width: 26,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 12,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.75),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 22),

          Text(
            t.noCardsTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            t.noCardsSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: Colors.black.withOpacity(0.45),
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 26),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                t.addCreditCard,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _CardsListState extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> cards;
  final VoidCallback onAdd;

  const _CardsListState({required this.cards, required this.onAdd});

  static const _primary = Color(0xFF0E6F73);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              t.payment,
              style: const TextStyle(
                color: Color(0xFF8B5A3C),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            itemCount: cards.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.black.withOpacity(0.06)),
            itemBuilder: (context, i) {
              final d = cards[i].data();
              final brand = (d['brand'] ?? 'visa').toString();
              final last4 = (d['last4'] ?? '0000').toString();

              final isMaster = brand.toLowerCase().contains('master');
              final brandLabel = isMaster ? t.masterCard : t.visa;

              return ListTile(
                leading: _brandIcon(brand),
                title: Text(
                  brandLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '****$last4',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                t.addCreditCard,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _brandIcon(String brand) {
    final b = brand.toLowerCase();
    if (b.contains('master')) {
      return const Icon(Icons.circle, color: Colors.red);
    }
    return const Icon(Icons.credit_card, color: Colors.blue);
  }
}
