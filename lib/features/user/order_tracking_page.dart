import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'order_details_page.dart';
import 'package:campresso/features/user/delivery/delivery_waiting_page.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum OrderStatus { placed, preparing, readyToPickup }

// ✅ Delivery stepper states (UI only)
enum DeliveryStep { waiting, accepted, preparing, onTheWay, delivered }

class OrderTrackingPage extends StatefulWidget {
  final String orderId;
  final int orderNumber;

  const OrderTrackingPage({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

enum _NoResponseAction { cancel, switchToPickup, waitMore }

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  bool _confirmingReceived = false;
  bool _noResponseDialogOpen = false;

  // ✅ prevent showing completed screen multiple times
  bool _completedScreenShown = false;

  // ✅ show pickup reminder only once per page session
  bool _pickupReminderShown = false;

  DocumentReference<Map<String, dynamic>> _orderDoc() {
    return FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
  }

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw Exception("User not logged in");
    return u.uid;
  }

  bool _isMine(Map<String, dynamic> data) {
    final cid = (data['customerId'] ?? '').toString();
    final uid = (data['userId'] ?? '').toString();
    return cid == _uid || uid == _uid;
  }

  bool _canShowReceivedButton(Map<String, dynamic> data) {
    final fulfillment = (data['fulfillment'] ?? 'pickup').toString().toLowerCase().trim();
    if (fulfillment != 'delivery') return false;

    final deliveryStatus = (data['deliveryStatus'] ?? '').toString().toLowerCase().trim();
    final paymentStatus = (data['paymentStatus'] ?? '').toString().toLowerCase().trim();
    final partnerId = (data['deliveryPartnerId'] ?? '').toString().trim();

    if (!_isMine(data)) return false;
    if (partnerId.isEmpty) return false;

    if (deliveryStatus != 'accepted') return false;
    if (paymentStatus != 'paid') return false;

    // ✅ للدليفري: الاكتمال يعتمد فقط على deliveryStatus
    if (deliveryStatus == 'completed') return false;

    return true;
  }

  String _receivedButtonHintText(Map<String, dynamic> data, AppLocalizations t) {
    final fulfillment = (data['fulfillment'] ?? 'pickup').toString().toLowerCase().trim();
    if (fulfillment != 'delivery') return t.receivedButtonHint;

    final deliveryStatus = (data['deliveryStatus'] ?? '').toString().toLowerCase().trim();
    final paymentStatus = (data['paymentStatus'] ?? '').toString().toLowerCase().trim();
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    final partnerId = (data['deliveryPartnerId'] ?? '').toString().trim();
    final progress = (data['deliveryProgress'] ?? '').toString().toLowerCase().trim();

    // ✅ للدليفري: completed فقط من deliveryStatus
    if (deliveryStatus == 'completed') {
      return t.receivedButtonCompletedHint;
    }

    if (deliveryStatus == 'waiting' || partnerId.isEmpty) {
      return t.receivedButtonWaitingPartnerHint;
    }

    if (paymentStatus != 'paid') {
      return t.receivedButtonWaitingPaymentHint;
    }

    if (progress == 'on_the_way' || progress == 'ontheway') {
      return t.receivedButtonOnTheWayHint;
    }

    if (status == 'preparing') {
      return t.receivedButtonPreparingHint;
    }

    if (status == 'ready' || status == 'readytopickup') {
      return t.receivedButtonOnTheWayHint;
    }

    return t.receivedButtonHint;
  }

  double _readTip(Map<String, dynamic> data) {
    final v = data['deliveryTip'] ?? data['tipAmount'] ?? 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  // =========================
  // ✅ Delivery Stepper Index
  // =========================
  int _deliveryStepIndex(Map<String, dynamic> data) {
    final deliveryStatus = (data['deliveryStatus'] ?? 'waiting').toString().toLowerCase().trim();
    final status = (data['status'] ?? 'placed').toString().toLowerCase().trim();
    final progress = (data['deliveryProgress'] ?? '').toString().toLowerCase().trim();

    // ✅ delivery is completed ONLY when deliveryStatus is completed
    if (deliveryStatus == 'completed') return 4;
    if (deliveryStatus == 'waiting') return 0;

    if (deliveryStatus == 'accepted') {
      if (progress == 'on_the_way' || progress == 'ontheway') return 3;
      if (status == 'ready' || status == 'readytopickup') return 3;
      if (status == 'preparing') return 2;
      return 1;
    }

    return 0;
  }

  // =========================
  // ✅ show completed screen when order completes
  // pickup: status == completed
  // delivery: ONLY deliveryStatus == completed
  // =========================
  void _maybeShowCompletedScreen(Map<String, dynamic> data) {
    if (_completedScreenShown) return;
    if (!_isMine(data)) return;

    final fulfillment = (data['fulfillment'] ?? 'pickup').toString().toLowerCase().trim();
    final isDelivery = fulfillment == 'delivery';

    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    final deliveryStatus = (data['deliveryStatus'] ?? '').toString().toLowerCase().trim();

    final isCompleted = isDelivery
        ? (deliveryStatus == 'completed')
        : (status == 'completed');

    if (!isCompleted) return;

    _completedScreenShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderCompletedPage(
            orderId: widget.orderId,
            orderNumber: widget.orderNumber,
          ),
        ),
      );
    });
  }

  // =========================
  // ✅ Confirm Received Flow
  // =========================
  Future<void> _confirmReceivedFlow() async {
    if (_confirmingReceived) return;

    final t = AppLocalizations.of(context)!;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(t.confirmReceivedTitle),
        content: Text(t.confirmReceivedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.receivedButton),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (ok != true) return;

    setState(() => _confirmingReceived = true);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final docRef = _orderDoc();
        final snap = await tx.get(docRef);

        if (!snap.exists) throw Exception("Order not found");

        final data = snap.data() ?? <String, dynamic>{};

        final customerId = (data['customerId'] ?? data['userId'] ?? '').toString().trim();
        if (customerId.isEmpty || customerId != _uid) throw Exception("Not allowed");

        final fulfillment = (data['fulfillment'] ?? 'pickup').toString().toLowerCase().trim();
        final deliveryStatus = (data['deliveryStatus'] ?? '').toString().toLowerCase().trim();
        final paymentStatus = (data['paymentStatus'] ?? '').toString().toLowerCase().trim();
        final status = (data['status'] ?? '').toString().toLowerCase().trim();
        final partnerId = (data['deliveryPartnerId'] ?? '').toString().trim();

        if (fulfillment != 'delivery') throw Exception("Not a delivery order");
        if (partnerId.isEmpty) throw Exception("No delivery partner");
        if (deliveryStatus != 'accepted') throw Exception("Delivery not accepted yet");
        if (paymentStatus != 'paid') throw Exception("Order not paid yet");
        if (deliveryStatus == 'completed') {
          throw Exception("Already completed");
        }

        final tip = _readTip(data);
        final tipStatus = (data['tipStatus'] ?? 'pending').toString().toLowerCase().trim();

        tx.update(docRef, {
          'status': 'completed',
          'deliveryStatus': 'completed',
          'receivedAt': FieldValue.serverTimestamp(),
          'receivedBy': _uid,
          'tipReleased': (tip > 0),
          if (tip > 0) 'tipReleasedAt': FieldValue.serverTimestamp(),
          if (tip > 0) 'tipReleasedTo': partnerId,
          'tipStatus': (tip > 0) ? 'earned' : 'none',
          if (tip > 0) 'tipEarnedAt': FieldValue.serverTimestamp(),
        });

        if (tip > 0 && tipStatus != 'earned') {
          final tipDoc = FirebaseFirestore.instance
              .collection('users')
              .doc(partnerId)
              .collection('tips')
              .doc(widget.orderId);

          tx.set(tipDoc, {
            'orderId': widget.orderId,
            'amount': tip,
            'earnedAt': FieldValue.serverTimestamp(),
            'customerId': customerId,
            'cafeId': (data['cafeId'] ?? '').toString(),
            'orderNumber': data['orderNumber'] ?? widget.orderNumber,
          }, SetOptions(merge: true));

          final partnerUserDoc =
          FirebaseFirestore.instance.collection('users').doc(partnerId);

          tx.set(partnerUserDoc, {
            'totalTipsEarned': FieldValue.increment(tip),
            'tipsEarnedCount': FieldValue.increment(1),
            'walletBalanceSar': FieldValue.increment(tip),
          }, SetOptions(merge: true));
        }
      });

      if (!mounted) return;
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.receivedSuccessSnack)),
      );
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    } finally {
      if (mounted) setState(() => _confirmingReceived = false);
    }
  }


  // =========================
  // ✅ Delivery travel mode selected by delivery partner
  // =========================
  String _deliveryTravelMode(Map<String, dynamic> data) {
    return (data['deliveryTravelMode'] ?? data['deliveryPartnerTravelMode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
  }

  String _deliveryTravelModeLabel(String mode) {
    switch (mode) {
      case 'walking':
        return 'Walking';
      case 'metro':
        return 'Metro';
      default:
        return 'Not selected yet';
    }
  }

  IconData _deliveryTravelModeIcon(String mode) {
    switch (mode) {
      case 'walking':
        return Icons.directions_walk;
      case 'metro':
        return Icons.directions_transit;
      default:
        return Icons.route_outlined;
    }
  }

  int _readIntFromAny(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final v = data[key];
      if (v is int) return v;
      if (v is num) return v.round();
      final parsed = int.tryParse((v ?? '').toString());
      if (parsed != null) return parsed;
    }
    return 0;
  }

  int _deliveryEtaMinutes(Map<String, dynamic> data) {
    final travelMode = _deliveryTravelMode(data);

    if (travelMode == 'walking') {
      final walkingEta = _readIntFromAny(data, [
        'deliveryWalkingEstimatedMinutes',
        'deliveryWalkingEtaMinutes',
        'deliveryEstimatedMinutes',
        'deliveryEtaMinutes',
      ]);
      if (walkingEta > 0) return walkingEta;
    }

    if (travelMode == 'metro') {
      final metroEta = _readIntFromAny(data, [
        'deliveryMetroEstimatedMinutes',
        'deliveryMetroEtaMinutes',
        'deliveryEstimatedMinutes',
        'deliveryEtaMinutes',
      ]);
      if (metroEta > 0) return metroEta;
    }

    // Fallback for older orders. Prefer delivery-specific ETA when available,
    // otherwise use estimatedMinutes so the page still works.
    final deliveryEta = _readIntFromAny(data, [
      'deliveryEstimatedMinutes',
      'deliveryEtaMinutes',
      'estimatedMinutes',
    ]);

    return deliveryEta;
  }

  DateTime? _deliveryEtaBaseTime(Map<String, dynamic> data) {
    final acceptedAt = data['acceptedAt'];
    if (acceptedAt is Timestamp) return acceptedAt.toDate();

    final deliveryAcceptedAt = data['deliveryAcceptedAt'];
    if (deliveryAcceptedAt is Timestamp) return deliveryAcceptedAt.toDate();

    final updatedAt = data['updatedAt'];
    if (updatedAt is Timestamp) return updatedAt.toDate();

    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt.toDate();

    return null;
  }

  Widget _deliveryTravelModeCard({
    required Map<String, dynamic> data,
    required Color teal,
  }) {
    final mode = _deliveryTravelMode(data);
    final label = _deliveryTravelModeLabel(mode);
    final eta = _deliveryEtaMinutes(data);

    String body;
    if (mode.isEmpty) {
      body = 'The delivery partner must choose Walking or Metro before the delivery ETA can be shown.';
    } else if (eta > 0) {
      body = 'Delivery partner selected $label. The ETA below is based on this method.';
    } else {
      body = 'Delivery partner selected $label. ETA will be updated soon.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: teal.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: teal.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_deliveryTravelModeIcon(mode), color: teal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivery method: $label',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.62),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // ✅ Waiting countdown (from deliveryExpireAt)
  // =========================
  int _waitingRemainingSeconds(Map<String, dynamic> data) {
    final exp = data['deliveryExpireAt'];
    if (exp is Timestamp) {
      final diff = exp.toDate().difference(DateTime.now());
      return diff.isNegative ? 0 : diff.inSeconds;
    }
    return 0;
  }

  String _mmssFromSeconds(int seconds) {
    final s = seconds.clamp(0, 999999);
    final m = s ~/ 60;
    final r = s % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return "$m:${two(r)}";
  }

  Future<void> _onNoResponse(Map<String, dynamic> data) async {
    if (!mounted || _noResponseDialogOpen) return;
    _noResponseDialogOpen = true;

    final t = AppLocalizations.of(context)!;

    final action = await showDialog<_NoResponseAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(t.deliveryNoResponseTitle),
        content: Text(t.deliveryNoResponseBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _NoResponseAction.cancel),
            child: Text(t.cancelOrder),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _NoResponseAction.waitMore),
            child: Text(t.waitFiveMoreMinutes),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _NoResponseAction.switchToPickup),
            child: Text(t.switchToPickup),
          ),
        ],
      ),
    );

    _noResponseDialogOpen = false;
    if (!mounted) return;

    final ref = _orderDoc();

    if (action == _NoResponseAction.waitMore) {
      await ref.update({
        'deliveryExpireAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
      });
      return;
    }

    if (action == _NoResponseAction.switchToPickup) {
      await ref.update({
        'fulfillment': 'pickup',
        'deliveryStatus': 'timeout',
      });
      return;
    }

    await ref.update({
      'status': 'cancelled',
      'deliveryStatus': 'timeout',
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  // =========================
  // ✅ Status Parsing
  // =========================
  OrderStatus _parsePickupStatus(String s) {
    if (s == 'preparing') return OrderStatus.preparing;
    if (s == 'ready' || s == 'readytopickup') return OrderStatus.readyToPickup;
    return OrderStatus.placed;
  }

  Duration _remaining(DateTime baseAt, int etaMinutes) {
    final end = baseAt.add(Duration(minutes: etaMinutes));
    final diff = end.difference(DateTime.now());
    if (diff.isNegative) return Duration.zero;
    return diff;
  }

  String _mmss(Duration d) {
    final totalSec = d.inSeconds.clamp(0, 999999);
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return "${m.toString().padLeft(2, '0')} : ${s.toString().padLeft(2, '0')}";
  }

  Future<void> _openWaitingPage() async {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryWaitingPage(
          orderId: widget.orderId,
          orderNumber: widget.orderNumber,
        ),
      ),
    );
  }

  void _showPickupReminderOnce(String message) {
    if (_pickupReminderShown) return;
    _pickupReminderShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    const teal = Color(0xFF0E6F73);
    const brown = Color(0xFF7A4E2B);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _orderDoc().snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0.6,
              title: Text(
                t.orderTrackingTitle,
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Center(
              child: Text(
                t.orderTrackingNotFound,
                style: TextStyle(color: Colors.black.withOpacity(0.6)),
              ),
            ),
          );
        }

        final data = snap.data!.data()!;

        // ✅ if order completed => show completion screen
        _maybeShowCompletedScreen(data);

        final fulfillment = (data['fulfillment'] ?? 'pickup').toString().toLowerCase().trim();
        final isPickup = fulfillment != 'delivery';
        final isDelivery = !isPickup;

        final deliveryStatus = (data['deliveryStatus'] ?? 'waiting').toString().toLowerCase().trim();

        final pickupEtaMinutes = (data['estimatedMinutes'] is int)
            ? data['estimatedMinutes'] as int
            : int.tryParse('${data['estimatedMinutes']}') ?? 0;
        final deliveryTravelMode = _deliveryTravelMode(data);
        final deliveryEtaMinutes = _deliveryEtaMinutes(data);
        final hasDeliveryTravelMode = deliveryTravelMode == 'walking' || deliveryTravelMode == 'metro';
        final etaMinutes = isDelivery ? deliveryEtaMinutes : pickupEtaMinutes;

        final createdAtTs = data['createdAt'];
        DateTime? createdAt = (createdAtTs is Timestamp) ? createdAtTs.toDate() : null;

        final preparingStartedAtTs = data['preparingStartedAt'];
        DateTime? preparingStartedAt =
        (preparingStartedAtTs is Timestamp) ? preparingStartedAtTs.toDate() : null;

        createdAt ??= DateTime.now();

        final statusStr = ('${data['status'] ?? 'placed'}').toLowerCase().trim();
        final pickupStatus = _parsePickupStatus(statusStr);
        final deliveryIdx = _deliveryStepIndex(data);

        final showReceivedBtn = _canShowReceivedButton(data);
        final receivedHint = _receivedButtonHintText(data, t);

        final waitingSeconds = _waitingRemainingSeconds(data);
        final deliveryBaseAt = _deliveryEtaBaseTime(data);
        final countdownBaseAt = isDelivery
            ? (deliveryBaseAt ?? preparingStartedAt ?? createdAt)
            : (preparingStartedAt ?? createdAt);

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          if (isDelivery && deliveryStatus == 'waiting' && waitingSeconds <= 0 && !_noResponseDialogOpen) {
            await _onNoResponse(data);
          }
        });

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.6,
            centerTitle: true,
            title: Text(
              t.orderTrackingOrderNumber(widget.orderNumber.toString()),
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  children: [
                    if (isPickup)
                      _pickupStepper(status: pickupStatus, brown: brown, t: t)
                    else
                      _deliveryStepper(idx: deliveryIdx, brown: brown, t: t),

                    const SizedBox(height: 18),

                    if (isDelivery && deliveryStatus == 'waiting') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withOpacity(0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.deliveryWaitingCardTitle,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t.deliveryWaitingCardBody,
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 18),
                                const SizedBox(width: 8),
                                StreamBuilder<int>(
                                  stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
                                  builder: (context, _) {
                                    final sec = _waitingRemainingSeconds(data);
                                    return Text(
                                      t.deliveryWaitingTimeLeft(_mmssFromSeconds(sec)),
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    );
                                  },
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _openWaitingPage,
                                  child: Text(t.manageDeliveryRequest),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (isDelivery && deliveryStatus == 'accepted') ...[
                      _deliveryTravelModeCard(data: data, teal: teal),
                      const SizedBox(height: 18),
                    ],

                    const SizedBox(height: 8),

                    Center(
                      child: Column(
                        children: [
                          Text(
                            isPickup ? t.orderTrackingReadyIn : t.deliveryTrackingEtaTitle,
                            style: TextStyle(
                              color: teal.withOpacity(0.75),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 14),

                          StreamBuilder<int>(
                            stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
                            builder: (context, _) {
                              final liveRemaining = _remaining(countdownBaseAt, etaMinutes);
                              final liveIsZero = liveRemaining == Duration.zero;
                              final liveIsReadyStatus =
                                  statusStr == 'ready' || statusStr == 'readytopickup';

                              if (isDelivery && deliveryStatus == 'waiting') {
                                return Text(
                                  'Waiting for a delivery partner to accept your order',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black.withOpacity(0.6),
                                  ),
                                  textAlign: TextAlign.center,
                                );
                              }

                              if (isDelivery && deliveryStatus == 'accepted' && !hasDeliveryTravelMode) {
                                return Text(
                                  'Waiting for the delivery partner to select Walking or Metro',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black.withOpacity(0.6),
                                  ),
                                  textAlign: TextAlign.center,
                                );
                              }

                              if (isDelivery && deliveryStatus == 'accepted' && etaMinutes <= 0) {
                                return Text(
                                  'Delivery ETA will be updated soon',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black.withOpacity(0.6),
                                  ),
                                  textAlign: TextAlign.center,
                                );
                              }

                              if (!isDelivery && statusStr == 'placed') {
                                return Text(
                                  t.waitingForCafeAccept,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black.withOpacity(0.6),
                                  ),
                                  textAlign: TextAlign.center,
                                );
                              }

                              if (statusStr == 'preparing' && liveIsZero) {
                                return Text(
                                  t.orderDelayedMessage,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.orange,
                                  ),
                                  textAlign: TextAlign.center,
                                );
                              }

                              if (liveIsReadyStatus && liveIsZero) {
                                if (isPickup) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _showPickupReminderOnce(t.pickupReminderMessage);
                                  });
                                }

                                return Text(
                                  t.pickupReminderMessage,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.redAccent,
                                  ),
                                  textAlign: TextAlign.center,
                                );
                              }

                              return Text(
                                _mmss(liveRemaining),
                                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    if (isPickup) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: Container(
                          width: 220,
                          height: 220,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black.withOpacity(0.08)),
                            color: Colors.white,
                          ),
                          child: QrImageView(
                            data: widget.orderId,
                            version: QrVersions.auto,
                            gapless: false,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          t.orderTrackingQrHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: teal, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],

                    const SizedBox(height: 90),
                  ],
                ),
              ),

              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDelivery) ...[
                        if (showReceivedBtn)
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0E6F73),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                elevation: 8,
                              ),
                              onPressed: _confirmingReceived ? null : _confirmReceivedFlow,
                              child: _confirmingReceived
                                  ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                                  : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.white),
                                  const SizedBox(width: 10),
                                  Text(
                                    t.receivedButton,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              receivedHint,
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.65),
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 10),
                      ],

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: teal.withOpacity(0.35)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderDetailsPage(orderId: widget.orderId),
                              ),
                            );
                          },
                          child: Text(
                            t.orderTrackingViewOrderDetails,
                            style: TextStyle(fontWeight: FontWeight.w900, color: teal),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// ✅ COMPLETED PAGE (white screen)
// ============================================================
class OrderCompletedPage extends StatelessWidget {
  final String orderId;
  final int orderNumber;

  const OrderCompletedPage({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const teal = Color(0xFF0E6F73);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          t.orderTrackingOrderNumber(orderNumber.toString()),
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 86, color: teal),
              const SizedBox(height: 18),
              Text(
                t.staffStatusChangedCompleted,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                t.orderCompletedBody,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => OrderDetailsPage(orderId: orderId)),
                    );
                  },
                  child: Text(
                    t.orderTrackingViewOrderDetails,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: teal.withOpacity(0.35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    t.cancel,
                    style: TextStyle(color: teal, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ✅ Pickup Stepper
// ============================================================
Widget _pickupStepper({
  required OrderStatus status,
  required Color brown,
  required AppLocalizations t,
}) {
  int idx;
  if (status == OrderStatus.placed) {
    idx = 0;
  } else if (status == OrderStatus.preparing) {
    idx = 1;
  } else {
    idx = 2;
  }

  Widget dot({
    required bool active,
    required IconData icon,
    double shiftX = 0,
  }) {
    return Transform.translate(
      offset: Offset(shiftX, 0),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: brown, width: 2),
          color: active ? brown : Colors.white,
        ),
        child: Icon(icon, color: active ? Colors.white : brown),
      ),
    );
  }

  // ✅ label مع تحريك
  Widget label(String text, {double shiftX = 0}) => Transform.translate(
    offset: Offset(shiftX, 0),
    child: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        softWrap: true,
        style: TextStyle(
          color: brown,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    ),
  );

  Widget line() =>
      Expanded(child: Container(height: 2, color: brown.withOpacity(0.9)));

  return Column(
    children: [
      Row(
        children: [
          dot(
            active: idx >= 0,
            icon: Icons.check,
            shiftX: 8,
          ),
          line(),
          dot(
            active: idx >= 1,
            icon: Icons.local_cafe,
          ),
          line(),
          dot(
            active: idx >= 2,
            icon: Icons.notifications_none,
            shiftX: -8,
          ),
        ],
      ),

      const SizedBox(height: 6),

      Row(
        children: [
          Expanded(
            child: Center(
              child: label(
                t.orderTrackingPlaced,
                shiftX: -9, // 👈 لليسار
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: label(
                t.orderTrackingPreparing,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: label(
                t.orderTrackingReadyToPickup,
                shiftX: 7, // 👈 لليمين
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

// ============================================================
// ✅ Delivery Stepper
// ============================================================
Widget _deliveryStepper({
  required int idx,
  required Color brown,
  required AppLocalizations t,
}) {
  Widget dot({required bool active, required IconData icon}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: brown, width: 2),
        color: active ? brown : Colors.white,
      ),
      child: Icon(icon, color: active ? Colors.white : brown),
    );
  }

  Widget line() => Expanded(child: Container(height: 2, color: brown.withOpacity(0.9)));

  Widget label(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(color: brown, fontWeight: FontWeight.w800, fontSize: 11),
      textAlign: TextAlign.center,
    ),
  );

  return Column(
    children: [
      Row(
        children: [
          dot(active: idx >= 0, icon: Icons.hourglass_bottom),
          line(),
          dot(active: idx >= 1, icon: Icons.verified),
          line(),
          dot(active: idx >= 2, icon: Icons.local_cafe),
          line(),
          dot(active: idx >= 3, icon: Icons.delivery_dining),
          line(),
          dot(active: idx >= 4, icon: Icons.check_circle),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(width: 60, child: Center(child: label(t.deliveryStepWaiting))),
          SizedBox(width: 60, child: Center(child: label(t.deliveryStepAccepted))),
          SizedBox(width: 60, child: Center(child: label(t.deliveryStepPreparing))),
          SizedBox(width: 60, child: Center(child: label(t.deliveryStepOnTheWay))),
          SizedBox(width: 60, child: Center(child: label(t.deliveryStepDelivered))),
        ],
      ),
    ],
  );
}