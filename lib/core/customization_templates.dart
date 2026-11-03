import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// ✅ Templates جاهزة لـ optionGroups
class CustomizationTemplates {
  // ---------- Common option groups ----------

  /// Sizes (Single select, required)
  static List<Map<String, dynamic>> sizeGroup({
    required String title,
    required List<Map<String, dynamic>> options,
  }) {
    return [
      {
        "id": "size",
        "title": title,
        "type": "single", // single / multi / counter
        "required": true,
        "maxSelect": 1,
        "options": options,
      }
    ];
  }

  /// Milk (Single select, optional)
  static Map<String, dynamic> milkGroup({
    String title = "Milk",
  }) {
    return {
      "id": "milk",
      "title": title,
      "type": "single",
      "required": false,
      "maxSelect": 1,
      "options": [
        {"id": "no_milk", "name": "No Milk", "priceDelta": 0},
        {"id": "full_fat", "name": "Full Fat Milk", "priceDelta": 0},
        {"id": "low_fat", "name": "Low Fat Milk", "priceDelta": 0},
        {"id": "coconut", "name": "Coconut Milk", "priceDelta": 1},
        {"id": "almond", "name": "Almond Milk", "priceDelta": 1},
      ],
    };
  }

  /// Additions (Multi select with max, counter style in UI later)
  static Map<String, dynamic> additionsGroup({
    String title = "Additions",
    int maxSelect = 2,
  }) {
    return {
      "id": "additions",
      "title": title,
      "type": "multi",
      "required": false,
      "maxSelect": maxSelect,
      "options": [
        {"id": "caramel", "name": "Caramel", "priceDelta": 3},
        {"id": "hazelnut", "name": "Hazelnut", "priceDelta": 3},
        {"id": "vanilla", "name": "Vanilla Syrup", "priceDelta": 3},
      ],
    };
  }

  // ---------- Dunkin specific templates ----------

  /// Template: Hot/Cold coffee drink like Americano/Cappuccino/Latte...
  static List<Map<String, dynamic>> dunkinDrinkStandard({
    required String sizeTitle,
    int additionsMax = 2,
    List<Map<String, dynamic>>? sizeOptions,
  }) {
    final sizes = sizeOptions ??
        const [
          {"id": "s", "name": "Small", "priceDelta": 0},
          {"id": "m", "name": "Medium", "priceDelta": 1},
          {"id": "l", "name": "Large", "priceDelta": 2},
        ];

    return [
      ...sizeGroup(title: sizeTitle, options: sizes),
      milkGroup(),
      additionsGroup(maxSelect: additionsMax),
    ];
  }

  /// Template: Box (Choose coffee type)
  static List<Map<String, dynamic>> dunkinBoxCoffeeType({
    String title = "Choose Coffee Type",
  }) {
    return [
      {
        "id": "coffee_type",
        "title": title,
        "type": "single",
        "required": true,
        "maxSelect": 1,
        "options": [
          {"id": "original", "name": "Original Coffee", "priceDelta": 0},
          {"id": "dark", "name": "Dark Roast Coffee", "priceDelta": 0},
        ],
      }
    ];
  }

  /// Template: Half dozen donuts - select exactly 6 (Counter type)
  static List<Map<String, dynamic>> dunkinHalfDozenDonuts({
    String title = "Choose The 6 Regular Donuts",
  }) {
    return [
      {
        "id": "donuts_pick_6",
        "title": title,
        "type": "counter",
        "required": true,
        "minSelect": 6,
        "maxSelect": 6,
        "options": [
          {"id": "choco_frosted", "name": "Choco Frosted", "priceDelta": 0},
          {"id": "glazed", "name": "Glazed Donut", "priceDelta": 0},
          {"id": "long_john", "name": "Long John", "priceDelta": 0},
          {"id": "boston_cream", "name": "Boston Cream", "priceDelta": 0},
          {"id": "pecan_crown", "name": "Pecan Crown", "priceDelta": 0},
          {"id": "old_fashioned", "name": "Old Fashioned Donut", "priceDelta": 0},
          {"id": "vanilla_sprinkle", "name": "Vanilla Candy Sprinkle", "priceDelta": 0},
        ],
      }
    ];
  }
}

/// ✅ دالة تحديث Firestore: تضيف optionGroups تلقائياً حسب المنتج
class CustomizationSeeder {
  static final _db = FirebaseFirestore.instance;

  /// شغليها مرة وحدة (Debug) لتعبئة optionGroups لمنتجات dunkin
  static Future<void> seedDunkinOptionGroups() async {
    final productsRef = _db.collection('cafes').doc('dunkin').collection('products');

    final snap = await productsRef.get();
    if (snap.docs.isEmpty) {
      debugPrint('⚠️ No products found under cafes/dunkin/products');
      return;
    }

    final batch = _db.batch();
    int updated = 0;
    int skipped = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      final name = (data['name'] ?? '').toString().toLowerCase();
      final category = (data['category'] ?? '').toString().toLowerCase();

      // لو أصلاً موجود optionGroups لا نلمسه (حتى ما نخرب شي)
      if (data.containsKey('optionGroups')) {
        skipped++;
        continue;
      }

      final optionGroups = _resolveDunkinOptionGroups(
        name: name,
        category: category,
      );

      if (optionGroups == null) {
        skipped++;
        continue;
      }

      batch.update(doc.reference, {
        'optionGroups': optionGroups,
        'optionsUpdatedAt': FieldValue.serverTimestamp(),
      });
      updated++;
    }

    await batch.commit();
    debugPrint('✅ optionGroups seeded for Dunkin. updated=$updated, skipped=$skipped');
  }

  /// منطق توزيع الـ customization
  static List<Map<String, dynamic>>? _resolveDunkinOptionGroups({
    required String name,
    required String category,
  }) {
    // 1) Box products
    if (name.contains('box')) {
      return CustomizationTemplates.dunkinBoxCoffeeType();
    }

    // 2) Half dozen / dozen donuts selection
    if (name.contains('half dozen')) {
      return CustomizationTemplates.dunkinHalfDozenDonuts();
    }

    // 3) Drinks: Hot/Cold beverages
    final isDrink = category.contains('hot beverages') || category.contains('cold beverages');
    if (isDrink) {
      // فرق بسيط: بعض المشروبات عندها إضافات أكثر
      final additionsMax = (name.contains('cappuccino') || name.contains('latte')) ? 4 : 2;

      // عنوان الـ size يطلع حلو حسب الاسم
      final pretty = _prettyTitleFromName(name);
      final sizeTitle = pretty.isEmpty ? "Choose Size" : "Choose $pretty Size";

      return CustomizationTemplates.dunkinDrinkStandard(
        sizeTitle: sizeTitle,
        additionsMax: additionsMax,
      );
    }

    // باقي المنتجات بدون customization حالياً
    return null;
  }

  static String _prettyTitleFromName(String name) {
    if (name.trim().isEmpty) return '';
    final words = name.split(' ');
    final capped = words.map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
    return capped;
  }
}
