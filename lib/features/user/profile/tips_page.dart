// my_tips_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class MyTipsPage extends StatelessWidget {
  const MyTipsPage({super.key});

  static const _teal = Color(0xFF0E6F73);
  static const _divider = Color(0xFFEAEAEA);

  String _fmtDate(AppLocalizations t, DateTime d) {
    return t.tipDateFormat(
      d.day.toString(),
      d.month.toString(),
      d.year.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.6,
          centerTitle: true,
          title: Text(
            t.myTipsTitle,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: Center(child: Text(t.noUserSignedIn)),
      );
    }

    final uid = user.uid;

    final tipsStream = FirebaseFirestore.instance
        .collection('orders')
        .where('deliveryPartnerId', isEqualTo: uid)
        .where('tipReleased', isEqualTo: true)
        .orderBy('tipReleasedAt', descending: true)
        .snapshots();

    final walletStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        centerTitle: true,
        title: Text(
          t.myTipsTitle,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: walletStream,
        builder: (context, walletSnap) {
          if (walletSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (walletSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "${t.error}: ${walletSnap.error}",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.withOpacity(0.8)),
                ),
              ),
            );
          }

          final walletData = walletSnap.data?.data() ?? {};
          final walletRaw = walletData['walletBalanceSar'];
          final walletBalance = walletRaw is num ? walletRaw.toDouble() : 0.0;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: tipsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "${t.error}: ${snap.error}",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.withOpacity(0.8)),
                    ),
                  ),
                );
              }

              final docs = snap.data?.docs ?? [];

              double totalTips = 0.0;
              for (final d in docs) {
                final data = d.data();
                final v = data['deliveryTip'];
                if (v is num) totalTips += v.toDouble();
              }

              final tipsCount = docs.length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                children: [
                  _walletSummaryCard(
                    t: t,
                    walletBalance: walletBalance,
                    totalTips: totalTips,
                    tipsCount: tipsCount,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    t.tipsHistoryTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: _divider),
                  const SizedBox(height: 10),
                  if (docs.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.card_giftcard,
                              size: 46,
                              color: _teal,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              t.noTipsYetTitle,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t.noTipsYetSubtitle,
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.6),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...docs.map((doc) {
                      final data = doc.data();

                      final tip = (data['deliveryTip'] is num)
                          ? (data['deliveryTip'] as num).toDouble()
                          : 0.0;

                      final orderNumber = (data['orderNumber'] ?? '').toString();
                      final cafeName =
                      (data['cafeName'] ?? data['cafeId'] ?? '').toString();

                      final createdAtTs = data['createdAt'];
                      DateTime date = DateTime.now();
                      if (createdAtTs is Timestamp) date = createdAtTs.toDate();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 7),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.black.withOpacity(0.04),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: _teal.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.card_giftcard,
                                color: _teal,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.tipEarnedLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${t.orderNumberLabel(orderNumber)} • $cafeName",
                                    style: TextStyle(
                                      color: Colors.black.withOpacity(0.6),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _fmtDate(t, date),
                                    style: TextStyle(
                                      color: Colors.black.withOpacity(0.45),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              t.tipPlusAmountSar(tip.toStringAsFixed(2)),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: _teal,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _walletSummaryCard({
    required AppLocalizations t,
    required double walletBalance,
    required double totalTips,
    required int tipsCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _teal.withOpacity(0.10),
            Colors.black.withOpacity(0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _teal.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: _teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.walletBalanceLabel,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            t.tipAmountSar(walletBalance.toStringAsFixed(2)),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.walletBalanceHint,
            style: TextStyle(
              color: Colors.black.withOpacity(0.50),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: Colors.black.withOpacity(0.08),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniStatCard(
                  icon: Icons.payments_outlined,
                  label: t.totalTipsLabel,
                  value: t.tipAmountSar(totalTips.toStringAsFixed(2)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniStatCard(
                  icon: Icons.delivery_dining,
                  label: t.ordersLabel,
                  value: tipsCount.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _teal, size: 20),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: Colors.black.withOpacity(0.55),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}