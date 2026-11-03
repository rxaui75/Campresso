import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/flutter_gen/gen_l10n/app_localizations.dart';
import 'cart_controller.dart';
import 'cart_models.dart';

class ProductCustomizationSheet extends StatefulWidget {
  final String cafeId;
  final String productId;

  const ProductCustomizationSheet({
    super.key,
    required this.cafeId,
    required this.productId,
  });

  static Future<void> open(
      BuildContext context, {
        required String cafeId,
        required String productId,
      }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => ProductCustomizationSheet(
        cafeId: cafeId,
        productId: productId,
      ),
    );
  }

  @override
  State<ProductCustomizationSheet> createState() =>
      _ProductCustomizationSheetState();
}

class _ProductCustomizationSheetState extends State<ProductCustomizationSheet> {
  // groupId -> selected option id (single)
  final Map<String, String> _singleSelected = {};

  // groupId -> optionId -> qty (multi with +)
  final Map<String, Map<String, int>> _multiQty = {};

  // ✅ CHANGED: start from 0 instead of 1
  int _qty = 0;

  double _calcOptionsTotal(List<OptionGroup> groups) {
    double total = 0;

    for (final g in groups.where((x) => x.type == 'single')) {
      final selectedId = _singleSelected[g.id];
      if (selectedId == null || selectedId.isEmpty) continue;
      final opt = g.options.firstWhere(
            (o) => o.id == selectedId,
        orElse: () => const OptionItem(
          id: '',
          name: '',
          priceDelta: 0,
          caloriesDelta: 0,
        ),
      );
      total += opt.priceDelta;
    }

    for (final g in groups.where((x) => x.type == 'multi')) {
      final map = _multiQty[g.id] ?? {};
      for (final o in g.options) {
        final q = map[o.id] ?? 0;
        total += o.priceDelta * q;
      }
    }

    return total;
  }

  bool _validateRequired(List<OptionGroup> groups) {
    for (final g in groups.where((x) => x.required)) {
      if (g.type == 'single') {
        if ((_singleSelected[g.id] ?? '').isEmpty) return false;
      } else {
        final map = _multiQty[g.id] ?? {};
        final picked = map.values.fold<int>(0, (a, b) => a + b);
        if (picked != g.maxSelect) return false;
      }
    }
    return true;
  }

  int _pickedCount(OptionGroup g) {
    final map = _multiQty[g.id] ?? {};
    return map.values.fold<int>(0, (a, b) => a + b);
  }

  void _incMulti(OptionGroup g, OptionItem o) {
    final map = _multiQty.putIfAbsent(g.id, () => {});
    final picked = _pickedCount(g);
    if (picked >= g.maxSelect) return;
    map[o.id] = (map[o.id] ?? 0) + 1;
    setState(() {});
  }

  void _decMulti(OptionGroup g, OptionItem o) {
    final map = _multiQty[g.id] ?? {};
    final cur = map[o.id] ?? 0;
    if (cur <= 0) return;
    if (cur == 1) {
      map.remove(o.id);
    } else {
      map[o.id] = cur - 1;
    }
    setState(() {});
  }

  String _localizedText({
    required BuildContext context,
    required Map<String, dynamic> data,
    required String enKey,
    required String arKey,
    String fallbackKey = '',
  }) {
    final lang = Localizations.localeOf(context).languageCode;

    final en = (data[enKey] ?? '').toString().trim();
    final ar = (data[arKey] ?? '').toString().trim();
    final fallback =
    fallbackKey.isEmpty ? '' : (data[fallbackKey] ?? '').toString().trim();

    if (lang == 'ar') {
      if (ar.isNotEmpty) return ar;
      if (en.isNotEmpty) return en;
      return fallback;
    }

    if (en.isNotEmpty) return en;
    if (ar.isNotEmpty) return ar;
    return fallback;
  }

  void _addToCart({
    required String name,
    required String imageAsset,
    required int calories,
    required int prepMinutes,
    required double basePrice,
    required List<OptionGroup> groups,
  }) {
    final t = AppLocalizations.of(context)!;

    // ✅ NEW: do not add if qty is 0
    if (_qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.selectQuantityFirst)),
      );
      return;
    }

    final selections = <String, dynamic>{};
    final selectedOptions = <CartSelectedOption>[];

    for (final g in groups) {
      if (g.type == 'single') {
        final selectedId = _singleSelected[g.id] ?? '';
        selections[g.id] = selectedId;

        if (selectedId.isNotEmpty) {
          final opt = g.options.firstWhere(
                (o) => o.id == selectedId,
            orElse: () => const OptionItem(
              id: '',
              name: '',
              priceDelta: 0,
              caloriesDelta: 0,
            ),
          );
          if (opt.id.isNotEmpty) {
            selectedOptions.add(
              CartSelectedOption(
                groupId: g.id,
                groupTitle: g.title,
                optionId: opt.id,
                optionName: opt.name,
                qty: 1,
                priceDelta: opt.priceDelta,
              ),
            );
          }
        }
      } else {
        final map = _multiQty[g.id] ?? {};
        selections[g.id] = map;

        for (final o in g.options) {
          final q = map[o.id] ?? 0;
          if (q <= 0) continue;
          selectedOptions.add(
            CartSelectedOption(
              groupId: g.id,
              groupTitle: g.title,
              optionId: o.id,
              optionName: o.name,
              qty: q,
              priceDelta: o.priceDelta,
            ),
          );
        }
      }
    }

    final key = CartItem.buildKey(
      cafeId: widget.cafeId,
      productId: widget.productId,
      selections: selections,
    );

    final item = CartItem(
      key: key,
      cafeId: widget.cafeId,
      productId: widget.productId,
      name: name,
      imageAsset: imageAsset,
      calories: calories,
      prepMinutes: prepMinutes,
      basePrice: basePrice,
      selectedOptions: selectedOptions,
      qty: _qty,
    );

    CartController.instance.addOrMerge(item);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.addedToCart)),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0E6F73);
    final t = AppLocalizations.of(context)!;

    final docRef = FirebaseFirestore.instance
        .collection('cafes')
        .doc(widget.cafeId)
        .collection('products')
        .doc(widget.productId);

    return Container(
      decoration: const BoxDecoration(color: Colors.black54),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Material(
              color: Colors.white,
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: docRef.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text('${t.errorPrefix}: ${snap.error}'),
                    );
                  }

                  final data = snap.data!.data() ?? {};

                  final name = _localizedText(
                    context: context,
                    data: data,
                    enKey: 'name_en',
                    arKey: 'name_ar',
                    fallbackKey: 'name',
                  );

                  final details = _localizedText(
                    context: context,
                    data: data,
                    enKey: 'description_en',
                    arKey: 'description_ar',
                  );

                  final imageAsset = (data['imageAsset'] ?? '').toString();
                  final calories = (data['calories'] is num)
                      ? (data['calories'] as num).toInt()
                      : 0;
                  final prepMinutes = (data['prepMinutes'] is num)
                      ? (data['prepMinutes'] as num).toInt()
                      : 0;
                  final basePrice = (data['price'] is num)
                      ? (data['price'] as num).toDouble()
                      : 0.0;

                  final groups =
                  OptionGroup.fromDynamicList(data['optionGroups']);

                  final hasOptions = groups.isNotEmpty;
                  final optionsValid = hasOptions ? _validateRequired(groups) : true;

                  // ✅ NEW: add-to-cart requires quantity > 0 too
                  final canAdd = optionsValid && _qty > 0;

                  final optionsTotal =
                  hasOptions ? _calcOptionsTotal(groups) : 0.0;
                  final total = (basePrice + optionsTotal) * _qty;

                  return Stack(
                    children: [
                      ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          if (imageAsset.isNotEmpty)
                            Center(
                              child: Image.asset(
                                imageAsset,
                                height: 150,
                                fit: BoxFit.contain,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              details,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.black.withOpacity(0.68),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _pill('$calories ${t.cal}'),
                              const SizedBox(width: 8),
                              _pill('$prepMinutes ${t.minutes}'),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (!hasOptions)
                            Text(
                              t.noCustomization,
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.55),
                              ),
                            ),
                          if (hasOptions) ...[
                            for (final g in groups) ...[
                              _groupHeader(g, t),
                              const SizedBox(height: 10),
                              if (g.type == 'single') _singleGroup(g, t),
                              if (g.type == 'multi') _multiGroup(g, t),
                              const SizedBox(height: 18),
                            ],
                          ],
                        ],
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 18,
                                  offset: const Offset(0, -6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                _qtyControl(),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                      canAdd ? teal : Colors.grey,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: canAdd
                                        ? () => _addToCart(
                                      name: name,
                                      imageAsset: imageAsset,
                                      calories: calories,
                                      prepMinutes: prepMinutes,
                                      basePrice: basePrice,
                                      groups: groups,
                                    )
                                        : null,
                                    child: Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          t.addToCart,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '${total.toStringAsFixed(2)} SAR',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _qtyControl() {
    const teal = Color(0xFF0E6F73);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (_qty <= 0) return;
              setState(() => _qty--);
            },
            icon: const Icon(Icons.remove),
          ),
          Text(
            '$_qty',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          IconButton(
            onPressed: () => setState(() => _qty++),
            icon: const Icon(Icons.add, color: teal),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.black.withOpacity(0.65),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _calorieBadge(int calories, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EFFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: 16,
            color: Colors.black.withOpacity(0.55),
          ),
          const SizedBox(width: 6),
          Text(
            '$calories ${t.cal}',
            style: TextStyle(
              color: Colors.black.withOpacity(0.62),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(OptionGroup g, AppLocalizations t) {
    final req = g.required;
    String subtitle = '';

    if (g.type == 'multi') {
      subtitle = t.selectUpTo(g.maxSelect);
      if (req) subtitle = t.selectExact(g.maxSelect);
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                g.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (req)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              t.required,
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }

  Widget _singleGroup(OptionGroup g, AppLocalizations t) {
    final selected = _singleSelected[g.id];
    return Column(
      children: g.options.map((o) {
        final isSelected = selected == o.id;
        return InkWell(
          onTap: () => setState(() => _singleSelected[g.id] = o.id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (o.priceDelta > 0)
                      Text(
                        '+ ${o.priceDelta.toStringAsFixed(2)} SAR',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    const SizedBox(width: 10),
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 22,
                    ),
                  ],
                ),
                if (o.caloriesDelta > 0) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _calorieBadge(o.caloriesDelta, t),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _multiGroup(OptionGroup g, AppLocalizations t) {
    final picked = _pickedCount(g);
    final remaining = (g.maxSelect - picked).clamp(0, g.maxSelect);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (g.required)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              t.remaining(remaining),
              style: TextStyle(
                color: Colors.black.withOpacity(0.55),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ...g.options.map((o) {
          final map = _multiQty[g.id] ?? {};
          final q = map[o.id] ?? 0;

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (o.priceDelta > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '+ ${o.priceDelta.toStringAsFixed(2)} SAR',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    _plusMinus(
                      qty: q,
                      onPlus: () => _incMulti(g, o),
                      onMinus: () => _decMulti(g, o),
                    ),
                  ],
                ),
                if (o.caloriesDelta > 0) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _calorieBadge(o.caloriesDelta, t),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _plusMinus({
    required int qty,
    required VoidCallback onPlus,
    required VoidCallback onMinus,
  }) {
    return Row(
      children: [
        IconButton(
          onPressed: qty > 0 ? onMinus : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 22,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

/// ===== Models =====

class OptionGroup {
  final String id;
  final String title;
  final String type; // 'single' | 'multi'
  final bool required;
  final int maxSelect;
  final List<OptionItem> options;

  const OptionGroup({
    required this.id,
    required this.title,
    required this.type,
    required this.required,
    required this.maxSelect,
    required this.options,
  });

  static List<OptionGroup> fromDynamicList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map<OptionGroup>((e) {
      final m = (e is Map)
          ? Map<String, dynamic>.from(e)
          : <String, dynamic>{};

      final optsRaw = m['options'];
      final opts = (optsRaw is List)
          ? optsRaw.map<OptionItem>((x) {
        final om = (x is Map)
            ? Map<String, dynamic>.from(x)
            : <String, dynamic>{};
        return OptionItem(
          id: (om['id'] ?? '').toString(),
          name: (om['name'] ?? '').toString(),
          priceDelta: (om['priceDelta'] is num)
              ? (om['priceDelta'] as num).toDouble()
              : 0.0,
          caloriesDelta: (om['caloriesDelta'] is num)
              ? (om['caloriesDelta'] as num).toInt()
              : 0,
        );
      }).toList()
          : <OptionItem>[];

      return OptionGroup(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        type: (m['type'] ?? 'single').toString(),
        required: (m['required'] ?? false) == true,
        maxSelect: (m['maxSelect'] is num)
            ? (m['maxSelect'] as num).toInt()
            : 1,
        options: opts,
      );
    }).toList();
  }
}

class OptionItem {
  final String id;
  final String name;
  final double priceDelta;
  final int caloriesDelta;

  const OptionItem({
    required this.id,
    required this.name,
    required this.priceDelta,
    required this.caloriesDelta,
  });
}