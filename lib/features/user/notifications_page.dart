import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class NotificationsPage extends StatefulWidget {
  final bool asTab; // إذا كانت ضمن BottomNav (عادة true) نخفي زر الرجوع
  const NotificationsPage({super.key, this.asTab = true});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  int tab = 0; // 0 All, 1 Orders, 2 Ads

  // ✅ Orders TTL (hide after 24 hours)
  static const Duration _orderTTL = Duration(hours: 24);

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw Exception("User not logged in");
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> get _notifsCol =>
      FirebaseFirestore.instance.collection('users').doc(_uid).collection('notifications');

  Query<Map<String, dynamic>> _query() {
    final base = _notifsCol.orderBy('createdAt', descending: true);

    if (tab == 1) return base.where('type', isEqualTo: 'order');
    if (tab == 2) return base.where('type', isEqualTo: 'ad');
    return base;
  }

  Future<void> _markRead(DocumentReference ref, Map<String, dynamic> data) async {
    final read = (data['read'] is bool) ? (data['read'] as bool) : false;
    if (read) return;
    try {
      await ref.set({'read': true}, SetOptions(merge: true));
    } catch (_) {
      // ignore
    }
  }

  bool _isExpiredOrderNotif(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().toLowerCase().trim();
    if (type != 'order') return false;

    final ts = data['createdAt'] ?? data['updatedAt'];
    final when = (ts is Timestamp) ? ts.toDate() : null;
    if (when == null) return false;

    final age = DateTime.now().difference(when);
    return age > _orderTTL;
  }

  String _notifDedupKey(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().toLowerCase().trim();

    if (type == 'ad') {
      final cafeId = (data['cafeId'] ?? '').toString().trim();
      final adId = (data['adId'] ?? '').toString().trim();
      final title = (data['titleKey'] ?? data['title'] ?? '').toString().trim();
      final body = (data['bodyKey'] ?? data['body'] ?? '').toString().trim();

      // ✅ prefer stable ad identity if present
      if (cafeId.isNotEmpty && adId.isNotEmpty) {
        return 'ad|$cafeId|$adId';
      }

      // ✅ fallback if adId was not saved in old notifications
      return 'ad|$cafeId|$title|$body';
    }

    if (type == 'order') {
      final orderId = (data['orderId'] ?? '').toString().trim();
      final title = (data['titleKey'] ?? data['title'] ?? '').toString().trim();
      final body = (data['bodyKey'] ?? data['body'] ?? '').toString().trim();

      if (orderId.isNotEmpty) {
        return 'order|$orderId|$title|$body';
      }

      return 'order|$title|$body';
    }

    final title = (data['titleKey'] ?? data['title'] ?? '').toString().trim();
    final body = (data['bodyKey'] ?? data['body'] ?? '').toString().trim();
    return '$type|$title|$body';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _dedupeNotifications(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final seen = <String>{};
    final result = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final d in docs) {
      final key = _notifDedupKey(d.data());
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(d);
    }

    return result;
  }

  Future<bool> _shouldShowAdNotification(Map<String, dynamic> data) async {
    final type = (data['type'] ?? '').toString().toLowerCase().trim();
    if (type != 'ad') return true;

    final cafeId = (data['cafeId'] ?? '').toString().trim();
    final adId = (data['adId'] ?? '').toString().trim();

    // ✅ If old ad notifications don't have adId/cafeId, keep showing them
    // بدل ما يختفوا بالغلط
    if (cafeId.isEmpty || adId.isEmpty) return true;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('cafes')
          .doc(cafeId)
          .collection('ads')
          .doc(adId)
          .get();

      // ✅ ad deleted => hide notification
      if (!snap.exists) return false;

      final ad = snap.data() ?? <String, dynamic>{};
      final visible = (ad['visible'] is bool) ? ad['visible'] as bool : true;
      final isActive = (ad['isActive'] is bool) ? ad['isActive'] as bool : visible;

      return visible && isActive;
    } catch (_) {
      // لو صار خطأ بالشبكة أو القراءة، لا نخفيه بالغلط
      return true;
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _filterVisibleDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    final result = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final d in docs) {
      final data = d.data();

      if (_isExpiredOrderNotif(data)) continue;

      final shouldShow = await _shouldShowAdNotification(data);
      if (!shouldShow) continue;

      result.add(d);
    }

    return _dedupeNotifications(result);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    const teal = Color(0xFF0E6F73);
    final bg = Colors.black.withOpacity(0.06);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        centerTitle: true,
        title: Text(
          t.notificationsTitle,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
          ),
        ),
        automaticallyImplyLeading: !widget.asTab,
        leading: widget.asTab
            ? null
            : IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

          // ===== Segmented Tabs =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _segBtn(
                    label: t.notificationsTabAll,
                    active: tab == 0,
                    onTap: () => setState(() => tab = 0),
                    teal: teal,
                  ),
                  _segDivider(),
                  _segBtn(
                    label: t.notificationsTabOrders,
                    active: tab == 1,
                    onTap: () => setState(() => tab = 1),
                    teal: teal,
                  ),
                  _segDivider(),
                  _segBtn(
                    label: t.notificationsTabAds,
                    active: tab == 2,
                    onTap: () => setState(() => tab = 2),
                    teal: teal,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ===== List / Empty =====
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query().snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      "${t.error}: ${snap.error}",
                      style: TextStyle(color: Colors.black.withOpacity(0.65)),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;

                return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  future: _filterVisibleDocs(docs),
                  builder: (context, filteredSnap) {
                    if (!filteredSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());}
                    final docsFiltered = filteredSnap.data!;
                    if (docsFiltered.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 26),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: teal.withOpacity(0.10),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.notifications_none,
                                  size: 34,
                                  color: teal.withOpacity(0.95),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _emptyTitle(t),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _emptySubtitle(t),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  height: 1.4,
                                  color: Colors.black.withOpacity(0.55),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      itemCount: docsFiltered.length,
                      itemBuilder: (context, i) {
                        final d = docsFiltered[i];
                        final data = d.data();

                        final type = (data['type'] ?? '').toString().toLowerCase().trim();
                        final read = (data['read'] is bool) ? (data['read'] as bool) : false;

                        final ts = data['createdAt'] ?? data['updatedAt'];
                        final when = (ts is Timestamp) ? ts.toDate() : DateTime.now();

                        final title = _resolveLocalizedText(
                          t: t,
                          keyName: (data['titleKey'] ?? data['title'] ?? '').toString(),
                          args: (data['args'] is Map)
                              ? Map<String, dynamic>.from(data['args'] as Map)
                              : const <String, dynamic>{},
                          fallback: (data['title'] ?? '').toString(),
                        );

                        final body = _resolveLocalizedText(
                          t: t,
                          keyName: (data['bodyKey'] ?? data['body'] ?? '').toString(),
                          args: (data['args'] is Map)
                              ? Map<String, dynamic>.from(data['args'] as Map)
                              : const <String, dynamic>{},
                          fallback: (data['body'] ?? '').toString(),
                        );

                        final icon = type == 'ad' ? Icons.percent : Icons.receipt_long;
                        final iconBg = teal.withOpacity(0.10);
                        final border = teal.withOpacity(0.35);

                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            await _markRead(d.reference, data);

                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: border, width: 1.2),
                              color: read ? Colors.white : const Color(0xFFF5FAFB),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 16,
                                  offset: const Offset(0, 10),
                                  color: Colors.black.withOpacity(0.05),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: iconBg,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(icon, color: teal),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              title.isEmpty ? "-" : title,
                                              style: const TextStyle(fontWeight: FontWeight.w900),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _timeAgoLabel(t, when),
                                            style: TextStyle(
                                              color: Colors.black.withOpacity(0.45),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        body.isEmpty ? "-" : body,
                                        style: TextStyle(
                                          color: Colors.black.withOpacity(0.65),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===== Helpers =====

  Widget _segDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Colors.black.withOpacity(0.10),
    );
  }

  Widget _segBtn({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required Color teal,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? teal : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: active ? Colors.white : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  String _emptyTitle(AppLocalizations t) {
    if (tab == 1) return t.notificationsEmptyOrdersTitle;
    if (tab == 2) return t.notificationsEmptyAdsTitle;
    return t.notificationsEmptyAllTitle;
  }

  String _emptySubtitle(AppLocalizations t) {
    if (tab == 1) return t.notificationsEmptyOrdersSubtitle;
    if (tab == 2) return t.notificationsEmptyAdsSubtitle;
    return t.notificationsEmptyAllSubtitle;
  }

  String _timeAgoLabel(AppLocalizations t, DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 60) return t.notificationsTimeJustNow;
    if (diff.inMinutes < 60) return t.notificationsTimeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return t.notificationsTimeHoursAgo(diff.inHours);
    return t.notificationsTimeDaysAgo(diff.inDays);
  }

  String _resolveLocalizedText({
    required AppLocalizations t,
    required String keyName,
    required Map<String, dynamic> args,
    required String fallback,
  }) {
    final cafeName = (args['cafeName'] ?? '').toString();
    final orderNumber = (args['orderNumber'] ?? '').toString();
    final etaMinutes = int.tryParse((args['etaMinutes'] ?? '').toString()) ?? 0;

    switch (keyName) {
    // ---- Orders ----
      case 'notificationOrderPreparingTitle':
        return t.notificationOrderPreparingTitle;
      case 'notificationOrderPreparingBody':
        return t.notificationOrderPreparingBody(cafeName, orderNumber, etaMinutes);

      case 'notificationOrderReadyTitle':
        return t.notificationOrderReadyTitle;
      case 'notificationOrderReadyBody':
        return t.notificationOrderReadyBody(cafeName, orderNumber);

      case 'notificationOrderCompletedTitle':
        return t.notificationOrderCompletedTitle;
      case 'notificationOrderCompletedBody':
        return t.notificationOrderCompletedBody(cafeName, orderNumber);

      case 'notificationOrderCancelledTitle':
        return t.notificationOrderCancelledTitle;
      case 'notificationOrderCancelledBody':
        return t.notificationOrderCancelledBody(cafeName, orderNumber);

    // ---- Ads ----
      case 'notificationAdTitle':
        return t.notificationAdTitle;
      case 'notificationAdBody':
        final text = (args['text'] ?? '').toString();
        return t.notificationAdBody(text);

      default:
        return fallback;
    }
  }
}