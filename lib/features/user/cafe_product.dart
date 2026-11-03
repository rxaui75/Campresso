class CafeProduct {
  final String id;
  final String cafeId;

  /// Optional bilingual product name/category/details
  final String? nameEn;
  final String? nameAr;
  final String? categoryEn;
  final String? categoryAr;
  final String? descriptionEn;
  final String? descriptionAr;

  /// Legacy / fallback
  final String name;
  final String category;
  final String description;

  final int calories;
  final int prepMinutes;
  final double price;
  final String imageAsset;

  /// Customization groups from Firestore
  final List<ProductOptionGroup> optionGroups;

  CafeProduct({
    required this.id,
    required this.cafeId,
    required this.name,
    required this.category,
    required this.description,
    required this.calories,
    required this.prepMinutes,
    required this.price,
    required this.imageAsset,
    this.optionGroups = const [],
    this.nameEn,
    this.nameAr,
    this.categoryEn,
    this.categoryAr,
    this.descriptionEn,
    this.descriptionAr,
  });

  bool get hasCustomizations => optionGroups.isNotEmpty;

  String nameFor(bool isAr) {
    return isAr ? (nameAr ?? name) : (nameEn ?? name);
  }

  String categoryFor(bool isAr) {
    return isAr ? (categoryAr ?? category) : (categoryEn ?? category);
  }

  String descriptionFor(bool isAr) {
    return isAr
        ? (descriptionAr?.isNotEmpty == true
        ? descriptionAr!
        : (descriptionEn?.isNotEmpty == true ? descriptionEn! : description))
        : (descriptionEn?.isNotEmpty == true
        ? descriptionEn!
        : (descriptionAr?.isNotEmpty == true ? descriptionAr! : description));
  }
}

class ProductOptionGroup {
  final String id;

  final String titleEn;
  final String titleAr;

  final String? titleLegacy;

  final bool required;
  final String type; // "single" | "multi"
  final int? maxSelect;
  final int? minSelect;

  final List<ProductOption> options;

  const ProductOptionGroup({
    required this.id,
    required this.titleEn,
    required this.titleAr,
    required this.required,
    required this.type,
    required this.options,
    this.maxSelect,
    this.minSelect,
    this.titleLegacy,
  });

  bool get isSingle => type.toLowerCase() == 'single';
  bool get isMulti => type.toLowerCase() == 'multi';

  String titleFor(bool isAr) {
    if (isAr) return titleAr.isNotEmpty ? titleAr : (titleLegacy ?? titleEn);
    return titleEn.isNotEmpty ? titleEn : (titleLegacy ?? titleAr);
  }

  static ProductOptionGroup fromMap(Map<String, dynamic> m) {
    final legacyTitle = (m['title'] ?? '').toString();

    final titleEn = (m['title_en'] ?? m['titleEn'] ?? legacyTitle).toString();
    final titleAr = (m['title_ar'] ?? m['titleAr'] ?? legacyTitle).toString();

    final optionsRaw = m['options'];

    final options = (optionsRaw is List)
        ? optionsRaw.map<ProductOption>((x) {
      final om =
      (x is Map) ? Map<String, dynamic>.from(x) : <String, dynamic>{};
      return ProductOption.fromMap(om);
    }).toList()
        : <ProductOption>[];

    return ProductOptionGroup(
      id: (m['id'] ?? '').toString(),
      titleEn: titleEn,
      titleAr: titleAr,
      titleLegacy: legacyTitle.isNotEmpty ? legacyTitle : null,
      required: (m['required'] ?? false) == true,
      type: (m['type'] ?? 'single').toString(),
      maxSelect:
      (m['maxSelect'] is num) ? (m['maxSelect'] as num).toInt() : null,
      minSelect:
      (m['minSelect'] is num) ? (m['minSelect'] as num).toInt() : null,
      options: options,
    );
  }
}

class ProductOption {
  final String id;

  final String nameEn;
  final String nameAr;

  final String? nameLegacy;

  final double priceDelta;
  final int? caloriesDelta;

  const ProductOption({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.priceDelta,
    this.caloriesDelta,
    this.nameLegacy,
  });

  String nameFor(bool isAr) {
    if (isAr) return nameAr.isNotEmpty ? nameAr : (nameLegacy ?? nameEn);
    return nameEn.isNotEmpty ? nameEn : (nameLegacy ?? nameAr);
  }

  static ProductOption fromMap(Map<String, dynamic> m) {
    final legacyName = (m['name'] ?? '').toString();
    final nameEn = (m['name_en'] ?? m['nameEn'] ?? legacyName).toString();
    final nameAr = (m['name_ar'] ?? m['nameAr'] ?? legacyName).toString();

    return ProductOption(
      id: (m['id'] ?? '').toString(),
      nameEn: nameEn,
      nameAr: nameAr,
      nameLegacy: legacyName.isNotEmpty ? legacyName : null,
      priceDelta: (m['priceDelta'] is num)
          ? (m['priceDelta'] as num).toDouble()
          : 0.0,
      caloriesDelta: (m['caloriesDelta'] is num)
          ? (m['caloriesDelta'] as num).toInt()
          : null,
    );
  }
}