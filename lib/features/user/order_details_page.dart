// order_details_page.dart
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

// ✅ For Call + WhatsApp
import 'package:url_launcher/url_launcher.dart';

// ✅ Pay
import 'package:pay/pay.dart';

// ✅ QR
import 'package:qr_flutter/qr_flutter.dart';

class OrderDetailsPage extends StatefulWidget {
  final String orderId;

  /// ✅ Keep for backward compatibility, but we don't rely on it
  final bool asDeliveryPartner;

  const OrderDetailsPage({
    super.key,
    required this.orderId,
    this.asDeliveryPartner = false,
  });

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  // ✅ تحميل الكونفيق مرة واحدة (مهم: المسار بدون "assets/")
  late final Future<PaymentConfiguration> _applePayConfigFuture =
  PaymentConfiguration.fromAsset('pay/apple_pay.json');

  late final Future<PaymentConfiguration> _googlePayConfigFuture =
  PaymentConfiguration.fromAsset('pay/google_pay.json');

  bool _paying = false;

  DocumentReference<Map<String, dynamic>> _orderRef() {
    return FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
  }

  /// ✅ للدليفري: ادفعي على paidAmount (إن وجد) وإلا grandTotal وإلا amountPaid
  Future<double> _readPayableAmount() async {
    final snap = await _orderRef().get();
    final data = snap.data();

    dynamic v = data?['paidAmount'];
    v ??= data?['grandTotal'];
    v ??= data?['amountPaid'];
    v ??= 0;

    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  List<PaymentItem> _paymentItems(AppLocalizations t, double amount) => [
    PaymentItem(
      label: t.checkoutTotalLabel,
      amount: amount.toStringAsFixed(2),
      status: PaymentItemStatus.final_price,
    ),
  ];

  /// ✅ بعد نجاح الدفع:
  /// - paymentStatus = paid
  /// - paymentMethod = apple/google
  /// - paidAt
  /// - tipStatus: pending/none
  /// - ✅ IMPORTANT: إذا (delivery + accepted) نحول status إلى preparing (بدون ما يصير قبل الدفع)
  Future<void> _markPaidAndStartPreparingIfNeeded({
    required String paymentMethod, // "apple" | "google"
  }) async {
    final ref = _orderRef();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception("Order not found");

      final data = snap.data() ?? <String, dynamic>{};

      final fulfillment =
      (data['fulfillment'] ?? 'pickup').toString().toLowerCase().trim();
      final deliveryStatus =
      (data['deliveryStatus'] ?? 'waiting').toString().toLowerCase().trim();
      final status = (data['status'] ?? 'placed').toString().toLowerCase().trim();

      final tip = (data['tipAmount'] ?? data['deliveryTip'] ?? 0);
      final tipVal =
      (tip is num) ? tip.toDouble() : double.tryParse("$tip") ?? 0.0;

      final update = <String, dynamic>{
        'paymentStatus': 'paid',
        'paymentMethod': paymentMethod,
        'paidAt': FieldValue.serverTimestamp(),
        'tipStatus': tipVal > 0 ? 'pending' : 'none',
      };

      // ✅ فقط للدليفري: بعد الدفع + بعد accept → خلي الكافيه يبدأ preparing
      final isDelivery = fulfillment == 'delivery';
      final isAccepted = deliveryStatus == 'accepted';

      // ما نلمس status إذا كان جاهز/مكتمل/ملغي.. الخ
      final safeToStart =
      (status == 'placed' || status == 'pending' || status == 'pending_payment');

      if (isDelivery && isAccepted && safeToStart) {
        update['status'] = 'preparing';
        update['preparingStartedAt'] = FieldValue.serverTimestamp();
      }

      tx.update(ref, update);
    });
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
          SnackBar(content: Text("${t.error}: invalid amount")),
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
        builder: (_) {
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
                  onPaymentResult: (_) async {
                    try {
                      await _markPaidAndStartPreparingIfNeeded(paymentMethod: "apple");
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.paymentSuccess)),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${t.error}: $e")),
                      );
                    }
                  },
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
                  onPaymentResult: (_) async {
                    try {
                      await _markPaidAndStartPreparingIfNeeded(paymentMethod: "google");
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.paymentSuccess)),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${t.error}: $e")),
                      );
                    }
                  },
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
  // ✅ Delivery location resolver (same idea as Orders page)
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

    final docRef = _orderRef();
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _simple(context, t.orderDetailsTitle, "${t.orderDetailsError}: ${snap.error}");
        }

        if (!snap.hasData) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0.6,
              centerTitle: true,
              title: Text(
                t.orderDetailsTitle,
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data!.data();
        if (data == null) {
          return _simple(context, t.orderDetailsTitle, t.orderDetailsNotFound);
        }

        final rawOrderNo = data["orderNumber"];
        final int orderNumber = (rawOrderNo is int) ? rawOrderNo : int.tryParse("$rawOrderNo") ?? 0;

        final createdTs = data["createdAt"];
        final createdAt = (createdTs is Timestamp) ? createdTs.toDate() : DateTime.now();

        final etaRaw = data["estimatedMinutes"];
        final eta = (etaRaw is int) ? etaRaw : int.tryParse("$etaRaw") ?? 0;

        final items = (data["items"] as List? ?? []).cast<Map>();

        final fulfillment = (data["fulfillment"] ?? "pickup").toString().toLowerCase().trim();
        final deliveryStatus = (data["deliveryStatus"] ?? "waiting").toString().toLowerCase().trim();

        // ✅ Money fields
        final amountPaid = (data["paidAmount"] ?? data["grandTotal"] ?? data["amountPaid"] ?? 0);
        final amountPaidDouble =
        (amountPaid is num) ? amountPaid.toDouble() : double.tryParse("$amountPaid") ?? 0.0;

        // ✅ Payment fields
        final paymentStatus = (data["paymentStatus"] ?? "unpaid").toString().toLowerCase().trim();
        final pmRaw = (data["paymentMethod"] ?? "cash").toString().toLowerCase().trim();
        final isPaid = paymentStatus == 'paid';

        final deliveryLocationText = _deliveryLocationText(data, t);

        final customerId = (data["customerId"] ?? data["userId"] ?? "").toString();
        final deliveryPartnerId = (data["deliveryPartnerId"] ?? "").toString();

        final storedCustomerName = (data["customerName"] ?? "").toString().trim();
        final storedDeliveryPartnerName = (data["deliveryPartnerName"] ?? "").toString().trim();
        final storedDeliveryPartnerPhone = (data["deliveryPartnerPhone"] ?? "").toString().trim();
        final storedDeliveryPartnerBarcode = (data["deliveryPartnerBarcode"] ?? "").toString().trim();

        final bool isDeliveryPartner = (myUid != null && myUid == deliveryPartnerId);
        final bool isCustomer = (myUid != null && myUid == customerId);

        final bool hideMoneyForThisUser = isDeliveryPartner;

        final bool isDeliveryOrder = fulfillment == 'delivery';
        final bool isAccepted = deliveryStatus == 'accepted';

        final bool showCustomerContactForDeliveryGirl =
            isDeliveryOrder && isAccepted && isDeliveryPartner;
        final bool showDeliveryGirlContactForCustomer =
            isDeliveryOrder && isAccepted && isCustomer;
        final bool showDeliveryPartnerQr = isDeliveryOrder && isAccepted && isDeliveryPartner;

        // ✅ Customer can pay ONLY if: delivery + accepted + unpaid + customer
        final bool canPayHere = isDeliveryOrder && isAccepted && !isPaid && isCustomer && !_paying;

        String _fallbackBarcode(String orderId, String partnerId) {
          final code = (orderId.hashCode ^ partnerId.hashCode).abs() % 100000000;
          return code.toString().padLeft(8, '0');
        }

        final deliveryPartnerBarcode = storedDeliveryPartnerBarcode.isNotEmpty
            ? storedDeliveryPartnerBarcode
            : (deliveryPartnerId.isNotEmpty
            ? _fallbackBarcode(widget.orderId, deliveryPartnerId)
            : "");

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.6,
            centerTitle: true,
            title: Text(
              orderNumber == 0
                  ? t.orderTrackingTitle
                  : t.orderTrackingOrderNumber(orderNumber.toString()),
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Center(
                child: Text(
                  orderNumber == 0
                      ? t.orderDetailsHeader(widget.orderId)
                      : t.orderTrackingShortOrderNumber(orderNumber.toString()),
                  style: TextStyle(color: teal, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              const SizedBox(height: 18),

              // =========================
              // Delivery Info
              // =========================
              if (isDeliveryOrder) ...[
                _sectionTitle(context, "Delivery Info"),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    children: [
                      if (isDeliveryPartner) ...[
                        _kvAutoName(
                          context: context,
                          label: "Customer",
                          directName: storedCustomerName,
                          userId: customerId,
                          fallback: t.customer,
                        ),
                        const SizedBox(height: 10),
                        _kvWrap(context, "Delivery location", deliveryLocationText),
                        const SizedBox(height: 10),
                        _kv(context, "Delivery status", deliveryStatus),
                      ] else ...[
                        _kvWrap(context, "Delivery location", deliveryLocationText),
                        const SizedBox(height: 10),
                        _kv(context, "Delivery status", deliveryStatus),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Customer -> delivery girl contact
                if (showDeliveryGirlContactForCustomer) ...[
                  _sectionTitle(context, "Delivery Girl Contact"),
                  const SizedBox(height: 10),
                  if (storedDeliveryPartnerName.isNotEmpty || storedDeliveryPartnerPhone.isNotEmpty)
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            storedDeliveryPartnerName.isEmpty
                                ? "Delivery Girl"
                                : storedDeliveryPartnerName,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            storedDeliveryPartnerPhone.isEmpty
                                ? "Not available"
                                : storedDeliveryPartnerPhone,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: storedDeliveryPartnerPhone.isEmpty
                                  ? Colors.black.withOpacity(0.55)
                                  : Colors.black87,
                            ),
                          ),
                          if (storedDeliveryPartnerPhone.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _callWhatsappRow(
                              context: context,
                              teal: teal,
                              phone: storedDeliveryPartnerPhone,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Use this number only for delivery coordination.",
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.55),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    _deliveryPartnerContactCard(
                      context: context,
                      teal: teal,
                      partnerId: deliveryPartnerId,
                    ),
                  const SizedBox(height: 14),
                ],

                // Delivery girl -> customer contact
                if (showCustomerContactForDeliveryGirl) ...[
                  _sectionTitle(context, "Customer Contact"),
                  const SizedBox(height: 10),
                  _userContactCard(context: context, teal: teal, userId: customerId),
                  const SizedBox(height: 14),
                ],

                // QR for delivery partner
                if (showDeliveryPartnerQr) ...[
                  _sectionTitle(context, t.deliveryPartnerBarcodeTitle),
                  const SizedBox(height: 10),
                  _card(
                    child: Column(
                      children: [
                        Text(
                          t.deliveryPartnerBarcodeHint,
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.6),
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: 220,
                          height: 220,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black.withOpacity(0.08)),
                            color: Colors.white,
                          ),
                          child: deliveryPartnerBarcode.isEmpty
                              ? Center(
                            child: Text(
                              t.notAvailable,
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                              : QrImageView(
                            data: deliveryPartnerBarcode,
                            version: QrVersions.auto,
                            gapless: false,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ],

              // Items
              _sectionTitle(context, t.orderDetailsItems(items.length)),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  children: [
                    for (final it in items) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "x${it["qty"] ?? 1} ${it["name"] ?? ""}",
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (!hideMoneyForThisUser)
                            Text(
                              t.amountSar(((it["lineTotal"] ?? 0).toDouble()).toStringAsFixed(2)),
                              style: TextStyle(color: teal, fontWeight: FontWeight.w900),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ]
                  ],
                ),
              ),

              const SizedBox(height: 14),
              _sectionTitle(context, t.orderDetailsCafeDetails),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  children: [
                    _kv(
                      context,
                      t.orderDetailsLocation,
                      (data["cafeName"] ?? t.orderDetailsCafeFallback).toString(),
                    ),
                    const SizedBox(height: 10),
                    _kv(context, t.orderDetailsReadyAt, _readyAtLabel(createdAt, eta)),
                  ],
                ),
              ),

              // =========================
              // Payment (Pending/Paid + Pay now)
              // =========================
              if (!hideMoneyForThisUser) ...[
                const SizedBox(height: 14),
                _sectionTitle(context, t.orderDetailsPaymentMethod),
                const SizedBox(height: 10),
                _card(
                  child: Row(
                    children: [
                      Icon(Icons.payment, color: teal),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isPaid ? _paymentLabel(context, pmRaw) : t.pending,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        isPaid ? t.orderDetailsPaid : t.pending,
                        style: TextStyle(
                          color: isPaid ? teal : Colors.black.withOpacity(0.55),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),

                if (canPayHere) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: teal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _startOnlinePayFlow,
                      child: _paying
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Text(
                        t.payNow,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                _card(
                  child: _kv(
                    context,
                    t.orderDetailsTotal,
                    t.amountSar(amountPaidDouble.toStringAsFixed(2)),
                    bold: true,
                  ),
                ),
              ],

              if (isDeliveryPartner) ...[
                const SizedBox(height: 14),
                Text(
                  t.deliveryPrivacyNote,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // =========================
  // Helpers
  // =========================

  static Widget _kvAutoName({
    required BuildContext context,
    required String label,
    required String directName,
    required String userId,
    required String fallback,
  }) {
    if (directName.trim().isNotEmpty) {
      return _kv(context, label, directName.trim());
    }
    if (userId.trim().isEmpty) {
      return _kv(context, label, fallback);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snap) {
        if (!snap.hasData) return _kv(context, label, fallback);
        final u = snap.data!.data() ?? {};
        final full = (u['fullName'] ?? '').toString().trim();
        final first = (u['firstName'] ?? '').toString().trim();
        final last = (u['lastName'] ?? '').toString().trim();
        final combined = [first, last].where((x) => x.isNotEmpty).join(' ');
        final name = full.isNotEmpty ? full : (combined.isNotEmpty ? combined : fallback);
        return _kv(context, label, name);
      },
    );
  }

  static Widget _userContactCard({
    required BuildContext context,
    required Color teal,
    required String userId,
  }) {
    if (userId.trim().isEmpty) {
      return _card(
        child: Text(
          "Not available",
          style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w700),
        ),
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snap) {
        if (!snap.hasData) return _card(child: const Center(child: CircularProgressIndicator()));

        final u = snap.data!.data() ?? {};
        final phone = (u['phoneNumber'] ?? '').toString().trim();

        if (phone.isEmpty) {
          return _card(
            child: Text(
              "Not available",
              style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w700),
            ),
          );
        }

        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(phone, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 12),
              _callWhatsappRow(context: context, teal: teal, phone: phone),
              const SizedBox(height: 8),
              Text(
                "Use this number only for delivery coordination.",
                style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _deliveryPartnerContactCard({
    required BuildContext context,
    required Color teal,
    required String partnerId,
  }) {
    if (partnerId.trim().isEmpty) {
      return _card(
        child: Text(
          "Not assigned yet",
          style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w700),
        ),
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(partnerId).get(),
      builder: (context, snap) {
        if (!snap.hasData) return _card(child: const Center(child: CircularProgressIndicator()));

        final u = snap.data!.data() ?? {};
        final name = (u['fullName'] ?? u['name'] ?? u['displayName'] ?? '').toString().trim();
        final phone = (u['phoneNumber'] ?? '').toString().trim();

        if (name.isEmpty && phone.isEmpty) {
          return _card(
            child: Text(
              "Not available",
              style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w700),
            ),
          );
        }

        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? "Delivery Girl" : name,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                phone.isEmpty ? "Not available" : phone,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: phone.isEmpty ? Colors.black.withOpacity(0.55) : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              if (phone.isNotEmpty) ...[
                _callWhatsappRow(context: context, teal: teal, phone: phone),
                const SizedBox(height: 8),
                Text(
                  "Use this number only for delivery coordination.",
                  style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static Widget _callWhatsappRow({
    required BuildContext context,
    required Color teal,
    required String phone,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final uri = Uri.parse("tel:$phone");
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                await Clipboard.setData(ClipboardData(text: phone));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Copied to clipboard")),
                  );
                }
              }
            },
            icon: const Icon(Icons.call),
            label: const Text("Call", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: teal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final wa = _waNumber(phone);
              final uri = Uri.parse("https://wa.me/$wa");
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                await Clipboard.setData(ClipboardData(text: phone));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Copied to clipboard")),
                  );
                }
              }
            },
            icon: const Icon(Icons.chat, color: Colors.white),
            label: const Text(
              "WhatsApp",
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  static String _waNumber(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static Scaffold _simple(BuildContext context, String title, String msg) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        title: Text(
          title,
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(child: Text(msg)),
    );
  }

  static String _paymentLabel(BuildContext context, String m) {
    final t = AppLocalizations.of(context)!;

    if (m == "cash") return t.paymentCashOnDelivery;
    if (m == "online") return t.paymentOnline;
    if (m == "apple") return t.paymentApplePay;
    if (m == "google") return t.paymentGooglePay;

    return m;
  }

  static String _readyAtLabel(DateTime createdAt, int etaMin) {
    final dt = createdAt.add(Duration(minutes: etaMin));
    String two(int x) => x.toString().padLeft(2, '0');
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    return "${two(dt.day)}/${two(dt.month)}/${dt.year}  $h:${two(dt.minute)} $ampm";
  }

  static Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.brown.shade600,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
    );
  }

  static Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: child,
    );
  }

  static Widget _kv(BuildContext context, String k, String v, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w800),
        ),
      ],
    );
  }

  static Widget _kvWrap(BuildContext context, String k, String v, {bool bold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            k,
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w800),
          ),
        ),
      ],
    );
  }
}