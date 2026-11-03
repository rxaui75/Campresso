import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class StaffScanQrPage extends StatefulWidget {
  final String? expectedOrderDocId;
  final int? expectedOrderNumber;

  const StaffScanQrPage({
    super.key,
    this.expectedOrderDocId,
    this.expectedOrderNumber,
  });

  @override
  State<StaffScanQrPage> createState() => _StaffScanQrPageState();
}

class _StaffScanQrPageState extends State<StaffScanQrPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handling = false;
  String? _statusText;

  String? _extractRawValue(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    return v;
  }

  String? _extractOrderDocId(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;

    // supports: "order:<docId>" or just "<docId>"
    if (v.startsWith('order:')) {
      final id = v.substring('order:'.length).trim();
      return id.isEmpty ? null : id;
    }
    return v;
  }

  Future<void> _completePickupOrder({
    required String orderDocId,
  }) async {
    final t = AppLocalizations.of(context)!;

    setState(() => _statusText = t.staffQrVerifying);

    final update = <String, dynamic>{
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('orders')
        .doc(orderDocId)
        .set(update, SetOptions(merge: true));

    if (!mounted) return;

    setState(() => _statusText = t.staffQrCompletedSuccess);
    await Future.delayed(const Duration(milliseconds: 350));

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _handoffDeliveryOrderToDriver({
    required String orderDocId,
  }) async {
    final t = AppLocalizations.of(context)!;

    setState(() => _statusText = t.staffQrVerifying);

    final update = <String, dynamic>{
      'status': 'ready',
      'deliveryStatus': 'accepted',
      'deliveryProgress': 'on_the_way',
      'handoffToDriverAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('orders')
        .doc(orderDocId)
        .set(update, SetOptions(merge: true));

    if (!mounted) return;

    setState(() => _statusText = t.staffQrCompletedSuccess);
    await Future.delayed(const Duration(milliseconds: 350));

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<bool> _validateAgainstExpectedOrder({
    required String expectedOrderDocId,
    required String scannedRaw,
  }) async {
    final t = AppLocalizations.of(context)!;

    final orderSnap = await FirebaseFirestore.instance
        .collection('orders')
        .doc(expectedOrderDocId)
        .get();

    if (!orderSnap.exists) {
      if (mounted) {
        setState(() => _statusText = t.orderTrackingNotFound);
      }
      return false;
    }

    final data = orderSnap.data() ?? <String, dynamic>{};
    final fulfillment =
    (data['fulfillment'] ?? 'pickup').toString().toLowerCase().trim();

    final isDelivery = fulfillment == 'delivery';

    if (isDelivery) {
      final expectedDeliveryBarcode =
      (data['deliveryPartnerBarcode'] ?? '').toString().trim();

      if (expectedDeliveryBarcode.isEmpty) {
        setState(() => _statusText = t.staffQrInvalidCode);
        return false;
      }

      if (scannedRaw != expectedDeliveryBarcode) {
        setState(() => _statusText = t.staffQrWrongOrder);
        return false;
      }

      await _handoffDeliveryOrderToDriver(orderDocId: expectedOrderDocId);
      return true;
    }

    final scannedOrderDocId = _extractOrderDocId(scannedRaw);
    if (scannedOrderDocId == null) {
      setState(() => _statusText = t.staffQrInvalidCode);
      return false;
    }

    if (scannedOrderDocId != expectedOrderDocId) {
      setState(() => _statusText = t.staffQrWrongOrder);
      return false;
    }

    await _completePickupOrder(orderDocId: expectedOrderDocId);
    return true;
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    _handling = true;

    try {
      final t = AppLocalizations.of(context)!;

      final raw = capture.barcodes.firstOrNull?.rawValue ?? '';
      final scannedRaw = _extractRawValue(raw);

      if (scannedRaw == null) {
        setState(() => _statusText = t.staffQrInvalidCode);
        _handling = false;
        return;
      }

      // ✅ إذا الصفحة جايه من زر complete (expected موجود)
      final expected = widget.expectedOrderDocId;
      if (expected != null && expected.isNotEmpty) {
        final handled = await _validateAgainstExpectedOrder(
          expectedOrderDocId: expected,
          scannedRaw: scannedRaw,
        );

        if (!handled) {
          _handling = false;
        }
        return;
      }

      // ✅ fallback بدون expected:
      // نحاول فقط كـ pickup order doc id
      final scannedOrderDocId = _extractOrderDocId(scannedRaw);
      if (scannedOrderDocId == null) {
        setState(() => _statusText = t.staffQrInvalidCode);
        _handling = false;
        return;
      }

      await _completePickupOrder(orderDocId: scannedOrderDocId);
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context)!;
        setState(() => _statusText = "${t.error}: $e");
      }
      _handling = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        centerTitle: true,
        title: Text(
          t.staffScanQrTitle,
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                ),
              ),
            ),
          ),

          Center(
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 28,
            child: Column(
              children: [
                Text(
                  t.staffQrScanInstruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                if (_statusText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _statusText!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}