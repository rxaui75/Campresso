// cart_models.dart
import 'dart:convert';

class CartSelectedOption {
  final String groupId;
  final String groupTitle;
  final String optionId;
  final String optionName;
  final int qty; // 1 for single, >1 for multi
  final double priceDelta;

  const CartSelectedOption({
    required this.groupId,
    required this.groupTitle,
    required this.optionId,
    required this.optionName,
    required this.qty,
    required this.priceDelta,
  });

  Map<String, dynamic> toJson() => {
    "groupId": groupId,
    "groupTitle": groupTitle,
    "optionId": optionId,
    "optionName": optionName,
    "qty": qty,
    "priceDelta": priceDelta,
  };

  static CartSelectedOption fromJson(Map<String, dynamic> m) {
    return CartSelectedOption(
      groupId: (m["groupId"] ?? "").toString(),
      groupTitle: (m["groupTitle"] ?? "").toString(),
      optionId: (m["optionId"] ?? "").toString(),
      optionName: (m["optionName"] ?? "").toString(),
      qty: (m["qty"] is num) ? (m["qty"] as num).toInt() : 1,
      priceDelta: (m["priceDelta"] is num) ? (m["priceDelta"] as num).toDouble() : 0.0,
    );
  }
}

class CartItem {
  final String key; // unique key = product + selections (so we can merge)
  final String cafeId;

  final String productId;
  final String name;
  final String imageAsset;

  final int calories;
  final int prepMinutes;

  final double basePrice;
  final List<CartSelectedOption> selectedOptions;

  int qty;

  CartItem({
    required this.key,
    required this.cafeId,
    required this.productId,
    required this.name,
    required this.imageAsset,
    required this.calories,
    required this.prepMinutes,
    required this.basePrice,
    required this.selectedOptions,
    required this.qty,
  });

  double get optionsTotalOneUnit {
    double t = 0;
    for (final o in selectedOptions) {
      t += o.priceDelta * o.qty;
    }
    return t;
  }

  double get unitPrice => basePrice + optionsTotalOneUnit;

  double get lineTotal => unitPrice * qty;

  Map<String, dynamic> toJson() => {
    "key": key,
    "cafeId": cafeId,
    "productId": productId,
    "name": name,
    "imageAsset": imageAsset,
    "calories": calories,
    "prepMinutes": prepMinutes,
    "basePrice": basePrice,
    "qty": qty,
    "selectedOptions": selectedOptions.map((e) => e.toJson()).toList(),
  };

  static CartItem fromJson(Map<String, dynamic> m) {
    return CartItem(
      key: (m["key"] ?? "").toString(),
      cafeId: (m["cafeId"] ?? "").toString(),
      productId: (m["productId"] ?? "").toString(),
      name: (m["name"] ?? "").toString(),
      imageAsset: (m["imageAsset"] ?? "").toString(),
      calories: (m["calories"] is num) ? (m["calories"] as num).toInt() : 0,
      prepMinutes: (m["prepMinutes"] is num) ? (m["prepMinutes"] as num).toInt() : 3,
      basePrice: (m["basePrice"] is num) ? (m["basePrice"] as num).toDouble() : 0.0,
      qty: (m["qty"] is num) ? (m["qty"] as num).toInt() : 1,
      selectedOptions: (m["selectedOptions"] is List)
          ? (m["selectedOptions"] as List)
          .whereType<Map>()
          .map((e) => CartSelectedOption.fromJson(Map<String, dynamic>.from(e)))
          .toList()
          : <CartSelectedOption>[],
    );
  }

  static String buildKey({
    required String cafeId,
    required String productId,
    required Map<String, dynamic> selections, // stable map
  }) {
    // make stable string for merging
    String stableJson(Map<String, dynamic> s) {
      final keys = s.keys.toList()..sort();
      final ordered = <String, dynamic>{};
      for (final k in keys) {
        final v = s[k];
        if (v is Map) {
          final vk = v.keys.toList()..sort();
          final vv = <String, dynamic>{};
          for (final kk in vk) {
            vv[kk.toString()] = v[kk];
          }
          ordered[k] = vv;
        } else {
          ordered[k] = v;
        }
      }
      return jsonEncode(ordered);
    }

    return "$cafeId|$productId|${stableJson(selections)}";
  }
}
