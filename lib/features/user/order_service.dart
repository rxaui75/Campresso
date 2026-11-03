// order_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cart_models.dart';

class OrderService {
  OrderService._();
  static final OrderService instance = OrderService._();

  int _generateOrderNumber() {
    return 10000 + (DateTime.now().millisecondsSinceEpoch % 90000);
  }

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      throw Exception("User not logged in (FirebaseAuth.currentUser is null)");
    }
    return u.uid;
  }

  String get _displayName {
    final u = FirebaseAuth.instance.currentUser;
    return (u?.displayName ?? '').trim();
  }

  Future<Map<String, dynamic>> _myUserProfile() async {
    final snap =
    await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    return snap.data() ?? {};
  }

  String _pickBestNameFromProfile(Map<String, dynamic> p) {
    final full = (p['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;

    final first = (p['firstName'] ?? '').toString().trim();
    final last = (p['lastName'] ?? '').toString().trim();
    final combined = [first, last].where((x) => x.isNotEmpty).join(' ').trim();
    if (combined.isNotEmpty) return combined;

    final dn = _displayName;
    if (dn.isNotEmpty) return dn;

    final email = (p['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;

    return "Customer";
  }

  String _makeDeliveryBarcode(String orderId, String uid) {
    final code = (orderId.hashCode ^ uid.hashCode).abs() % 100000000;
    return code.toString().padLeft(8, '0');
  }

  Future<String> createOrder({
    required String cafeId,
    required String cafeName,
    required DateTime pickupAt,
    required String transportMode, // walking/metro/delivery
    required String paymentMethod, // cash/online/wallet/pending
    required int estimatedMinutes,
    required double amountPaid, // cafe amount only
    required int itemsCount,
    required List<CartItem> items,

    String? fulfillment, // pickup | delivery
    String? deliveryStatus, // waiting | accepted | timeout | cancelled
    DateTime? deliveryExpireAt,
    double? deliveryTip,
    double? grandTotal,

    String? statusOverride, // placed | preparing | ...
  }) async {
    final orders = FirebaseFirestore.instance.collection('orders');
    final orderNumber = _generateOrderNumber();
    final doc = orders.doc();

    final derivedFulfillment = (fulfillment ??
        (transportMode.toLowerCase() == 'delivery'
            ? 'delivery'
            : 'pickup'))
        .toLowerCase();

    final derivedDeliveryStatus =
    derivedFulfillment == 'delivery' ? (deliveryStatus ?? 'waiting') : null;

    final derivedStatus = statusOverride ?? "placed";

    final myProfile = await _myUserProfile();
    final customerName = _pickBestNameFromProfile(myProfile);
    final customerPhone = (myProfile['phoneNumber'] ?? '').toString().trim();

    final tip = (deliveryTip ?? 0).toDouble();
    final gt = (grandTotal ?? amountPaid).toDouble();

    final cafeAmount = amountPaid.toDouble();
    final tipAmount = tip;

    final paidAmount = (derivedFulfillment == 'delivery') ? gt : cafeAmount;

    final pm = paymentMethod.toLowerCase().trim();

    // pending = not yet paid
    // cash / online / wallet = treated as paid in current flow
    final paymentStatusValue = (pm == 'pending') ? 'pending' : 'paid';

    final data = <String, dynamic>{
      "userId": _uid,
      "customerId": _uid,
      "orderNumber": orderNumber,

      "customerName": customerName,
      if (customerPhone.isNotEmpty) "customerPhone": customerPhone,

      "cafeId": cafeId,
      "cafeName": cafeName,

      "status": derivedStatus,
      "createdAt": FieldValue.serverTimestamp(),
      "pickupAt": Timestamp.fromDate(pickupAt),

      "transportMode": transportMode,

      "paymentMethod": paymentMethod,
      "paymentStatus": paymentStatusValue,

      "estimatedMinutes": estimatedMinutes,
      "itemsCount": itemsCount,

      "amountPaid": cafeAmount,
      "deliveryTip": tipAmount,
      "grandTotal": gt,
      "paidAmount": paidAmount,

      "cafeAmount": cafeAmount,
      "tipAmount": tipAmount,
      "tipStatus":
      (derivedFulfillment == 'delivery' && tipAmount > 0) ? "pending" : "none",

      "fulfillment": derivedFulfillment,
      if (derivedDeliveryStatus != null) "deliveryStatus": derivedDeliveryStatus,
      if (deliveryExpireAt != null)
        "deliveryExpireAt": Timestamp.fromDate(deliveryExpireAt),

      "items": items.map((it) {
        return {
          "productId": it.productId,
          "name": it.name,
          "imageAsset": it.imageAsset,
          "qty": it.qty,
          "unitPrice": it.unitPrice,
          "lineTotal": it.lineTotal,
          "prepMinutes": it.prepMinutes,
          "calories": it.calories,
          "selectedOptions": it.selectedOptions.map((o) {
            return {
              "groupId": o.groupId,
              "groupTitle": o.groupTitle,
              "optionId": o.optionId,
              "optionName": o.optionName,
              "qty": o.qty,
              "priceDelta": o.priceDelta,
            };
          }).toList(),
        };
      }).toList(),
    };

    await doc.set(data);
    return doc.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myOrdersStream({
    required bool current,
  }) {
    final base = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true);

    if (current) {
      return base.snapshots();
    } else {
      return base.snapshots();
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> waitingDeliveriesStream() {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('fulfillment', isEqualTo: 'delivery')
        .where('deliveryStatus', isEqualTo: 'waiting')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> acceptDelivery({required String orderId}) async {
    final myProfile = await _myUserProfile();
    final deliveryName = _pickBestNameFromProfile(myProfile);
    final deliveryPhone = (myProfile['phoneNumber'] ?? '').toString().trim();

    final barcode = _makeDeliveryBarcode(orderId, _uid);

    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      "deliveryStatus": "accepted",
      "deliveryPartnerId": _uid,
      "deliveryPartnerName": deliveryName.isEmpty ? "Delivery Girl" : deliveryName,
      if (deliveryPhone.isNotEmpty) "deliveryPartnerPhone": deliveryPhone,
      "deliveryPartnerBarcode": barcode,
      "acceptedAt": FieldValue.serverTimestamp(),
      "status": "preparing",
    });
  }

  Future<void> markDeliveryTimeout({required String orderId}) async {
    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      "deliveryStatus": "timeout",
    });
  }
}