// orders_controller.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum OrderStatus { placed, preparing, readyToPickup, completed, cancelled }

OrderStatus _statusFromString(String s) {
  final v = s.toLowerCase().trim();
  if (v == "placed") return OrderStatus.placed;
  if (v == "preparing") return OrderStatus.preparing;
  if (v == "ready" || v == "readytopickup" || v == "ready_to_pickup") {
    return OrderStatus.readyToPickup;
  }
  if (v == "completed") return OrderStatus.completed;
  if (v == "cancelled" || v == "canceled") return OrderStatus.cancelled;
  return OrderStatus.placed;
}

String _statusToString(OrderStatus s) {
  switch (s) {
    case OrderStatus.placed:
      return "placed";
    case OrderStatus.preparing:
      return "preparing";
    case OrderStatus.readyToPickup:
      return "ready";
    case OrderStatus.completed:
      return "completed";
    case OrderStatus.cancelled:
      return "cancelled";
  }
}

class OrderItem {
  final String name;
  final String imageAsset;
  final int qty;

  // في Firestore عندك unitPrice + lineTotal
  final double unitPrice;
  final double lineTotalValue;

  const OrderItem({
    required this.name,
    required this.imageAsset,
    required this.qty,
    required this.unitPrice,
    required this.lineTotalValue,
  });

  double get lineTotal => lineTotalValue;

  factory OrderItem.fromMap(Map<String, dynamic> m) {
    final qty = (m["qty"] ?? 1) as int;
    final unitPrice = (m["unitPrice"] is num) ? (m["unitPrice"] as num).toDouble() : 0.0;

    // إذا lineTotal موجود (وهو موجود عندك) استخدميه
    // وإلا احسبيه
    final lt = (m["lineTotal"] is num)
        ? (m["lineTotal"] as num).toDouble()
        : unitPrice * qty;

    return OrderItem(
      name: (m["name"] ?? "") as String,
      imageAsset: (m["imageAsset"] ?? "") as String,
      qty: qty,
      unitPrice: unitPrice,
      lineTotalValue: lt,
    );
  }
}

class OrderModel {
  final String id;

  final String cafeId;
  final String cafeName;

  final DateTime createdAt;
  final DateTime pickupAt;

  final int etaMinutes;

  // ✅ مهم: لازم تكون مو final عشان OrderTrackingPage يغيّرها
  OrderStatus status;

  /// cash / apple / google / online
  final String paymentMethod;

  /// المبلغ النهائي المدفوع (عندك هو totalPrice في checkout)
  final double amountPaid;

  final List<OrderItem> items;

  OrderModel({
    required this.id,
    required this.cafeId,
    required this.cafeName,
    required this.createdAt,
    required this.pickupAt,
    required this.etaMinutes,
    required this.status,
    required this.paymentMethod,
    required this.amountPaid,
    required this.items,
  });

  // ======= Helpers للـ UI (OrderDetailsPage) =======

  /// نفس اللي انتي مستخدمته في OrderDetailsPage
  String get paymentLabel {
    final p = paymentMethod.toLowerCase().trim();
    if (p == "cash") return "Cash on delivery";
    if (p == "apple") return "Apple Pay";
    if (p == "google") return "Google Pay";
    if (p == "online") return "Online Pay";
    return paymentMethod; // fallback
  }

  bool get paid => paymentMethod.toLowerCase().trim() != "cash";

  /// عندك ما في خصم حالياً، نخليه 0 عشان UI ما يطيح
  double get discount => 0.0;

  /// subtotal = مجموع line totals
  double get subtotal {
    double s = 0.0;
    for (final it in items) {
      s += it.lineTotal;
    }
    return s;
  }

  /// total = amountPaid (اللي محفوظ في Firestore)
  double get total => amountPaid;

  // ======= Firestore mapping =======

  factory OrderModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    // createdAt من serverTimestamp ممكن يطلع null أول لحظة
    DateTime createdAt;
    final ca = data["createdAt"];
    if (ca is Timestamp) {
      createdAt = ca.toDate();
    } else {
      createdAt = DateTime.now();
    }

    DateTime pickupAt;
    final pa = data["pickupAt"];
    if (pa is Timestamp) {
      pickupAt = pa.toDate();
    } else {
      pickupAt = createdAt;
    }

    final itemsRaw = (data["items"] is List) ? (data["items"] as List) : const [];
    final items = itemsRaw
        .whereType<Map<String, dynamic>>()
        .map((m) => OrderItem.fromMap(m))
        .toList();

    return OrderModel(
      id: doc.id,
      cafeId: (data["cafeId"] ?? "") as String,
      cafeName: (data["cafeName"] ?? "") as String,
      createdAt: createdAt,
      pickupAt: pickupAt,
      etaMinutes: (data["estimatedMinutes"] ?? 0) as int,
      status: _statusFromString((data["status"] ?? "placed") as String),
      paymentMethod: (data["paymentMethod"] ?? "cash") as String,
      amountPaid: (data["amountPaid"] is num) ? (data["amountPaid"] as num).toDouble() : 0.0,
      items: items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "cafeId": cafeId,
      "cafeName": cafeName,
      "createdAt": Timestamp.fromDate(createdAt),
      "pickupAt": Timestamp.fromDate(pickupAt),
      "estimatedMinutes": etaMinutes,
      "status": _statusToString(status),
      "paymentMethod": paymentMethod,
      "amountPaid": amountPaid,
      "items": items.map((it) {
        return {
          "name": it.name,
          "imageAsset": it.imageAsset,
          "qty": it.qty,
          "unitPrice": it.unitPrice,
          "lineTotal": it.lineTotal,
        };
      }).toList(),
    };
  }
}

class OrdersController extends ChangeNotifier {
  OrdersController._();
  static final OrdersController instance = OrdersController._();

  final List<OrderModel> _current = [];
  final List<OrderModel> _previous = [];

  List<OrderModel> get current => List.unmodifiable(_current);
  List<OrderModel> get previous => List.unmodifiable(_previous);

  // ===== Local demo creation (إذا احتجتيه للتست بدون Firestore) =====
  OrderModel createLocalDemoOrder({
    required String cafeId,
    required String cafeName,
    required int etaMinutes,
    required String paymentMethod, // cash / apple / google
    required double amountPaid,
    required List<OrderItem> items,
  }) {
    final id = (10000 + Random().nextInt(89999)).toString();

    final order = OrderModel(
      id: id,
      cafeId: cafeId,
      cafeName: cafeName,
      createdAt: DateTime.now(),
      pickupAt: DateTime.now(),
      etaMinutes: etaMinutes,
      status: OrderStatus.placed,
      paymentMethod: paymentMethod,
      amountPaid: amountPaid,
      items: items,
    );

    _current.insert(0, order);
    notifyListeners();
    return order;
  }

  // ===== Firestore sync helpers =====
  void upsertFromFirestore(OrderModel order) {
    // شيل أي نسخة قديمة من القوائم
    _current.removeWhere((o) => o.id == order.id);
    _previous.removeWhere((o) => o.id == order.id);

    final isCurrent = order.status == OrderStatus.placed ||
        order.status == OrderStatus.preparing ||
        order.status == OrderStatus.readyToPickup;

    if (isCurrent) {
      _current.insert(0, order);
    } else {
      _previous.insert(0, order);
    }
    notifyListeners();
  }

  void setFromFirestoreList(List<OrderModel> orders) {
    _current.clear();
    _previous.clear();

    for (final o in orders) {
      final isCurrent = o.status == OrderStatus.placed ||
          o.status == OrderStatus.preparing ||
          o.status == OrderStatus.readyToPickup;

      if (isCurrent) {
        _current.add(o);
      } else {
        _previous.add(o);
      }
    }

    // ترتيب: الأحدث أول
    _current.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _previous.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    notifyListeners();
  }

  OrderModel? findById(String id) {
    for (final o in _current) {
      if (o.id == id) return o;
    }
    for (final o in _previous) {
      if (o.id == id) return o;
    }
    return null;
  }

  void markReadyToPickup(String id) {
    final o = findById(id);
    if (o == null) return;
    o.status = OrderStatus.readyToPickup;
    notifyListeners();
  }

  void completeOrder(String id) {
    final idx = _current.indexWhere((o) => o.id == id);
    if (idx < 0) return;
    final o = _current.removeAt(idx);
    o.status = OrderStatus.completed;
    _previous.insert(0, o);
    notifyListeners();
  }
}
