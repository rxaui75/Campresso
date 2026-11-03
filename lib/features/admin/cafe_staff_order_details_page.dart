import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class CafeStaffOrderDetailsPage extends StatelessWidget {
  final String orderDocId;
  final String cafeId;

  const CafeStaffOrderDetailsPage({
    super.key,
    required this.orderDocId,
    required this.cafeId,
  });

  static const _teal = Color(0xFF0E6F73);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          t.staffOrderDetailsTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderDocId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("${t.error}: ${snap.error}"));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snap.data!;
          final data = doc.data();

          if (data == null) {
            return Center(child: Text(t.staffOrderNotFound));
          }

          // ✅ optional safety: ensure staff is viewing same cafe
          final orderCafeId = (data['cafeId'] ?? '').toString();
          if (orderCafeId.isNotEmpty && orderCafeId != cafeId) {
            return Center(child: Text(t.staffOrderCafeMismatch));
          }

          final orderNumber = _safeInt(data, 'orderNumber', fallback: 0);
          final customerName =
          _safeString(data, 'customerName', fallback: t.staffUnknownCustomer);
          final customerPhone = _safeString(data, 'customerPhone', fallback: '');

          final status =
          _safeString(data, 'status', fallback: 'placed').toLowerCase().trim();

          // Time logic:
          // - If readyAt exists -> show as "Ready at" (real ready time)
          // - else show pickupAt as "Pickup at"
          final readyAt = _asDateTime(data['readyAt']);
          final pickupAt = _asDateTime(data['pickupAt']);

          final showReadyAt = readyAt != null;
          final shownTime = showReadyAt ? readyAt : pickupAt;

          final paymentMethodRaw = _safeString(data, 'paymentMethod', fallback: '');
          final paymentStatusRaw = _safeString(data, 'paymentStatus', fallback: '');

          final paymentMethodText = _paymentMethodText(t, paymentMethodRaw);
          final paymentStatusText = _paymentStatusText(t, paymentStatusRaw);

          final items =
          (data['items'] is List) ? List.from(data['items']) : <dynamic>[];

          final cafeName = _safeString(data, 'cafeName', fallback: '');

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            children: [
              // Header: Order #
              Center(
                child: Text(
                  orderNumber > 0
                      ? "${t.staffOrderHash}$orderNumber"
                      : t.staffOrderDetailsTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 14),

              // Items
              _sectionTitle(t.staffItemsTitle(items.length)),
              const SizedBox(height: 8),
              _card(
                child: items.isEmpty
                    ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    t.staffNoItems,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                    : Column(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      _itemRow(t, items[i]),
                      if (i != items.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Customer
              _sectionTitle(t.staffCustomerTitle),
              const SizedBox(height: 8),
              _card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv(t.staffCustomerNameLabel, customerName),
                      if (customerPhone.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _phoneKv(
                          label: t.staffCustomerPhoneLabel,
                          phone: customerPhone,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cafe Details (minimal)
              _sectionTitle(t.staffCafeDetailsTitle),
              const SizedBox(height: 8),
              _card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // (Optional) cafe name
                      if (cafeName.isNotEmpty) ...[
                        _kv(t.staffCafeNameLabel, cafeName),
                        const SizedBox(height: 10),
                      ],
                      _kv(
                        showReadyAt ? t.staffReadyAtLabel : t.staffPickupAtLabel,
                        shownTime == null
                            ? t.staffTimeUnknown
                            : _formatTime(context, shownTime),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Order Status (only status)
              _sectionTitle(t.staffOrderStatusTitle),
              const SizedBox(height: 8),
              _card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _statusText(t, status),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      _statusBadge(t, status),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Payment Method (only method + paid/pending)
              _sectionTitle(t.staffPaymentMethodTitle),
              const SizedBox(height: 8),
              _card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          paymentMethodText,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      _pill(
                        text: paymentStatusText,
                        bg: (paymentStatusRaw.toLowerCase() == 'paid')
                            ? const Color(0xFFDFF5E7)
                            : const Color(0xFFFFF3CD),
                        fg: (paymentStatusRaw.toLowerCase() == 'paid')
                            ? const Color(0xFF1E7E34)
                            : const Color(0xFF8A6D00),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- Helpers ----------------

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.black.withOpacity(0.65),
        fontWeight: FontWeight.w900,
        fontSize: 13,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.04),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            k,
            style: TextStyle(
              color: Colors.black.withOpacity(0.55),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            v,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: _teal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneKv({
    required String label,
    required String phone,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.black.withOpacity(0.55),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 📞 phone number (one line)
              Text(
                phone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _teal,
                ),
              ),
              const SizedBox(height: 6),
              // 🔘 action icons under the number
              Row(
                children: [
                  IconButton(
                    tooltip: 'Call',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.call, size: 20),
                    color: _teal,
                    onPressed: () => _call(phone),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'WhatsApp',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.chat, size: 20),
                    color: Colors.green,
                    onPressed: () => _whatsApp(phone),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _whatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _itemRow(AppLocalizations t, dynamic it) {
    if (it is! Map) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(t.staffUnknownItem),
      );
    }

    final name = (it['name'] ?? it['title'] ?? '').toString().trim();
    final qty = _safeInt(it, 'qty', fallback: 1);

    final double lineTotal = _safeDouble(it, 'lineTotal', fallback: 0.0);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "x$qty ${name.isEmpty ? t.staffUnknownItem : name}",
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (lineTotal > 0)
            Text(
              t.staffSarAmount(lineTotal.toStringAsFixed(2)),
              style: const TextStyle(fontWeight: FontWeight.w900, color: _teal),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(AppLocalizations t, String status) {
    final s = status.toLowerCase();
    if (s == 'completed') {
      return _pill(
        text: t.staffStatusCompleted,
        bg: const Color(0xFFE6F4EA),
        fg: const Color(0xFF2E7D32),
      );
    }
    if (s == 'ready') {
      return _pill(
        text: t.staffStatusReady,
        bg: const Color(0xFFDFF5E7),
        fg: const Color(0xFF1E7E34),
      );
    }
    if (s == 'preparing') {
      return _pill(
        text: t.staffStatusPreparing,
        bg: const Color(0xFFFFF3CD),
        fg: const Color(0xFF8A6D00),
      );
    }
    if (s == 'cancelled') {
      return _pill(
        text: t.staffStatusCancelled,
        bg: const Color(0xFFEDEDED),
        fg: const Color(0xFF616161),
      );
    }
    return _pill(
    text: t.staffStatusNew,
    bg: const Color(0xFFFFE3E3),
    fg: const Color(0xFFD32F2F),
    );
  }

  Widget _pill({required String text, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }

  String _statusText(AppLocalizations t, String status) {
    final s = status.toLowerCase().trim();
    switch (s) {
      case 'placed':
        return t.staffStatusNew;
      case 'preparing':
        return t.staffStatusPreparing;
      case 'ready':
        return t.staffStatusReady;
      case 'completed':
        return t.staffStatusCompleted;
      case 'cancelled':
        return t.staffStatusCancelled;
      default:
        return s.isEmpty ? t.staffStatusNew : s;
    }
  }

  String _paymentMethodText(AppLocalizations t, String raw) {
    final v = raw.toLowerCase().trim();
    if (v == 'cash' || v == 'cod' || v == 'cash_on_pickup') return t.staffPayCashOnPickup;
    if (v == 'online' || v == 'card' || v == 'applepay' || v == 'googlepay') return t.staffPayOnline;
    return raw.isEmpty ? t.staffPayUnknown : raw;
  }

  String _paymentStatusText(AppLocalizations t, String raw) {
    final v = raw.toLowerCase().trim();
    if (v == 'paid') return t.staffPaid;
    if (v == 'pending' || v == 'unpaid') return t.staffPending;
    return raw.isEmpty ? t.staffPending : raw;
  }

  static String _safeString(Map data, String key, {String fallback = ''}) {
    final v = data[key];
    if (v == null) return fallback;
    return v.toString();
  }

  static int _safeInt(Map data, String key, {int fallback = 0}) {
    final v = data[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  static double _safeDouble(Map data, String key, {double fallback = 0.0}) {
    final v = data[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return fallback;
  }

  static DateTime? _asDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _formatTime(BuildContext context, DateTime dt) {
    final tod = TimeOfDay.fromDateTime(dt);
    final material = MaterialLocalizations.of(context);
    return material.formatTimeOfDay(tod, alwaysUse24HourFormat: false);
  }
}