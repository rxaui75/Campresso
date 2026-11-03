// orders_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'order_service.dart';
import 'order_tracking_page.dart';
import 'order_details_page.dart';
import 'user_home_page.dart';
import 'package:campresso/features/user/delivery/delivery_controller.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  int tab = 0; // 0 left tab, 1 right tab

  static const Duration _previousOrdersRetention = Duration(days: 7);

  // ✅ cache: uid -> resolved name
  final Map<String, String> _nameCache = {};

  String _logoForCafe(String name) {
    switch (name.toLowerCase()) {
      case 'dunkin':
        return 'assets/images/cafes/dunkin.png';
      case 'selu':
        return 'assets/images/cafes/selu.png';
      default:
        return 'assets/images/cafes/window.jpeg';
    }
  }

  /// ✅ stream يتغير حسب deliveryOn + tab
  Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream(bool deliveryOn) {
    if (deliveryOn) {
      // Left = Deliveries, Right = My Orders
      if (tab == 0) {
        // ✅ Deliveries: waiting + accepted
        return FirebaseFirestore.instance
            .collection('orders')
            .where('fulfillment', isEqualTo: 'delivery')
            .where('deliveryStatus', whereIn: ['waiting', 'accepted'])
            .orderBy('createdAt', descending: true)
            .snapshots();
      } else {
        // ✅ My Orders in delivery mode:
        // fetch broadly, then filter locally
        return FirebaseFirestore.instance
            .collection('orders')
            .orderBy('createdAt', descending: true)
            .snapshots();
      }
    } else {
      // ✅ Normal customer orders:
      // fetch broadly, then filter locally into current / previous
      return OrderService.instance.myOrdersStream(current: true);
    }
  }

  String _emptyText(AppLocalizations t, bool deliveryOn) {
    if (deliveryOn) {
      return tab == 0 ? t.noCurrentOrders : t.noCurrentOrders;
    }
    return tab == 0 ? t.noCurrentOrders : t.noPreviousOrders;
  }

  bool _isCurrentCard(bool deliveryOn) {
    if (deliveryOn) {
      // في وضع delivery: My Orders (tab=1) نعتبرها current لتفتح tracking
      return tab == 1;
    }
    return tab == 0; // الطبيعي
  }

  // ============================================================
  // ✅ Customer / ownership helpers
  // ============================================================
  String _resolveCustomerUid(Map<String, dynamic> orderData) {
    final v = (orderData['customerId'] ??
        orderData['customerUid'] ??
        orderData['userId'] ??
        orderData['uid'] ??
        '')
        .toString()
        .trim();
    return v;
  }

  bool _isMyOrder(Map<String, dynamic> data, String? myUid) {
    if (myUid == null || myUid.isEmpty) return false;
    return _resolveCustomerUid(data) == myUid;
  }

  bool _isDeliveryOrder(Map<String, dynamic> data) {
    final fulfillment =
    (data['fulfillment'] ?? 'pickup').toString().toLowerCase().trim();
    return fulfillment == 'delivery';
  }

  bool _isCurrentMyOrder(Map<String, dynamic> data, String? myUid) {
    if (!_isMyOrder(data, myUid)) return false;

    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    final deliveryStatus =
    (data['deliveryStatus'] ?? '').toString().toLowerCase().trim();

    if (_isDeliveryOrder(data)) {
      // ✅ completed or cancelled should NOT stay in current
      if (status == 'completed' || status == 'cancelled') return false;
      if (deliveryStatus == 'completed') return false;
      return true;
    }

    // ✅ pickup logic
    return status != 'completed' && status != 'cancelled';
  }

  bool _isPreviousMyOrder(Map<String, dynamic> data, String? myUid) {
    if (!_isMyOrder(data, myUid)) return false;

    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    final deliveryStatus =
    (data['deliveryStatus'] ?? '').toString().toLowerCase().trim();

    if (_isDeliveryOrder(data)) {
      return status == 'completed' ||
          status == 'cancelled' ||
          deliveryStatus == 'completed';
    }

    return status == 'completed' || status == 'cancelled';
  }

  DateTime? _readTimestampAsDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  DateTime? _previousOrderAnchorDate(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    final deliveryStatus =
    (data['deliveryStatus'] ?? '').toString().toLowerCase().trim();

    // ✅ Prefer the actual finish/cancel time first
    if (status == 'completed' || deliveryStatus == 'completed') {
      return _readTimestampAsDate(data['completedAt']) ??
          _readTimestampAsDate(data['receivedAt']) ??
          _readTimestampAsDate(data['updatedAt']) ??
          _readTimestampAsDate(data['createdAt']);
    }

    if (status == 'cancelled') {
      return _readTimestampAsDate(data['cancelledAt']) ??
          _readTimestampAsDate(data['updatedAt']) ??
          _readTimestampAsDate(data['createdAt']);
    }

    return _readTimestampAsDate(data['updatedAt']) ??
        _readTimestampAsDate(data['createdAt']);
  }

  bool _isWithinPreviousRetention(Map<String, dynamic> data) {
    final anchor = _previousOrderAnchorDate(data);
    if (anchor == null) return true; // if missing timestamps, keep visible
    return DateTime.now().difference(anchor) <= _previousOrdersRetention;
  }

  Widget _customerNameText({
    required AppLocalizations t,
    required Map<String, dynamic> orderData,
    TextStyle? style,
  }) {
    final st = style ?? const TextStyle(fontWeight: FontWeight.w800);

    final directName = (orderData['customerName'] ?? '').toString().trim();
    if (directName.isNotEmpty) return Text(directName, style: st);

    final customerUid = _resolveCustomerUid(orderData);
    if (customerUid.isEmpty) return Text(t.customer, style: st);

    final cached = _nameCache[customerUid];
    if (cached != null && cached.isNotEmpty) {
      return Text(cached, style: st);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(customerUid).get(),
      builder: (context, snap) {
        if (!snap.hasData) return Text(t.customer, style: st);

        final u = snap.data!.data();
        if (u == null) return Text(t.customer, style: st);

        final fullName = (u['fullName'] ?? '').toString().trim();
        final first = (u['firstName'] ?? '').toString().trim();
        final last = (u['lastName'] ?? '').toString().trim();
        final email = (u['email'] ?? '').toString().trim();

        String name = fullName;
        if (name.isEmpty) {
          final combined = [first, last].where((x) => x.isNotEmpty).join(' ');
          name = combined.isNotEmpty ? combined : email;
        }

        final finalName = name.isEmpty ? t.customer : name;
        _nameCache[customerUid] = finalName;

        return Text(finalName, style: st);
      },
    );
  }

  // ============================================================
  // ✅ Delivery location resolver
  // ============================================================
  String _deliveryLocationText(Map<String, dynamic> data, AppLocalizations t) {
    final textCandidates = [
      data['deliveryLocationText'],
      data['deliveryAddress'],
      data['customerAddress'],
      data['selectedDeliveryLocationText'],
      data['deliveryLocationName'],
      data['locationText'],
      data['address'],
    ];

    for (final c in textCandidates) {
      final text = (c ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }

    GeoPoint? point;

    final gpCandidates = [
      data['deliveryLocation'],
      data['customerLocation'],
      data['location'],
      data['deliveryGeoPoint'],
      data['customerGeoPoint'],
    ];

    for (final c in gpCandidates) {
      if (c is GeoPoint) {
        point = c;
        break;
      }
    }

    point ??= _geoPointFromMap(data['deliveryLocation']);
    point ??= _geoPointFromMap(data['customerLocation']);
    point ??= _geoPointFromMap(data['location']);

    point ??= _geoPointFromLatLngFields(data);

    if (point != null) {
      return "${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}";
    }

    return t.deliveryLocationNotSet;
  }

  GeoPoint? _geoPointFromMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      final lat = _toDouble(value['lat'] ?? value['latitude']);
      final lng = _toDouble(value['lng'] ?? value['longitude'] ?? value['lon']);
      if (lat != null && lng != null) return GeoPoint(lat, lng);
    }

    if (value is Map) {
      final lat = _toDouble(value['lat'] ?? value['latitude']);
      final lng = _toDouble(value['lng'] ?? value['longitude'] ?? value['lon']);
      if (lat != null && lng != null) return GeoPoint(lat, lng);
    }

    return null;
  }

  GeoPoint? _geoPointFromLatLngFields(Map<String, dynamic> data) {
    final lat = _toDouble(
      data['deliveryLat'] ?? data['customerLat'] ?? data['lat'] ?? data['latitude'],
    );
    final lng = _toDouble(
      data['deliveryLng'] ??
          data['deliveryLon'] ??
          data['customerLng'] ??
          data['lng'] ??
          data['longitude'] ??
          data['lon'],
    );

    if (lat != null && lng != null) {
      return GeoPoint(lat, lng);
    }

    return null;
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const teal = Color(0xFF0E6F73);

    return AnimatedBuilder(
      animation: DeliveryController.instance,
      builder: (_, __) {
        final deliveryOn = DeliveryController.instance.available;
        final myUid = FirebaseAuth.instance.currentUser?.uid;

        if (tab < 0 || tab > 1) tab = 0;

        final leftLabel = deliveryOn ? t.deliveries : t.current;
        final rightLabel = deliveryOn ? t.myOrders : t.previous;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.6,
            centerTitle: true,
            title: Text(
              t.orders,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w800,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UserHomePage(initialIndex: 0),
                  ),
                      (route) => false,
                );
              },
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              _segmented(
                left: leftLabel,
                right: rightLabel,
                activeLeft: tab == 0,
                onLeft: () => setState(() => tab = 0),
                onRight: () => setState(() => tab = 1),
              ),
              const SizedBox(height: 14),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _ordersStream(deliveryOn),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 50),
                      child: Center(
                        child: Text(
                          "Error: ${snap.error}",
                          style: TextStyle(color: Colors.black.withOpacity(0.6)),
                        ),
                      ),
                    );
                  }

                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final docsRaw = snap.data!.docs;
                  final isDeliveriesTab = deliveryOn && tab == 0;
                  final isMyOrdersTabInDeliveryMode = deliveryOn && tab == 1;
                  final isCurrentTabNormal = !deliveryOn && tab == 0;
                  final isPreviousTabNormal = !deliveryOn && tab == 1;

                  final docs = isDeliveriesTab
                      ? docsRaw.where((d) {
                    final data = d.data();

                    final customerId = _resolveCustomerUid(data);
                    if (myUid != null && customerId == myUid) return false;

                    final st = (data['deliveryStatus'] ?? 'waiting')
                        .toString()
                        .toLowerCase()
                        .trim();

                    if (st == 'waiting') return true;

                    if (st == 'accepted') {
                      final pid =
                      (data['deliveryPartnerId'] ?? '').toString().trim();
                      return myUid != null && pid == myUid;
                    }

                    return false;
                  }).toList()
                      : isMyOrdersTabInDeliveryMode || isCurrentTabNormal
                      ? docsRaw
                      .where((d) => _isCurrentMyOrder(d.data(), myUid))
                      .toList()
                      : isPreviousTabNormal
                      ? docsRaw
                      .where((d) =>
                  _isPreviousMyOrder(d.data(), myUid) &&
                      _isWithinPreviousRetention(d.data()))
                      .toList()
                      : docsRaw;

                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 50),
                      child: Center(
                        child: Text(
                          _emptyText(t, deliveryOn),
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.55),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }

                  final isCurrent = _isCurrentCard(deliveryOn);

                  return Column(
                    children: [
                      for (final d in docs) ...[
                        isDeliveriesTab
                            ? _deliveryCardSmart(
                          context: context,
                          doc: d,
                          teal: teal,
                          t: t,
                          myUid: myUid,
                        )
                            : _orderCard(
                          context: context,
                          doc: d,
                          teal: teal,
                          isCurrent: isCurrent,
                          t: t,
                          deliveryOn: deliveryOn,
                        ),
                        const SizedBox(height: 12),
                      ]
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // MY ORDERS (Customer view)
  // ============================================================
  Widget _orderCard({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Color teal,
    required bool isCurrent,
    required AppLocalizations t,
    required bool deliveryOn,
  }) {
    final data = doc.data();

    final orderId = doc.id;
    final orderNumber = (data["orderNumber"] ?? 0) is int
        ? (data["orderNumber"] as int)
        : int.tryParse("${data["orderNumber"]}") ?? 0;
    final cafeName = (data["cafeName"] ?? "Cafe").toString();
    final status = (data["status"] ?? "placed").toString();

    final fulfillment =
    (data["fulfillment"] ?? "pickup").toString().toLowerCase().trim();
    final deliveryStatus =
    (data["deliveryStatus"] ?? "").toString().toLowerCase().trim();
    final deliveryProgress =
    (data["deliveryProgress"] ?? "").toString().toLowerCase().trim();

    final isDeliveryWaiting =
        fulfillment == "delivery" && deliveryStatus == "waiting";
    final isDeliveryOnTheWay = fulfillment == "delivery" &&
        deliveryStatus == "accepted" &&
        (deliveryProgress == "on_the_way" || deliveryProgress == "ontheway");

    final isDeliveryActive = fulfillment == "delivery" &&
        deliveryStatus == "accepted" &&
        status != "completed" &&
        status != "cancelled";

    final statusText = isDeliveryWaiting
        ? t.pending
        : isDeliveryOnTheWay
        ? t.deliveryStepOnTheWay
        : isDeliveryActive
        ? t.accepted
        : _statusLabel(status, t);

    final statusColor = isDeliveryWaiting
        ? const Color(0xFF7A4E2B)
        : isDeliveryOnTheWay
        ? const Color(0xFF0E6F73)
        : isDeliveryActive
        ? const Color(0xFF0E6F73)
        : _statusColor(status);

    final createdTs = data["createdAt"];
    final createdAt = (createdTs is Timestamp) ? createdTs.toDate() : null;

    String timeLabel = t.inProgress;
    if (createdAt != null) timeLabel = _timeLabel(createdAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              _logoForCafe(cafeName),
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                color: Colors.black.withOpacity(0.05),
                child: const Icon(Icons.local_cafe),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      orderNumber == 0 ? "#----" : "#$orderNumber",
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.45),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(cafeName, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      timeLabel,
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.55),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: teal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                if (isCurrent || isDeliveryWaiting || isDeliveryActive) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderTrackingPage(
                        orderId: orderId,
                        orderNumber: orderNumber,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderDetailsPage(orderId: orderId),
                    ),
                  );
                }
              },
              child: Text(
                t.view,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DELIVERIES TAB (Delivery girl view)
  // ============================================================
  Widget _deliveryCardSmart({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Color teal,
    required AppLocalizations t,
    required String? myUid,
  }) {
    final data = doc.data();
    final st =
    (data["deliveryStatus"] ?? "waiting").toString().toLowerCase().trim();

    if (st == 'accepted') {
      return _deliveryAcceptedCard(
        context: context,
        doc: doc,
        teal: teal,
        t: t,
      );
    }

    return _deliveryRequestCard(
      context: context,
      doc: doc,
      teal: teal,
      t: t,
      myUid: myUid,
    );
  }

  Widget _deliveryAcceptedCard({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Color teal,
    required AppLocalizations t,
  }) {
    final data = doc.data();

    final orderId = doc.id;
    final orderNumber = (data["orderNumber"] ?? 0) is int
        ? (data["orderNumber"] as int)
        : int.tryParse("${data["orderNumber"]}") ?? 0;
    final cafeName = (data["cafeName"] ?? "Cafe").toString();
    final locationText = _deliveryLocationText(data, t);

    final createdTs = data["createdAt"];
    final createdAt = (createdTs is Timestamp) ? createdTs.toDate() : null;
    final timeLabel = createdAt == null ? t.inProgress : _timeLabel(createdAt);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailsPage(
              orderId: orderId,
              asDeliveryPartner: true,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: teal.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: teal.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${t.deliveryRequest} • ${orderNumber == 0 ? "#----" : "#$orderNumber"}",
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  timeLabel,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: teal.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: teal.withOpacity(0.35)),
              ),
              child: Text(
                t.accepted,
                style: TextStyle(color: teal, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: _customerNameText(
                    t: t,
                    orderData: data,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(cafeName, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    locationText,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.7),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.tapToViewDetails,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Future<String?> _showDeliveryTravelModeDialog(BuildContext context) async {
    const teal = Color(0xFF0E6F73);

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            title: const Text(
              'Choose delivery route',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select how you will pick up and deliver this order. This is required so the customer can see a more accurate delivery time.',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.62),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                _deliveryTravelOption(
                  icon: Icons.directions_walk,
                  title: 'Walking',
                  subtitle: 'Use walking route for delivery timing.',
                  onTap: () => Navigator.pop(dialogContext, 'walking'),
                ),
                const SizedBox(height: 10),
                _deliveryTravelOption(
                  icon: Icons.directions_transit,
                  title: 'Metro',
                  subtitle: 'Use campus metro route for delivery timing.',
                  onTap: () => Navigator.pop(dialogContext, 'metro'),
                ),
              ],
            ),
            actions: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: teal.withOpacity(0.22)),
                ),
                child: Text(
                  'You cannot continue without choosing a route.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: teal,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _deliveryTravelOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    const teal = Color(0xFF0E6F73);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.025),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: teal.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: teal),
          ],
        ),
      ),
    );
  }

  Widget _deliveryRequestCard({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Color teal,
    required AppLocalizations t,
    required String? myUid,
  }) {
    final data = doc.data();

    final orderId = doc.id;
    final orderNumber = (data["orderNumber"] ?? 0) is int
        ? (data["orderNumber"] as int)
        : int.tryParse("${data["orderNumber"]}") ?? 0;
    final cafeName = (data["cafeName"] ?? "Cafe").toString();

    final locationText = _deliveryLocationText(data, t);

    final createdTs = data["createdAt"];
    final createdAt = (createdTs is Timestamp) ? createdTs.toDate() : null;
    final timeLabel = createdAt == null ? t.inProgress : _timeLabel(createdAt);

    String _makeDeliveryBarcode(String orderId, String uid) {
      final code = (orderId.hashCode ^ uid.hashCode).abs() % 100000000;
      return code.toString().padLeft(8, '0');
    }

    String _buildNameFromUser(Map<String, dynamic> u) {
      final full = (u['fullName'] ?? '').toString().trim();
      if (full.isNotEmpty) return full;
      final first = (u['firstName'] ?? '').toString().trim();
      final last = (u['lastName'] ?? '').toString().trim();
      final combined = [first, last].where((x) => x.isNotEmpty).join(' ');
      if (combined.isNotEmpty) return combined;
      final email = (u['email'] ?? '').toString().trim();
      return email.isNotEmpty ? email : "Delivery Partner";
    }

    Future<void> accept() async {
      if (myUid == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.error)),
        );
        return;
      }

      final deliveryTravelMode = await _showDeliveryTravelModeDialog(context);
      if (!context.mounted) return;

      // The dialog is not dismissible, but keep this guard for safety.
      if (deliveryTravelMode == null || deliveryTravelMode.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose a delivery route first.')),
        );
        return;
      }

      bool accepted = false;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = FirebaseFirestore.instance.collection('orders').doc(orderId);
        final snap = await tx.get(ref);

        final st = (snap.data()?['deliveryStatus'] ?? 'waiting')
            .toString()
            .toLowerCase()
            .trim();
        if (st != 'waiting') {
          accepted = false;
          return;
        }

        final userRef = FirebaseFirestore.instance.collection('users').doc(myUid);
        final userSnap = await tx.get(userRef);
        final userData = userSnap.data() ?? <String, dynamic>{};

        final deliveryName = _buildNameFromUser(userData);
        final deliveryPhone = (userData['phoneNumber'] ?? '').toString().trim();

        final barcode = _makeDeliveryBarcode(orderId, myUid);

        final orderData = snap.data() ?? <String, dynamic>{};

        final update = <String, dynamic>{
          'deliveryStatus': 'accepted',
          'deliveryPartnerId': myUid,
          'acceptedAt': FieldValue.serverTimestamp(),
          'deliveryAcceptedAt': FieldValue.serverTimestamp(),
          'deliveryPartnerBarcode': barcode,
          'deliveryPartnerName': deliveryName,

          // ✅ Required choice from the delivery girl.
          // Customer tracking can read this later to calculate/display a more accurate ETA.
          'deliveryTravelMode': deliveryTravelMode,
          'deliveryTransportMode': deliveryTravelMode,
          'deliveryPartnerTransportMode': deliveryTravelMode,
          'deliveryEtaStatus': 'pending_calculation',
          'deliveryEtaNeedsCalculation': true,
        };

        if (deliveryPhone.isNotEmpty) {
          update['deliveryPartnerPhone'] = deliveryPhone;
        }

        if ((orderData['paymentStatus'] ?? '').toString().trim().isEmpty) {
          update['paymentStatus'] = 'unpaid';
        }
        if ((orderData['tipStatus'] ?? '').toString().trim().isEmpty) {
          update['tipStatus'] = 'none';
        }

        tx.update(ref, update);
        accepted = true;
      });

      if (!context.mounted) return;

      if (accepted) {
        final label = deliveryTravelMode == 'metro' ? 'Metro' : 'Walking';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.deliveryAccepted} • $label')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.deliveryAlreadyTaken)),
        );
      }
    }

    void notAvailable() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.markedNotAvailable)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "${t.deliveryRequest} • ${orderNumber == 0 ? "#----" : "#$orderNumber"}",
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                timeLabel,
                style: TextStyle(
                  color: Colors.black.withOpacity(0.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: _customerNameText(
                  t: t,
                  orderData: data,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(cafeName, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  locationText,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: notAvailable,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    t.notAvailable,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    t.accept,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // UI + Helpers
  // ============================================================
  Widget _segmented({
    required String left,
    required String right,
    required bool activeLeft,
    required VoidCallback onLeft,
    required VoidCallback onRight,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onLeft,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: activeLeft ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  left,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: activeLeft ? Colors.black87 : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onRight,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !activeLeft ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  right,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: !activeLeft ? Colors.black87 : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String s, AppLocalizations t) {
    switch (s) {
      case "placed":
        return t.orderPlaced;
      case "preparing":
        return t.preparing;
      case "ready":
      case "readyToPickup":
        return t.readyToPickup;
      case "completed":
        return t.completed;
      case "cancelled":
        return t.cancelled;
      default:
        return t.preparing;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case "placed":
        return const Color(0xFF7A4E2B);
      case "preparing":
        return const Color(0xFF0E6F73);
      case "ready":
      case "readyToPickup":
        return const Color(0xFF2E7D32);
      case "completed":
        return const Color(0xFF2E7D32);
      case "cancelled":
        return Colors.red;
      default:
        return const Color(0xFF0E6F73);
    }
  }

  String _timeLabel(DateTime d) {
    String two(int x) => x.toString().padLeft(2, '0');
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? "PM" : "AM";
    return "${two(d.day)}/${two(d.month)}/${d.year}  $h:${two(d.minute)} $ampm";
  }
}