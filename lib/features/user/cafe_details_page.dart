import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'cafe_product.dart';
import 'cart_controller.dart';
import 'cart_models.dart';
import 'checkout_page.dart';

class CafeDetailsPage extends StatefulWidget {
  final String cafeId;
  final String cafeNameEn;
  final String cafeNameAr;
  final String cafeLogoAsset;
  final double distanceKm;
  final String crowdLevel; // Low / Medium / High

  /// ✅ NEW: from Ads (optional) - open specific product
  final String? highlightProductId;

  /// ✅ NEW: if true and highlightProductId found => open product sheet automatically
  final bool autoOpenProduct;

  /// ✅ NEW: from Ads (optional) - open a category tab only (e.g. "Donuts")
  /// Must match category_en used in products.
  final String? initialCategoryKey;

  const CafeDetailsPage({
    super.key,
    required this.cafeId,
    required this.cafeNameEn,
    required this.cafeNameAr,
    required this.cafeLogoAsset,
    required this.distanceKm,
    required this.crowdLevel,
    this.highlightProductId,
    this.autoOpenProduct = false,
    this.initialCategoryKey,
  });

  @override
  State<CafeDetailsPage> createState() => _CafeDetailsPageState();
}

class _CafeDetailsPageState extends State<CafeDetailsPage> {
  int selectedTab = 0;

  static const preferredOrder = [
    'Donuts & Coffee Boxes',
    'Hot Beverages',
    'Cold Beverages',
    'Donuts',
    'Sandwiches',
    'Water',
    'Sweets',
    'Matcha',
    'Smoothie',
    'Special Drinks',
  ];

  Map<String, String> _categoryLabels = {};

  // ✅ Cache: storagePath -> downloadUrl (avoids repeated network calls)
  final Map<String, String> _storageUrlCache = {};

  // ✅ NEW: scrolling + highlight
  final ScrollController _gridCtrl = ScrollController();
  final Map<String, GlobalKey> _productKeys = {};
  String? _highlightId;
  Timer? _highlightTimer;

  // ✅ Prevent repeating behaviors on rebuilds
  bool _didDeepLinkOnce = false;
  bool _didInitCategoryOnce = false;

  @override
  void dispose() {
    _gridCtrl.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  List<String> _buildCategories(List<_UiProduct> products, {required bool isAr}) {
    _categoryLabels = {};
    final keys = <String>{};

    for (final up in products) {
      final p = up.product;
      final key = (p.categoryEn?.trim().isNotEmpty == true)
          ? p.categoryEn!.trim()
          : p.category.trim();

      keys.add(key);

      final label = p.categoryFor(isAr);
      _categoryLabels[key] = label;
    }

    final ordered = preferredOrder.where((c) => keys.contains(c)).toList();
    final extras = keys.where((c) => !preferredOrder.contains(c)).toList();
    ordered.addAll(extras);

    if (ordered.isEmpty) {
      _categoryLabels['Menu'] = isAr ? 'القائمة' : 'Menu';
      return ['Menu'];
    }

    return ordered;
  }

  List<_UiProduct> _filterByCategory({
    required List<_UiProduct> products,
    required List<String> categories,
  }) {
    if (categories.isEmpty) return products;
    if (selectedTab >= categories.length) return products;

    final selectedKey = categories[selectedTab];
    if (selectedKey == 'Menu') return products;

    return products.where((up) {
      final p = up.product;
      final key = (p.categoryEn?.trim().isNotEmpty == true)
          ? p.categoryEn!.trim()
          : p.category.trim();
      return key == selectedKey;
    }).toList();
  }

  List<ProductOptionGroup> _parseOptionGroups(dynamic raw) {
    if (raw is! List) return const [];

    final groups = <ProductOptionGroup>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      groups.add(ProductOptionGroup.fromMap(m));
    }

    return groups.where((g) => g.options.isNotEmpty).toList();
  }

  _UiProduct _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final id = (d['id'] ?? doc.id).toString();
    final cafeId = (d['cafeId'] ?? widget.cafeId).toString();

    final nameEn = (d['name_en'] ?? d['nameEn'] ?? d['name'] ?? '')
        .toString()
        .trim();
    final nameAr = (d['name_ar'] ?? d['nameAr'] ?? '').toString().trim();

    final fallbackName =
    (nameEn.isNotEmpty ? nameEn : (nameAr.isNotEmpty ? nameAr : 'Unnamed'));
    final displayName = isAr
        ? (nameAr.isNotEmpty ? nameAr : fallbackName)
        : (nameEn.isNotEmpty ? nameEn : fallbackName);

    final categoryEn =
    (d['category_en'] ?? d['categoryEn'] ?? d['category'] ?? 'Menu')
        .toString()
        .trim();
    final categoryAr =
    (d['category_ar'] ?? d['categoryAr'] ?? '').toString().trim();
    final displayCategory =
    isAr ? (categoryAr.isNotEmpty ? categoryAr : categoryEn) : categoryEn;

    final calories = (d['calories'] is num) ? (d['calories'] as num).toInt() : 0;
    final prepMinutes =
    (d['prepMinutes'] is num) ? (d['prepMinutes'] as num).toInt() : 3;
    final price =
    (d['price'] is num) ? (d['price'] as num).toDouble() : 0.0;

    // Old products: imageAsset is stored (local asset path)
    final imageAsset = (d['imageAsset'] ?? widget.cafeLogoAsset).toString();

    // New staff products: Firestore fields
    final imageUrl = (d['imageUrl'] ?? '').toString().trim();
    final imagePath = (d['imagePath'] ?? '').toString().trim();

    final optionGroups = _parseOptionGroups(d['optionGroups']);

    final isActive = (d['isActive'] is bool) ? (d['isActive'] as bool) : true;
    final descriptionEn = (d['description_en'] ?? '').toString().trim();
    final descriptionAr = (d['description_ar'] ?? '').toString().trim();
    final description = (d['description'] ?? '').toString().trim();

    final product = CafeProduct(
      id: id,
      cafeId: cafeId,
      name: displayName,
      category: displayCategory,
      description: description,
      calories: calories,
      prepMinutes: prepMinutes,
      price: price,
      imageAsset: imageAsset,
      optionGroups: optionGroups,
      nameEn: nameEn.isEmpty ? null : nameEn,
      nameAr: nameAr.isEmpty ? null : nameAr,
      categoryEn: categoryEn.isEmpty ? null : categoryEn,
      categoryAr: categoryAr.isEmpty ? null : categoryAr,
      descriptionEn: descriptionEn.isEmpty ? null : descriptionEn,
      descriptionAr: descriptionAr.isEmpty ? null : descriptionAr,
    );

    return _UiProduct(
      product: product,
      isActive: isActive,
      imageUrl: imageUrl,
      imagePath: imagePath,
    );
  }

  Future<String?> _resolveStorageUrl(String storagePath) async {
    final p = storagePath.trim();
    if (p.isEmpty) return null;
    if (_storageUrlCache.containsKey(p)) return _storageUrlCache[p];

    final ref = FirebaseStorage.instance.ref(p);
    final url = await ref.getDownloadURL();
    _storageUrlCache[p] = url;
    return url;
  }

  void _openProductSheet(_UiProduct up) {
    final t = AppLocalizations.of(context)!;

    if (!up.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.cafeItemNotAvailableSnack)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductOverlaySheet(
        product: up.product,
        imageUrl: up.imageUrl,
        imagePath: up.imagePath,
        resolveStorageUrl: _resolveStorageUrl,
      ),
    );
  }

  void _handleInitialCategory({
    required List<String> categories,
  }) {
    if (_didInitCategoryOnce) return;

    final key = (widget.initialCategoryKey ?? '').trim();
    if (key.isEmpty) return;

    final idx = categories.indexOf(key);
    if (idx < 0) {
      _didInitCategoryOnce = true;
      return;
    }

    _didInitCategoryOnce = true;
    if (idx != selectedTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => selectedTab = idx);
      });
    }
  }

  void _handleDeepLink({
    required List<_UiProduct> allProducts,
    required List<String> categories,
    required bool isAr,
  }) {
    if (_didDeepLinkOnce) return;

    final targetId = (widget.highlightProductId ?? '').trim();
    if (targetId.isEmpty) return;

    final idxAll = allProducts.indexWhere((x) => x.product.id == targetId);
    if (idxAll < 0) return;

    _didDeepLinkOnce = true;

    final up = allProducts[idxAll];
    final p = up.product;

    final catKey = (p.categoryEn?.trim().isNotEmpty == true)
        ? p.categoryEn!.trim()
        : p.category.trim();

    final newTab = categories.indexOf(catKey);

    if (newTab >= 0 && newTab != selectedTab) {
      setState(() => selectedTab = newTab);
    }

    setState(() => _highlightId = targetId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _highlightId = null);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final key = _productKeys[targetId];
      final ctx = key?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOut,
          alignment: 0.15,
        );
      } else {
        if (_gridCtrl.hasClients) {
          _gridCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }

      if (widget.autoOpenProduct) {
        _openProductSheet(up);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    const teal = Color(0xFF2C7A7B);
    const brown = Color(0xFF7A4E2B);
    final lightBg = Colors.grey.shade100;

    final productsStream = FirebaseFirestore.instance
        .collection('cafes')
        .doc(widget.cafeId)
        .collection('products')
        .orderBy('category_en')
        .snapshots();

    final cafeTitle = isAr
        ? (widget.cafeNameAr.isEmpty ? widget.cafeNameEn : widget.cafeNameAr)
        : widget.cafeNameEn;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          cafeTitle,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: productsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  '${t.errorLoadingProducts}: ${snapshot.error}',
                  style: TextStyle(color: Colors.red.withOpacity(0.8)),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final products = docs.map(_fromDoc).toList();

          final categories = _buildCategories(products, isAr: isAr);
          if (selectedTab >= categories.length) selectedTab = 0;

          _handleInitialCategory(categories: categories);

          _productKeys.clear();

          final filteredProducts = _filterByCategory(
            products: products,
            categories: categories,
          );

          for (final up in filteredProducts) {
            _productKeys[up.product.id] = GlobalKey();
          }

          _handleDeepLink(allProducts: products, categories: categories, isAr: isAr);

          final selectedKey = categories[selectedTab];
          final selectedLabel = _categoryLabels[selectedKey] ?? selectedKey;

          return Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 2),
                  Center(
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Image.asset(
                            widget.cafeLogoAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) {
                              return Icon(
                                Icons.local_cafe,
                                size: 40,
                                color: Colors.black.withOpacity(0.25),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isAr
                        ? "${widget.cafeNameAr} - ${widget.cafeNameEn}"
                        : "${widget.cafeNameEn} - ${widget.cafeNameAr}",
                    style: const TextStyle(
                      color: teal,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _infoBox(
                        value: "${widget.distanceKm.toStringAsFixed(1)} km",
                        label: t.distance,
                        valueColor: brown,
                      ),
                      const SizedBox(width: 18),
                      Container(width: 1, height: 34, color: Colors.grey.shade300),
                      const SizedBox(width: 18),
                      _infoBox(
                        value: widget.crowdLevel,
                        label: t.crowdLevel,
                        valueColor: brown,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: lightBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Icon(Icons.chat_bubble_outline, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: lightBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: categories.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 6),
                              itemBuilder: (context, i) {
                                final selected = i == selectedTab;
                                final key = categories[i];
                                final label = _categoryLabels[key] ?? key;

                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => setState(() => selectedTab = i),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selected ? teal : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: selected ? Colors.white : Colors.black54,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Align(
                      alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(
                        selectedLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: GridView.builder(
                        controller: _gridCtrl,
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: filteredProducts.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemBuilder: (context, index) {
                          final up = filteredProducts[index];
                          final p = up.product;

                          final isHighlighted =
                          (_highlightId != null && _highlightId == p.id);
                          final key = _productKeys[p.id] ?? GlobalKey();
                          return KeyedSubtree(
                            key: key,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: isHighlighted
                                    ? Border.all(
                                  color: const Color(0xFF0E6F73),
                                  width: 2.2,
                                )
                                    : Border.all(
                                  color: Colors.transparent,
                                  width: 2.2,
                                ),
                              ),
                              child: _productCard(
                                t: t,
                                product: p,
                                isActive: up.isActive,
                                titleColor: brown,
                                priceColor: teal,
                                imageUrl: up.imageUrl,
                                imagePath: up.imagePath,
                                onTap: () => _openProductSheet(up),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 18,
                bottom: 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FloatingActionButton(
                      heroTag: "cartFab",
                      onPressed: () {
                        final cart = CartController.instance;
                        if (cart.isEmptyFor(widget.cafeId)) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CheckoutPage(
                              cafeId: widget.cafeId,
                              distanceKm: widget.distanceKm,
                              crowdLevel: widget.crowdLevel,
                            ),
                          ),
                        );
                      },
                      backgroundColor: teal,
                      child: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                    ),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedBuilder(
                          animation: CartController.instance,
                          builder: (_, __) {
                            final c = CartController.instance.itemsCountFor(widget.cafeId);
                            return Text(
                              "$c",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoBox({
    required String value,
    required String label,
    required Color valueColor,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _productCard({
    required AppLocalizations t,
    required CafeProduct product,
    required bool isActive,
    required Color titleColor,
    required Color priceColor,
    required String imageUrl,
    required String imagePath,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Opacity(
        opacity: isActive ? 1.0 : 0.45,
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _ProductImage(
                      assetPath: product.imageAsset,
                      imageUrl: imageUrl,
                      imagePath: imagePath,
                      resolveStorageUrl: _resolveStorageUrl,
                      iconSize: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _tinyRow(t.calories, "${product.calories} kcal"),
                  const SizedBox(height: 4),
                  _tinyRow(t.preparationTime, "${product.prepMinutes} ${t.minutes}"),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "${product.price.toStringAsFixed(2)} ${t.sar}",
                      style: TextStyle(
                        color: priceColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!isActive)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    t.cafeItemNotAvailableBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tinyRow(String left, String right) {
    const teal = Color(0xFF2C7A7B);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(left, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        Text(
          right,
          style: const TextStyle(
            color: teal,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _UiProduct {
  final CafeProduct product;
  final bool isActive;
  final String imageUrl;
  final String imagePath;

  const _UiProduct({
    required this.product,
    required this.isActive,
    required this.imageUrl,
    required this.imagePath,
  });
}

class _ProductImage extends StatelessWidget {
  final String assetPath;
  final String imageUrl;
  final String imagePath;
  final Future<String?> Function(String storagePath) resolveStorageUrl;
  final BoxFit fit;
  final double iconSize;

  const _ProductImage({
    required this.assetPath,
    required this.imageUrl,
    required this.imagePath,
    required this.resolveStorageUrl,
    required this.fit,
    required this.iconSize,
  });

  Widget _placeholder() {
    return Icon(
      Icons.local_cafe,
      size: iconSize,
      color: Colors.black.withOpacity(0.25),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isNotEmpty) {
      return Image.network(
        imageUrl.trim(),
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes == null
                    ? null
                    : (progress.cumulativeBytesLoaded /
                    (progress.expectedTotalBytes ?? 1)),
              ),
            ),
          );
        },
      );
    }

    if (imagePath.trim().isNotEmpty) {
      return FutureBuilder<String?>(
        future: resolveStorageUrl(imagePath.trim()),
        builder: (context, snap) {
          final url = snap.data;
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (url == null || url.isEmpty) return _placeholder();

          return Image.network(
            url,
            fit: fit,
            errorBuilder: (_, __, ___) => _placeholder(),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress.expectedTotalBytes == null
                        ? null
                        : (progress.cumulativeBytesLoaded /
                        (progress.expectedTotalBytes ?? 1)),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return Image.asset(
      assetPath,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }
}

/* ===================== Product Overlay Sheet ===================== */

class _ProductOverlaySheet extends StatefulWidget {
  final CafeProduct product;
  final String imageUrl;
  final String imagePath;
  final Future<String?> Function(String storagePath) resolveStorageUrl;

  const _ProductOverlaySheet({
    required this.product,
    required this.imageUrl,
    required this.imagePath,
    required this.resolveStorageUrl,
  });

  @override
  State<_ProductOverlaySheet> createState() => _ProductOverlaySheetState();
}

class _ProductOverlaySheetState extends State<_ProductOverlaySheet> {
  int qty = 0;

  final Map<String, String> _singleSelected = {};
  final Map<String, Map<String, int>> _multiQty = {};
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _loadInitialStateFromCart();
  }

  void _loadInitialStateFromCart() {
    final p = widget.product;
    final sameProductItems = _sameProductCartItems(p);

    if (sameProductItems.length == 1) {
      _applyCartItemToState(sameProductItems.first);
      return;
    }

    final existing = _findCurrentCartItem(p);
    if (existing != null) {
      _applyCartItemToState(existing);
    }
  }

  List<CartItem> _sameProductCartItems(CafeProduct p) {
    final items = CartController.instance.itemsFor(p.cafeId);
    return items.where((e) => e.productId == p.id).toList();
  }

  Map<String, dynamic> _buildSelectionsMap(CafeProduct p) {
    final selections = <String, dynamic>{};

    for (final g in p.optionGroups) {
      if (g.isSingle) {
        selections[g.id] = _singleSelected[g.id];
      } else {
        final raw = _multiQty[g.id] ?? {};
        selections[g.id] = Map<String, int>.fromEntries(
          raw.entries.where((e) => e.value > 0),
        );
      }
    }

    return selections;
  }

  String _currentCartKey(CafeProduct p) {
    return CartItem.buildKey(
      cafeId: p.cafeId,
      productId: p.id,
      selections: _buildSelectionsMap(p),
    );
  }

  CartItem? _findCurrentCartItem(CafeProduct p) {
    final key = _currentCartKey(p);
    final items = CartController.instance.itemsFor(p.cafeId);
    final idx = items.indexWhere((e) => e.key == key);
    if (idx < 0) return null;
    return items[idx];
  }

  void _applyCartItemToState(CartItem item) {
    _singleSelected.clear();
    _multiQty.clear();

    for (final sel in item.selectedOptions) {
      final group = widget.product.optionGroups
          .where((g) => g.id == sel.groupId)
          .cast<ProductOptionGroup?>()
          .firstWhere((g) => g != null, orElse: () => null);

      if (group == null) continue;

      if (group.isSingle) {
        _singleSelected[sel.groupId] = sel.optionId;
      } else {
        final map = _multiQty.putIfAbsent(sel.groupId, () => {});
        map[sel.optionId] = sel.qty;
      }
    }

    qty = item.qty;
    _validationError = null;
  }

  int _qtyForCurrentSelection(CafeProduct p) {
    final item = _findCurrentCartItem(p);
    return item?.qty ?? 0;
  }

  double _optionsTotal(CafeProduct p) {
    double total = 0.0;

    for (final g in p.optionGroups.where((x) => x.isSingle)) {
      final selId = _singleSelected[g.id];
      if (selId == null) continue;
      final opt = g.options
          .where((o) => o.id == selId)
          .cast<ProductOption?>()
          .firstWhere((o) => o != null, orElse: () => null);
      if (opt != null) total += opt.priceDelta;
    }

    for (final g in p.optionGroups.where((x) => x.isMulti)) {
      final m = _multiQty[g.id];
      if (m == null) continue;
      for (final e in m.entries) {
        final optId = e.key;
        final q = e.value;
        if (q <= 0) continue;
        final opt = g.options
            .where((o) => o.id == optId)
            .cast<ProductOption?>()
            .firstWhere((o) => o != null, orElse: () => null);
        if (opt != null) total += (opt.priceDelta * q);
      }
    }

    return total;
  }

  int _optionsCalories(CafeProduct p) {
    int total = 0;

    for (final g in p.optionGroups.where((x) => x.isSingle)) {
      final selId = _singleSelected[g.id];
      if (selId == null) continue;
      final opt = g.options
          .where((o) => o.id == selId)
          .cast<ProductOption?>()
          .firstWhere((o) => o != null, orElse: () => null);
      if (opt != null) {
        total += opt.caloriesDelta ?? 0;
      }
    }

    for (final g in p.optionGroups.where((x) => x.isMulti)) {
      final m = _multiQty[g.id];
      if (m == null) continue;
      for (final e in m.entries) {
        final optId = e.key;
        final q = e.value;
        if (q <= 0) continue;
        final opt = g.options
            .where((o) => o.id == optId)
            .cast<ProductOption?>()
            .firstWhere((o) => o != null, orElse: () => null);
        if (opt != null) {
          total += (opt.caloriesDelta ?? 0) * q;
        }
      }
    }

    return total;
  }

  int _finalCalories(CafeProduct p) {
    return p.calories + _optionsCalories(p);
  }

  double _finalPrice(CafeProduct p) {
    final base = p.price;
    final options = _optionsTotal(p);
    return (base + options) * qty;
  }

  bool _validate(CafeProduct p) {
    final t = AppLocalizations.of(context)!;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    if (qty <= 0) {
      _validationError = t.selectQuantityFirst;
      return false;
    }

    for (final g in p.optionGroups.where((x) => x.isSingle)) {
      if (g.required && (_singleSelected[g.id] == null)) {
        _validationError = '${t.pleaseChoose}: ${g.titleFor(isAr)}';
        return false;
      }
    }

    for (final g in p.optionGroups.where((x) => x.isMulti)) {
      final m = _multiQty[g.id] ?? {};
      final selectedCount =
      m.values.fold<int>(0, (a, b) => a + (b > 0 ? b : 0));

      if (g.required && selectedCount == 0) {
        _validationError = '${t.pleaseChoose}: ${g.titleFor(isAr)}';
        return false;
      }

      final maxSel = g.maxSelect;
      if (maxSel != null && selectedCount > maxSel) {
        _validationError = '${t.maxOptions}: $maxSel • ${g.titleFor(isAr)}';
        return false;
      }
    }

    _validationError = null;
    return true;
  }

  Future<void> _submit(CafeProduct p, bool isAr) async {
    final t = AppLocalizations.of(context)!;
    final existing = _findCurrentCartItem(p);
    final key = _currentCartKey(p);
    if (qty <= 0 && existing != null) {
      CartController.instance.removeByKey(p.cafeId, key);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.removedFromCart)),
      );
      return;
    }
    if (!_validate(p)) {
      setState(() {});
      return;}
    final selections = _buildSelectionsMap(p);
    final selectedOptions = <CartSelectedOption>[];

    for (final g in p.optionGroups) {
      if (g.isSingle) {
        final selectedId = _singleSelected[g.id];
        if (selectedId != null && selectedId.isNotEmpty) {
          final opt = g.options.firstWhere((o) => o.id == selectedId);
          selectedOptions.add(
            CartSelectedOption(
              groupId: g.id,
              groupTitle: g.titleFor(isAr),
              optionId: opt.id,
              optionName: opt.nameFor(isAr),
              qty: 1,
              priceDelta: opt.priceDelta,
            ),
          );
        }
      } else {
        final map = _multiQty[g.id] ?? {};
        for (final opt in g.options) {
          final q = map[opt.id] ?? 0;
          if (q <= 0) continue;
          selectedOptions.add(
            CartSelectedOption(
              groupId: g.id,
              groupTitle: g.titleFor(isAr),
              optionId: opt.id,
              optionName: opt.nameFor(isAr),
              qty: q,
              priceDelta: opt.priceDelta,),);}
      }
    }
    if (existing == null) {
      final bestImageRef = (widget.imageUrl.trim().isNotEmpty)
          ? widget.imageUrl.trim()
          : (widget.imagePath.trim().isNotEmpty)
          ? widget.imagePath.trim()
          : p.imageAsset;
      final item = CartItem(
        key: key,
        cafeId: p.cafeId,
        productId: p.id,
        name: p.nameFor(isAr),
        imageAsset: bestImageRef,
        calories: _finalCalories(p),
        prepMinutes: p.prepMinutes,
        basePrice: p.price,
        selectedOptions: selectedOptions,
        qty: qty,
      );
      CartController.instance.addOrMerge(item);

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.addedToCart)),
      );
      return;
    }
    final diff = qty - existing.qty;

    if (diff > 0) {
      for (int i = 0; i < diff; i++) {
        CartController.instance.inc(p.cafeId, key);
      }
    } else if (diff < 0) {
      for (int i = 0; i < diff.abs(); i++) {
        CartController.instance.dec(p.cafeId, key);
      }
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.cartUpdated)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final p = widget.product;
    final totalCalories = _finalCalories(p);
    final existing = _findCurrentCartItem(p);
    final canSubmit = qty > 0 || existing != null;

    final String ctaText;
    if (existing != null && qty == 0) {
      ctaText = t.removeFromCart;
    } else if (existing != null) {
      ctaText = t.updateCart;
    } else {
      ctaText = t.addToCart;
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
                  children: [
                    Center(
                      child: SizedBox(
                        height: 180,
                        child: _ProductImage(
                          assetPath: p.imageAsset,
                          imageUrl: widget.imageUrl,
                          imagePath: widget.imagePath,
                          resolveStorageUrl: widget.resolveStorageUrl,
                          fit: BoxFit.contain,
                          iconSize: 80,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      p.nameFor(isAr),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (p.descriptionFor(isAr).trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        p.descriptionFor(isAr),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.black.withOpacity(0.68),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _caloriesBadge(totalCalories, t),
                        _pill("${p.prepMinutes} ${t.min}"),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_validationError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _validationError!,
                          style: TextStyle(
                            color: Colors.red.withOpacity(0.85),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (!p.hasCustomizations)
                      Text(
                        t.noCustomizations,
                        style: TextStyle(color: Colors.black.withOpacity(0.55)),
                      ),
                    for (final g in p.optionGroups) ...[
                      _GroupHeader(
                        title: g.titleFor(isAr),
                        required: g.required,
                        subtitle: g.isMulti && g.maxSelect != null
                            ? "${t.youCanAddUpTo} ${g.maxSelect} ${t.options}"
                            : null,
                      ),
                      const SizedBox(height: 10),
                      if (g.isSingle) _buildSingleGroup(g, isAr: isAr),
                      if (g.isMulti) _buildMultiGroup(g, isAr: isAr),
                      const SizedBox(height: 18),
                      Divider(color: Colors.black.withOpacity(0.07)),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 18,
                        color: Colors.black.withOpacity(0.08),
                        offset: const Offset(0, -6),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      _qtyButton(
                        icon: Icons.remove,
                        onTap: () => setState(() {
                          if (qty > 0) qty--;
                          _validationError = null;
                        }),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          "$qty",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _qtyButton(
                        icon: Icons.add,
                        onTap: () => setState(() {
                          qty++;
                          _validationError = null;
                        }),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canSubmit
                                ? const Color(0xFF0E6F73)
                                : Colors.grey,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: canSubmit ? () => _submit(p, isAr) : null,
                          child: Text(
                            (existing != null && qty == 0)
                                ? ctaText
                                : "$ctaText • ${_finalPrice(p).toStringAsFixed(2)} ${t.sar}",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSingleGroup(ProductOptionGroup g, {required bool isAr}) {
    final selectedId = _singleSelected[g.id];
    final t = AppLocalizations.of(context)!;

    return Column(
      children: g.options.map((o) {
        final selected = selectedId == o.id;

        return InkWell(
          onTap: () => setState(() {
            _singleSelected[g.id] = o.id;
            qty = _qtyForCurrentSelection(widget.product);
            _validationError = null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    o.nameFor(isAr),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _optionMeta(o, t),
                const SizedBox(width: 12),
                _RadioCircle(selected: selected),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultiGroup(ProductOptionGroup g, {required bool isAr}) {
    final m = _multiQty.putIfAbsent(g.id, () => {});
    final maxSel = g.maxSelect;
    final t = AppLocalizations.of(context)!;

    int selectedCount() {
      return m.values.fold<int>(0, (a, b) => a + (b > 0 ? b : 0));
    }

    bool canAddMore() {
      if (maxSel == null) return true;
      return selectedCount() < maxSel;
    }

    return Column(
      children: g.options.map((o) {
        final q = m[o.id] ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  o.nameFor(isAr),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _optionMeta(o, t),
              const SizedBox(width: 12),
              if (q > 0)
                _CircleBtn(
                  icon: Icons.remove,
                  onTap: () => setState(() {
                    final newQ = (m[o.id] ?? 0) - 1;
                    if (newQ <= 0) {
                      m.remove(o.id);
                    } else {
                      m[o.id] = newQ;
                    }
                    qty = _qtyForCurrentSelection(widget.product);
                    _validationError = null;
                  }),
                )
              else
                const SizedBox(width: 40),
              if (q > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    "$q",
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                )
              else
                const SizedBox(width: 28),
              _CircleBtn(
                icon: Icons.add,
                onTap: () => setState(() {
                  if (!canAddMore()) {
                    _validationError =
                    '${t.maxOptions}: ${maxSel ?? ''} • ${g.titleFor(isAr)}';
                    return;
                  }
                  m[o.id] = (m[o.id] ?? 0) + 1;
                  qty = _qtyForCurrentSelection(widget.product);
                  _validationError = null;
                }),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _optionMeta(ProductOption o, AppLocalizations t) {
    final hasPrice = o.priceDelta > 0;
    final hasCalories = (o.caloriesDelta ?? 0) > 0;

    if (!hasPrice && !hasCalories) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasPrice)
          Text(
            '+ ${o.priceDelta.toStringAsFixed(2)} SAR',
            style: TextStyle(
              color: Colors.black.withOpacity(0.6),
              fontWeight: FontWeight.w800,
            ),
          ),
        if (hasCalories) ...[
          if (hasPrice) const SizedBox(height: 6),
          _miniCaloriesBadge(o.caloriesDelta ?? 0, t),
        ],
      ],
    );
  }

  Widget _caloriesBadge(int calories, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4DAAF).withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: 18,
            color: Colors.black.withOpacity(0.55),
          ),
          const SizedBox(width: 6),
          Text(
            '$calories ${t.cal}',
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCaloriesBadge(int calories, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF4DAAF).withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: 14,
            color: Colors.black.withOpacity(0.5),
          ),
          const SizedBox(width: 4),
          Text(
            '$calories ${t.cal}',
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4F1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _qtyButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final bool required;
  final String? subtitle;

  const _GroupHeader({
    required this.title,
    required this.required,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(color: Colors.black.withOpacity(0.45)),
                ),
              ],
            ],
          ),
        ),
        if (required)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE7C2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              t.required,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFFB8741A),
              ),
            ),
          ),
      ],
    );
  }
}

class _RadioCircle extends StatelessWidget {
  final bool selected;
  const _RadioCircle({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF0E6F73) : Colors.black.withOpacity(0.25),
          width: 2,
        ),
      ),
      child: selected
          ? Center(
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0xFF0E6F73),
            shape: BoxShape.circle,
          ),
        ),
      )
          : null,
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon),
      ),
    );
  }
}