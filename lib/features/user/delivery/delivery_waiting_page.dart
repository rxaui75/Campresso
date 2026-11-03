// delivery_waiting_page.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pay/pay.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'package:campresso/features/user/order_tracking_page.dart';

class DeliveryWaitingPage extends StatefulWidget {
  final String orderId;
  final int orderNumber;

  /// fallback only (if deliveryExpireAt missing)
  final Duration waitDuration;

  const DeliveryWaitingPage({
    super.key,
    required this.orderId,
    required this.orderNumber,
    this.waitDuration = const Duration(minutes: 5),
  });

  @override
  State<DeliveryWaitingPage> createState() => _DeliveryWaitingPageState();
}

enum _NoResponseAction { cancel, switchToPickup, waitMore }
enum _ExitAction { stay, goTracking }

class _DeliveryWaitingPageState extends State<DeliveryWaitingPage> {
  bool _noResponseDialogOpen = false;
  bool _acceptedDialogShown = false;
  bool _paying = false;

  // ✅ تحميل الكونفيق مرة واحدة
  late final Future<PaymentConfiguration> _applePayConfigFuture =
  PaymentConfiguration.fromAsset('pay/apple_pay.json');

  late final Future<PaymentConfiguration> _googlePayConfigFuture =
  PaymentConfiguration.fromAsset('pay/google_pay.json');

  DocumentReference<Map<String, dynamic>> get _orderRef =>
      FirebaseFirestore.instance.collection('orders').doc(widget.orderId);

  // ============================================================
  // ✅ Exit handling (prevent accidental back)
  // ============================================================
  Future<void> _handleExitAttempt({
    required String deliveryStatus,
    required String paymentStatus,
  }) async {
    final t = AppLocalizations.of(context)!;

    // If already accepted/paid, it’s OK to leave to tracking directly (no scary dialog)
    final safeToJustTrack = (deliveryStatus == 'accepted') || (paymentStatus == 'paid');

    if (!mounted) return;

    if (safeToJustTrack) {
      await _goTracking();
      return;
    }

    final action = await showDialog<_ExitAction>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(t.deliveryLeaveTitle),
        content: Text(t.deliveryLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExitAction.stay),
            child: Text(t.stayHere),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _ExitAction.goTracking),
            child: Text(t.goToTracking),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (action == _ExitAction.goTracking) {
      await _goTracking();
    }
  }

  // ============================================================
  // No response dialog (Cancel / Switch to pickup / Wait more)
  // ============================================================
  Future<void> _onNoResponse() async {
    if (!mounted || _noResponseDialogOpen) return;
    _noResponseDialogOpen = true;

    final t = AppLocalizations.of(context)!;

    final action = await showDialog<_NoResponseAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
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
        );
      },
    );

    _noResponseDialogOpen = false;
    if (!mounted) return;

    if (action == _NoResponseAction.waitMore) {
      // ✅ extend expire by 5 minutes
      await _orderRef.update({
        'deliveryExpireAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
      });
      return;
    }

    if (action == _NoResponseAction.switchToPickup) {
      // ✅ convert to pickup
      await _orderRef.update({
        'fulfillment': 'pickup',
        'deliveryStatus': 'timeout',
      });

      // Go to tracking (now pickup mode UI)
      await _goTracking();
      return;
    }

    // Cancel
    await _orderRef.update({
      'status': 'cancelled',
      'deliveryStatus': 'timeout',
      'cancelledAt': FieldValue.serverTimestamp(),
    });

    // back to tracking (it will show cancelled)
    await _goTracking();
  }

  // ============================================================
  // Pay Flow
  // ============================================================

  /// ✅ للدليفري: ادفعي على paidAmount (إن وجد) وإلا grandTotal وإلا amountPaid
  Future<double> _readPayableAmount() async {
    final snap = await _orderRef.get();
    final data = snap.data();

    dynamic v = data?['paidAmount'];
    v ??= data?['grandTotal'];
    v ??= data?['amountPaid'];
    v ??= 0;

    if (v is num) return v.toDouble();
    return 0.0;
  }

  List<PaymentItem> _paymentItems(AppLocalizations t, double amount) => [
    PaymentItem(
      label: t.checkoutTotalLabel,
      amount: amount.toStringAsFixed(2),
      status: PaymentItemStatus.final_price,
    ),
  ];

  /// ✅ بعد نجاح الدفع
  Future<void> _markPaid({required String paymentMethod}) async {
    final snap = await _orderRef.get();
    final data = snap.data() ?? {};

    final tip = (data['tipAmount'] ?? data['deliveryTip'] ?? 0);
    final tipVal = (tip is num) ? tip.toDouble() : 0.0;

    await _orderRef.update({
      'paymentStatus': 'paid',
      'paymentMethod': paymentMethod,
      'paidAt': FieldValue.serverTimestamp(),
      'tipStatus': tipVal > 0 ? 'pending' : 'none',
    });
  }

  Future<void> _goTracking() async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OrderTrackingPage(
          orderId: widget.orderId,
          orderNumber: widget.orderNumber,
        ),
      ),
    );
  }

  Future<void> _onGooglePayResult(dynamic result) async {
    if (!mounted) return;

    try {
      await _markPaid(paymentMethod: "google");
      if (!mounted) return;

      Navigator.pop(context); // close bottom sheet
      await _goTracking();
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    }
  }

  Future<void> _onApplePayResult(dynamic result) async {
    if (!mounted) return;

    try {
      await _markPaid(paymentMethod: "apple");
      if (!mounted) return;

      Navigator.pop(context); // close bottom sheet
      await _goTracking();
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    }
  }

  Future<void> _startOnlinePayFlow() async {
    if (!mounted || _paying) return;
    setState(() => _paying = true);

    final t = AppLocalizations.of(context)!;

    try {
      final amount = await _readPayableAmount();
      if (!mounted) return;

      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${t.error}: ${t.invalidAmountError}")),
        );
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isDismissible: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (sheetCtx) {
          final items = _paymentItems(t, amount);

          Widget payButton;

          if (Platform.isIOS) {
            payButton = FutureBuilder<PaymentConfiguration>(
              future: _applePayConfigFuture,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text("Pay config error: ${snap.error}");
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ApplePayButton(
                  paymentConfiguration: snap.data!,
                  paymentItems: items,
                  style: ApplePayButtonStyle.black,
                  type: ApplePayButtonType.buy,
                  onPaymentResult: _onApplePayResult,
                  onError: (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("${t.applePayError}: $error")),
                    );
                  },
                  loadingIndicator: const Center(child: CircularProgressIndicator()),
                );
              },
            );
          } else {
            payButton = FutureBuilder<PaymentConfiguration>(
              future: _googlePayConfigFuture,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text("Pay config error: ${snap.error}");
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return GooglePayButton(
                  paymentConfiguration: snap.data!,
                  paymentItems: items,
                  type: GooglePayButtonType.pay,
                  onPaymentResult: _onGooglePayResult,
                  onError: (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("${t.googlePayError}: $error")),
                    );
                  },
                  loadingIndicator: const Center(child: CircularProgressIndicator()),
                );
              },
            );
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t.checkoutChoosePaymentMethod,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 52, child: payButton),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  // ============================================================
  // Accepted popup
  // ============================================================
  Future<void> _showAcceptedDialogInfoOnly() async {
    if (!mounted || _acceptedDialogShown) return;
    _acceptedDialogShown = true;

    final t = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(t.deliveryAcceptedTitle),
        content: Text(t.deliveryAcceptedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.ok),
          ),
        ],
      ),
    );
  }

  void _handleStatusSideEffects({
    required String deliveryStatus,
    required int remainingSeconds,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // accepted
      if (deliveryStatus == 'accepted') {
        await _showAcceptedDialogInfoOnly();
      }

      // time ended and still waiting -> show no response dialog
      if (deliveryStatus == 'waiting' && remainingSeconds <= 0) {
        await _onNoResponse();
      }
    });
  }

  // ============================================================
  // Countdown formatting
  // ============================================================
  String _formatRemaining(int seconds) {
    final s = seconds.clamp(0, 999999);
    final m = s ~/ 60;
    final r = s % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return "$m:${two(r)}";
  }

  int _calcRemainingSeconds(Map<String, dynamic> data) {
    // Prefer deliveryExpireAt from Firestore
    final exp = data['deliveryExpireAt'];
    if (exp is Timestamp) {
      final diff = exp.toDate().difference(DateTime.now());
      return diff.isNegative ? 0 : diff.inSeconds;
    }

    // fallback: createdAt + waitDuration
    final created = data['createdAt'];
    if (created is Timestamp) {
      final end = created.toDate().add(widget.waitDuration);
      final diff = end.difference(DateTime.now());
      return diff.isNegative ? 0 : diff.inSeconds;
    }

    // final fallback
    return widget.waitDuration.inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const teal = Color(0xFF0E6F73);

    return Scaffold(
      backgroundColor: Colors.white,

      // ✅ prevent accidental back
      body: PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          // We control back ourselves (no direct pop)
          // We'll decide based on current Firestore state inside StreamBuilder (below)
        },
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _orderRef.snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? {};
            final deliveryStatus = (data['deliveryStatus'] ?? 'waiting').toString().toLowerCase().trim();
            final paymentStatus = (data['paymentStatus'] ?? 'unpaid').toString().toLowerCase().trim();

            final isAccepted = deliveryStatus == 'accepted';
            final isPaid = paymentStatus == 'paid';

            // countdown (seconds)
            final remainingSeconds = _calcRemainingSeconds(data);

            _handleStatusSideEffects(
              deliveryStatus: deliveryStatus,
              remainingSeconds: remainingSeconds,
            );

            final canPay = isAccepted && !isPaid && !_paying;

            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                title: Text(t.deliveryRequestTitle),
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  onPressed: () => _handleExitAttempt(
                    deliveryStatus: deliveryStatus,
                    paymentStatus: paymentStatus,
                  ),
                ),
              ),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.deliveryWaitingTitle,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.deliveryWaitingSubtitle,
                      style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // ✅ Countdown box (updates itself each second, not the whole page)
                    _CountdownBox(
                      label: t.deliveryWaitingTimeHint,
                      formatter: _formatRemaining,
                      getRemainingSeconds: () => remainingSeconds,
                    ),

                    const SizedBox(height: 12),

                    Text(
                      "${t.deliveryStatusLabel}: $deliveryStatus",
                      style: TextStyle(color: teal, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.deliveryPaymentStatus(paymentStatus),
                      style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w800),
                    ),

                    const Spacer(),

                    // ✅ زر Pay / Paid / Disabled
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: teal,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: isPaid
                            ? _goTracking
                            : (canPay ? _startOnlinePayFlow : null),
                        child: _paying
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : Text(
                          isPaid
                              ? t.paidTrackOrderCta
                              : (isAccepted ? t.payNow : t.deliveryPayAfterAccept),
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// ✅ Countdown box widget (ticks every second)
// ============================================================
class _CountdownBox extends StatelessWidget {
  final String label;
  final String Function(int seconds) formatter;
  final int Function() getRemainingSeconds;

  const _CountdownBox({
    required this.label,
    required this.formatter,
    required this.getRemainingSeconds,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final seconds = getRemainingSeconds();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                formatter(seconds),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        );
      },
    );
  }
}
