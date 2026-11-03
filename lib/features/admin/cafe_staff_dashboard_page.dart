import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

// ✅ غيّري المسارات حسب مشروعك
import 'package:campresso/features/admin/profile/cafe_staff_profile_page.dart';
import 'package:campresso/features/admin/cafe_staff_order_details_page.dart';
import 'package:campresso/features/admin/cafe_staff_menu_page.dart';
import 'qr_code_page.dart';
import 'cafe_staff_ads_page.dart';

class CafeStaffDashboardPage extends StatefulWidget {
  final String cafeId; // ✅ e.g. "dunkin"
  final String cafeName;
  final String cafeLogoAsset;

  const CafeStaffDashboardPage({
    super.key,
    required this.cafeId,
    required this.cafeName,
    required this.cafeLogoAsset,
  });

  @override
  State<CafeStaffDashboardPage> createState() => _CafeStaffDashboardPageState();
}

class _CafeStaffDashboardPageState extends State<CafeStaffDashboardPage> {
  // ✅ Root messenger key (fix SnackBar with IndexedStack / nested scaffolds)
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
  GlobalKey<ScaffoldMessengerState>();

  void _snack(String text) {
    _messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ✅ Bottom bar index
  int _index = 0; // 0 Dashboard, 1 Menu, 2 Ads, 3 Profile

  // ✅ داخل الداشبورد نفسه: تبويب Current/History
  int _tab = 0; // 0 = current orders, 1 = history
  bool _busy = false;

  static const _teal = Color(0xFF0E6F73);

  // =========================
  // Firestore Query
  // =========================
  Query<Map<String, dynamic>> _baseOrdersQuery() {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('cafeId', isEqualTo: widget.cafeId)
        .where('paymentStatus', isEqualTo: 'paid')
        .orderBy('createdAt', descending: true);
  }

  // =========================
  // Status helpers
  // =========================
  _OrderStatus _mapStatus(String? s) {
    final v = (s ?? '').toLowerCase().trim();
    switch (v) {
      case 'placed':
        return _OrderStatus.newOrder;
      case 'preparing':
        return _OrderStatus.preparing;
      case 'ready':
        return _OrderStatus.ready;
      case 'completed':
        return _OrderStatus.completed;
      case 'cancelled':
        return _OrderStatus.cancelled;
      default:
        return _OrderStatus.newOrder;
    }
  }

  String _toFirestoreStatus(_OrderStatus s) {
    switch (s) {
      case _OrderStatus.newOrder:
        return 'placed';
      case _OrderStatus.preparing:
        return 'preparing';
      case _OrderStatus.ready:
        return 'ready';
      case _OrderStatus.completed:
        return 'completed';
      case _OrderStatus.cancelled:
        return 'cancelled';
    }
  }

  bool _canCancelOrder(_CafeOrderVM o) {
    return o.status == _OrderStatus.newOrder;
  }

  // =========================
  // ✅ Notifications writer (IN-APP)
  // =========================
  // Future<void> _writeUserNotification({
  //   required String customerId,
  //   required String type, // "order" | "ad"
  //   required String title,
  //   required String body,
  //   String? orderId,
  //   int? orderNumber,
  // }) async {
  //   final notifRef = FirebaseFirestore.instance
  //       .collection('users')
  //       .doc(customerId)
  //       .collection('notifications')
  //       .doc();
  //
  //   final payload = <String, dynamic>{
  //     'type': type,
  //     'title': title,
  //     'body': body,
  //     'read': false,
  //     'createdAt': FieldValue.serverTimestamp(),
  //     'cafeId': widget.cafeId,
  //     'cafeName': widget.cafeName,
  //     if (orderId != null) 'orderId': orderId,
  //     if (orderNumber != null) 'orderNumber': orderNumber,
  //   };
  //
  //   await notifRef.set(payload);
  // }

  // ✅ build order notification content from status
  // Future<void> _notifyCustomerOrderStatus({
  //   required String customerId,
  //   required String orderDocId,
  //   required int orderNumber,
  //   required _OrderStatus newStatus,
  // }) async {
  //   final t = AppLocalizations.of(context)!;
  //
  //   // Titles/Bodies كلها localization
  //   final title = switch (newStatus) {
  //     _OrderStatus.preparing => t.notifOrderPreparingTitle(orderNumber.toString()),
  //     _OrderStatus.ready => t.notifOrderReadyTitle(orderNumber.toString()),
  //     _OrderStatus.completed => t.notifOrderCompletedTitle(orderNumber.toString()),
  //     _OrderStatus.cancelled => t.notifOrderCancelledTitle(orderNumber.toString()),
  //     _OrderStatus.newOrder => t.notifOrderPlacedTitle(orderNumber.toString()),
  //   };
  //
  //   final body = switch (newStatus) {
  //     _OrderStatus.preparing => t.notifOrderPreparingBody(widget.cafeName),
  //     _OrderStatus.ready => t.notifOrderReadyBody(widget.cafeName),
  //     _OrderStatus.completed => t.notifOrderCompletedBody(widget.cafeName),
  //     _OrderStatus.cancelled => t.notifOrderCancelledBody(widget.cafeName),
  //     _OrderStatus.newOrder => t.notifOrderPlacedBody(widget.cafeName),
  //   };
  //
  //   await _writeUserNotification(
  //     customerId: customerId,
  //     type: 'order',
  //     title: title,
  //     body: body,
  //     orderId: orderDocId,
  //     orderNumber: orderNumber,
  //   );
  // }

  // =========================
  // Update order status + notify customer
  // =========================
  Future<void> _updateOrderStatus({
    required String orderDocId,
    required int orderNumber,
    required String customerId,
    required _OrderStatus newStatus,
  }) async {
    if (_busy) return;
    final t = AppLocalizations.of(context)!;

    setState(() => _busy = true);
    try {
      final ref = FirebaseFirestore.instance.collection('orders').doc(orderDocId);

      final updates = <String, dynamic>{
        'status': _toFirestoreStatus(newStatus),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == _OrderStatus.preparing) {
        updates['preparingStartedAt'] = FieldValue.serverTimestamp();
      } else if (newStatus == _OrderStatus.ready) {
        updates['readyAt'] = FieldValue.serverTimestamp();
      } else if (newStatus == _OrderStatus.completed) {
        updates['completedAt'] = FieldValue.serverTimestamp();
      } else if (newStatus == _OrderStatus.cancelled) {
        updates['cancelledAt'] = FieldValue.serverTimestamp();
      }

      //  update order
      await ref.set(updates, SetOptions(merge: true));

      // ✅ write notification for customer (in-app)
      //if (customerId.trim().isNotEmpty) {
      //   await _notifyCustomerOrderStatus(
      //     customerId: customerId.trim(),
      //     orderDocId: orderDocId,
      //     orderNumber: orderNumber,
      //     newStatus: newStatus,
      //   );
      // }

      if (!mounted) return;

      final msg = switch (newStatus) {
        _OrderStatus.preparing => t.staffStatusChangedPreparing,
        _OrderStatus.ready => t.staffStatusChangedReady,
        _OrderStatus.completed => t.staffStatusChangedCompleted,
        _OrderStatus.cancelled => t.staffStatusChangedCancelled,
        _OrderStatus.newOrder => t.staffStatusNew,
      };

      _snack(msg);
    } catch (e) {
      if (!mounted) return;
      _snack("${t.error}: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel(_CafeOrderVM o) async {
    final t = AppLocalizations.of(context)!;

    if (!_canCancelOrder(o)) {
      _snack("You can no longer cancel this order after preparation has started.");
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.staffCancelDialogTitle),
        content: Text(t.staffCancelDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              t.staffCancelConfirm,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _updateOrderStatus(
      orderDocId: o.docId,
      orderNumber: o.orderNumber,
      customerId: o.customerId,
      newStatus: _OrderStatus.cancelled,
    );
  }

  // =========================
  // Parsing helpers
  // =========================
  String _safeString(Map<String, dynamic> data, String key,
      {String fallback = ''}) {
    final v = data[key];
    if (v == null) return fallback;
    return v.toString();
  }

  int _safeInt(Map<String, dynamic> data, String key, {int fallback = 0}) {
    final v = data[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  double _safeDouble(Map<String, dynamic> data, String key,
      {double fallback = 0.0}) {
    final v = data[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return fallback;
  }

  String _itemsSummary(Map<String, dynamic> data) {
    final items = data['items'];
    if (items is! List || items.isEmpty) return '';
    final lines = <String>[];

    for (final it in items.take(2)) {
      if (it is Map) {
        final name = (it['name'] ?? it['title'] ?? '').toString();
        final size = (it['size'] ?? '').toString();
        if (name.isEmpty) continue;
        lines.add(size.isNotEmpty ? "$name • $size" : name);
      }
    }
    return lines.isEmpty ? '' : lines.join('\n');
  }

  // =========================
  // UI: Shell
  // =========================
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final pages = <Widget>[
      // Dashboard
      SafeArea(child: _buildDashboardBody()),
      SafeArea(
        child: CafeStaffMenuPage(
          cafeId: widget.cafeId,
        ),
      ),
      // Ads placeholder
      SafeArea(
        child: CafeStaffAdsPage(cafeId: widget.cafeId),
      ),
      // Profile
      SafeArea(
        child: CafeStaffProfilePage(
          cafeId: widget.cafeId,
          cafeName: widget.cafeName,
          cafeLogoAsset: widget.cafeLogoAsset,
          asTab: true,
        ),
      ),
    ];

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: IndexedStack(
          index: _index,
          children: pages,
        ),
        bottomNavigationBar: _staffBottomNav(t),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF8B5B3D),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StaffScanQrPage(),
              ),
            );
          },
          child: const Icon(
            Icons.qr_code_scanner,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // =========================
  // Dashboard body (طلبات + تبويب Current/History)
  // =========================
  Widget _buildDashboardBody() {
    final t = AppLocalizations.of(context)!;

    return Column(
      children: [
        const SizedBox(height: 14),
        Center(
          child: Image.asset(
            widget.cafeLogoAsset,
            width: 60,
            height: 60,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.cafeName,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _segmented(
            left: t.staffCurrentOrdersTab,
            right: t.staffOrderHistoryTab,
            activeIndex: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _baseOrdersQuery().snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text("${t.error}: ${snap.error}"));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;

              final all = docs.map((d) {
                final data = d.data();

                final orderNumber = _safeInt(data, 'orderNumber', fallback: 0);
                final customerName =
                _safeString(data, 'customerName', fallback: '');

                final customerId = _safeString(
                  data,
                  'customerId',
                  fallback: _safeString(data, 'userId', fallback: ''),
                );

                final etaMinutes =
                _safeInt(data, 'estimatedMinutes', fallback: 0);

                final grandTotal =
                _safeDouble(data, 'grandTotal', fallback: 0.0);
                final paidAmount =
                _safeDouble(data, 'paidAmount', fallback: 0.0);
                final price = grandTotal > 0 ? grandTotal : paidAmount;

                final status = _mapStatus(_safeString(data, 'status'));
                final summary = _itemsSummary(data);

                return _CafeOrderVM(
                  docId: d.id,
                  orderNumber: orderNumber,
                  customerId: customerId,
                  customerName: customerName,
                  itemsSummary: summary,
                  priceSar: price,
                  etaMinutes: etaMinutes,
                  status: status,
                );
              }).toList();

              final currentOrders =
              all.where((o) => o.status.isCurrent).toList();
              final historyOrders =
              all.where((o) => o.status.isHistory).toList();

              final ordersToShow = _tab == 0 ? currentOrders : historyOrders;

              final newCount = currentOrders
                  .where((o) => o.status == _OrderStatus.newOrder)
                  .length;
              final preparingCount = currentOrders
                  .where((o) => o.status == _OrderStatus.preparing)
                  .length;
              final readyCount = currentOrders
                  .where((o) => o.status == _OrderStatus.ready)
                  .length;

              final completedCount = historyOrders
                  .where((o) => o.status == _OrderStatus.completed)
                  .length;
              final cancelledCount = historyOrders
                  .where((o) => o.status == _OrderStatus.cancelled)
                  .length;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _tab == 0
                        ? Row(
                      children: [
                        Expanded(
                          child: _countCard(
                            count: newCount,
                            label: t.staffNewOrders,
                            borderColor: const Color(0xFFFF6B6B),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _countCard(
                            count: preparingCount,
                            label: t.staffPreparing,
                            borderColor: const Color(0xFFFFC107),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _countCard(
                            count: readyCount,
                            label: t.staffReadyForPickup,
                            borderColor: const Color(0xFF2ECC71),
                          ),
                        ),
                      ],
                    )
                        : Row(
                      children: [
                        Expanded(
                          child: _countCard(
                            count: completedCount,
                            label: t.staffCompletedOrders,
                            borderColor: const Color(0xFF2ECC71),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _countCard(
                            count: cancelledCount,
                            label: t.staffCancelledOrders,
                            borderColor: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _tab == 0
                            ? t.staffCurrentOrdersTitle
                            : t.staffPreviousOrdersTitle,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.75),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ordersToShow.isEmpty
                        ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _tab == 0
                              ? t.staffNoCurrentOrders
                              : t.staffNoHistoryOrders,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.55),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                        : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      itemCount: ordersToShow.length,
                      itemBuilder: (context, i) {
                        final o = ordersToShow[i];
                        final chip = _statusChip(t, o.status);
                        final idText =
                        o.orderNumber > 0 ? "#${o.orderNumber}" : "#";

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CafeStaffOrderDetailsPage(
                                        orderDocId: o.docId,
                                        cafeId: widget.cafeId,
                                      ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _teal.withOpacity(0.55),
                                  width: 1.2,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          idText,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                      chip,
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    o.customerName,
                                    style: TextStyle(
                                      color:
                                      Colors.black.withOpacity(0.55),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    o.itemsSummary.isNotEmpty
                                        ? o.itemsSummary
                                        : t.staffOrderItemsFallback,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Text(
                                        t.staffSarAmount(
                                            o.priceSar.toStringAsFixed(2)),
                                        style: const TextStyle(
                                          color: _teal,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (o.status.isCurrent)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _primaryActionButton(
                                            _teal,
                                            t,
                                            o,
                                            onStartPreparing: () =>
                                                _updateOrderStatus(
                                                  orderDocId: o.docId,
                                                  orderNumber: o.orderNumber,
                                                  customerId: o.customerId,
                                                  newStatus:
                                                  _OrderStatus.preparing,
                                                ),
                                            onMarkReady: () =>
                                                _updateOrderStatus(
                                                  orderDocId: o.docId,
                                                  orderNumber: o.orderNumber,
                                                  customerId: o.customerId,
                                                  newStatus:
                                                  _OrderStatus.ready,
                                                ),
                                            onComplete: () async {
                                              final ok =
                                              await Navigator.push<
                                                  bool>(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      StaffScanQrPage(
                                                        expectedOrderDocId:
                                                        o.docId,
                                                        expectedOrderNumber:
                                                        o.orderNumber,
                                                      ),
                                                ),
                                              );

                                              // ✅ بعد نجاح الـ QR scan: نحدّث + نرسل إشعار
                                              if (ok == true && mounted) {
                                                await _updateOrderStatus(
                                                  orderDocId: o.docId,
                                                  orderNumber:
                                                  o.orderNumber,
                                                  customerId:
                                                  o.customerId,
                                                  newStatus:
                                                  _OrderStatus
                                                      .completed,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                        if (_canCancelOrder(o)) ...[
                                          const SizedBox(width: 12),
                                          _outlinedDangerButton(
                                            t,
                                            onTap: () => _confirmCancel(o),
                                          ),
                                        ],
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------- UI components ----------------

  Widget _segmented({
    required String left,
    required String right,
    required int activeIndex,
    required ValueChanged<int> onChanged,
  }) {
    Widget seg(String text, int idx) {
      final active = activeIndex == idx;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(idx),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _teal : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: active
                    ? Colors.white
                    : Colors.black.withOpacity(0.6),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [seg(left, 0), seg(right, 1)]),
    );
  }

  Widget _countCard({
    required int count,
    required String label,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.4),
      ),
      child: Column(
        children: [
          Text("$count",
              style:
              const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black.withOpacity(0.7),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(AppLocalizations t, _OrderStatus s) {
    final info = s.chipInfo(t);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: info.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        info.text,
        style: TextStyle(
          color: info.fg,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _primaryActionButton(
      Color teal,
      AppLocalizations t,
      _CafeOrderVM o, {
        required VoidCallback onStartPreparing,
        required VoidCallback onMarkReady,
        required VoidCallback onComplete,
      }) {
    String label;
    VoidCallback onTap;

    switch (o.status) {
      case _OrderStatus.newOrder:
        label = t.staffStartPreparing;
        onTap = onStartPreparing;
        break;
      case _OrderStatus.preparing:
        label = t.staffMarkAsReady;
        onTap = onMarkReady;
        break;
      case _OrderStatus.ready:
        label = t.staffCompleteOrder;
        onTap = onComplete;
        break;
      default:
        label = t.staffAction;
        onTap = () {};
    }

    return SizedBox(
      height: 46,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: teal,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _busy ? null : onTap,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _outlinedDangerButton(AppLocalizations t,
      {required VoidCallback onTap}) {
    return SizedBox(
      height: 46,
      width: 120,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFFF6B6B), width: 1.2),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _busy ? null : onTap,
        child: Text(
          t.staffCancel,
          style: const TextStyle(
            color: Color(0xFFFF6B6B),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ✅ Bottom bar مربوط (يغير _index) + FIX overflow
  Widget _staffBottomNav(AppLocalizations t) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 10,
      child: SizedBox(
        height: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(
              icon: Icons.dashboard_outlined,
              label: t.staffNavDashboard,
              active: _index == 0,
              onTap: () => setState(() => _index = 0),
            ),
            _navItem(
              icon: Icons.menu_book_outlined,
              label: t.staffNavMenu,
              active: _index == 1,
              onTap: () => setState(() => _index = 1),
            ),
            const SizedBox(width: 46),
            _navItem(
              icon: Icons.local_offer_outlined,
              label: t.staffNavAds,
              active: _index == 2,
              onTap: () => setState(() => _index = 2),
            ),
            _navItem(
              icon: Icons.person_outline,
              label: t.staffNavProfile,
              active: _index == 3,
              onTap: () => setState(() => _index = 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final c = active ? _teal : Colors.black.withOpacity(0.45);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================
// View model
// =========================
class _CafeOrderVM {
  final String docId;
  final int orderNumber;
  final String customerId; // ✅ NEW
  final String customerName;
  final String itemsSummary;
  final double priceSar;
  final int etaMinutes;
  final _OrderStatus status;

  _CafeOrderVM({
    required this.docId,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.itemsSummary,
    required this.priceSar,
    required this.etaMinutes,
    required this.status,
  });
}

enum _OrderStatus { newOrder, preparing, ready, completed, cancelled }

extension on _OrderStatus {
  bool get isCurrent =>
      this == _OrderStatus.newOrder ||
          this == _OrderStatus.preparing ||
          this == _OrderStatus.ready;

  bool get isHistory =>
      this == _OrderStatus.completed || this == _OrderStatus.cancelled;

  _ChipInfo chipInfo(AppLocalizations t) {
    switch (this) {
      case _OrderStatus.newOrder:
        return _ChipInfo(
          text: t.staffStatusNew,
          bg: const Color(0xFFFFE3E3),
          fg: const Color(0xFFD32F2F),
        );
      case _OrderStatus.preparing:
        return _ChipInfo(
          text: t.staffStatusPreparing,
          bg: const Color(0xFFFFF3CD),
          fg: const Color(0xFF8A6D00),
        );
      case _OrderStatus.ready:
        return _ChipInfo(
          text: t.staffStatusReady,
          bg: const Color(0xFFDFF5E7),
          fg: const Color(0xFF1E7E34),
        );
      case _OrderStatus.completed:
        return _ChipInfo(
          text: t.staffStatusCompleted,
          bg: const Color(0xFFE6F4EA),
          fg: const Color(0xFF2E7D32),
        );
      case _OrderStatus.cancelled:
        return _ChipInfo(
          text: t.staffStatusCancelled,
          bg: const Color(0xFFEDEDED),
          fg: const Color(0xFF616161),
        );
    }
  }
}

class _ChipInfo {
  final String text;
  final Color bg;
  final Color fg;
  _ChipInfo({required this.text, required this.bg, required this.fg});
}

class _StaffAdsPlaceholder extends StatelessWidget {
  const _StaffAdsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(child: Text(t.staffAdsComingSoon));
  }
}