// cart_controller.dart
import 'package:flutter/foundation.dart';
import 'cart_models.dart';

class CartController extends ChangeNotifier {
  CartController._();
  static final CartController instance = CartController._();

  // ✅ لكل كافيه سلة مستقلة
  final Map<String, List<CartItem>> _itemsByCafe = {};

  // ===== Helpers =====
  List<CartItem> _list(String cafeId) => _itemsByCafe.putIfAbsent(cafeId, () => []);

  List<CartItem> itemsFor(String cafeId) => List.unmodifiable(_itemsByCafe[cafeId] ?? const []);

  bool isEmptyFor(String cafeId) => (_itemsByCafe[cafeId]?.isEmpty ?? true);

  // ===== Counts / Totals =====
  int itemsCountFor(String cafeId) {
    final items = _itemsByCafe[cafeId] ?? const [];
    return items.fold<int>(0, (a, b) => a + b.qty);
  }

  double totalPriceFor(String cafeId) {
    final items = _itemsByCafe[cafeId] ?? const [];
    return items.fold<double>(0, (a, b) => a + b.lineTotal);
  }

  // Suggested: prep time as MAX (orders prepared in parallel)
  int prepTimeMinutesFor(String cafeId) {
    final items = _itemsByCafe[cafeId] ?? const [];
    if (items.isEmpty) return 0;
    int mx = 0;
    for (final i in items) {
      if (i.prepMinutes > mx) mx = i.prepMinutes;
    }
    return mx;
  }

  // ===== Clear / Remove =====
  void clearCafe(String cafeId) {
    _itemsByCafe.remove(cafeId);
    notifyListeners();
  }

  void removeByKey(String cafeId, String key) {
    final items = _itemsByCafe[cafeId];
    if (items == null) return;
    items.removeWhere((e) => e.key == key);
    if (items.isEmpty) _itemsByCafe.remove(cafeId);
    notifyListeners();
  }

  // ===== Qty ops =====
  void inc(String cafeId, String key) {
    final items = _itemsByCafe[cafeId];
    if (items == null) return;

    final idx = items.indexWhere((e) => e.key == key);
    if (idx < 0) return;

    items[idx].qty += 1;
    notifyListeners();
  }

  void dec(String cafeId, String key) {
    final items = _itemsByCafe[cafeId];
    if (items == null) return;

    final idx = items.indexWhere((e) => e.key == key);
    if (idx < 0) return;

    items[idx].qty -= 1;
    if (items[idx].qty <= 0) items.removeAt(idx);

    if (items.isEmpty) _itemsByCafe.remove(cafeId);
    notifyListeners();
  }

  void setItemQty(String cafeId, String key, int qty) {
    final items = _itemsByCafe[cafeId];
    if (items == null) return;

    final idx = items.indexWhere((e) => e.key == key);
    if (idx < 0) return;

    if (qty <= 0) {
      items.removeAt(idx);
    } else {
      items[idx].qty = qty;
    }

    if (items.isEmpty) _itemsByCafe.remove(cafeId);
    notifyListeners();
  }

  // ===== Add/Merge =====
  void addOrMerge(CartItem item) {
    // ✅ نحدد السلة حسب cafeId اللي داخل الـ item
    final items = _list(item.cafeId);

    final idx = items.indexWhere((e) => e.key == item.key);
    if (idx >= 0) {
      items[idx].qty += item.qty;
    } else {
      items.add(item);
    }
    notifyListeners();
  }

  void addItem(CartItem item) => addOrMerge(item);

  // =========================================
  // (اختياري) Backward compatibility
  // لو عندك أماكن قديمة بتنادي cart.items / cart.totalPrice بدون cafeId
  // خليها ترجع سلة أول كافيه (أو فاضية)
  // =========================================
  @Deprecated('Use itemsFor(cafeId)')
  List<CartItem> get items {
    if (_itemsByCafe.isEmpty) return const [];
    return List.unmodifiable(_itemsByCafe.values.first);
  }

  @Deprecated('Use itemsCountFor(cafeId)')
  int get itemsCount {
    if (_itemsByCafe.isEmpty) return 0;
    return _itemsByCafe.values.first.fold<int>(0, (a, b) => a + b.qty);
  }

  @Deprecated('Use totalPriceFor(cafeId)')
  double get totalPrice {
    if (_itemsByCafe.isEmpty) return 0.0;
    return _itemsByCafe.values.first.fold<double>(0, (a, b) => a + b.lineTotal);
  }

  @Deprecated('Use prepTimeMinutesFor(cafeId)')
  int get prepTimeMinutes {
    if (_itemsByCafe.isEmpty) return 0;
    final firstCafeId = _itemsByCafe.keys.first;
    return prepTimeMinutesFor(firstCafeId);
  }

  @Deprecated('Use clearCafe(cafeId)')
  void clear() {
    _itemsByCafe.clear();
    notifyListeners();
  }
}
