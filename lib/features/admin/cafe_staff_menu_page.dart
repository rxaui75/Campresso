// cafe_staff_menu_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'cafe_staff_edit_product_page.dart';
import 'cafe_staff_add_product_page.dart';

class CafeStaffMenuPage extends StatefulWidget {
  final String cafeId;

  const CafeStaffMenuPage({
    super.key,
    required this.cafeId,
  });

  static const _teal = Color(0xFF0E6F73);

  @override
  State<CafeStaffMenuPage> createState() => _CafeStaffMenuPageState();
}

class _CafeStaffMenuPageState extends State<CafeStaffMenuPage> {
  int _tabIndex = 0;

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      FirebaseFirestore.instance
          .collection('cafes')
          .doc(widget.cafeId)
          .collection('products');

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
          t.staffMenuTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _productsRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("${t.error}: ${snap.error}"));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) return _emptyState(t);

          final catModels = _buildCategories(docs);
          if (catModels.isEmpty) return _emptyState(t);

          if (_tabIndex >= catModels.length) _tabIndex = 0;

          final selectedKey = catModels[_tabIndex].key;

          final filtered = docs.where((d) {
            final data = d.data();
            final key = _categoryKey(data);
            return key == selectedKey;
          }).toList();

          return Column(
            children: [
              const SizedBox(height: 6),
              _categoryTabs(t, catModels),
              const SizedBox(height: 12),
              _addItemButton(t),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text(t.staffMenuNoItemsInCategory))
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemBuilder: (context, i) => _productCard(t, filtered[i]),
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemCount: filtered.length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- Empty ----------------

  Widget _emptyState(AppLocalizations t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu, size: 42, color: Colors.black.withOpacity(0.25)),
            const SizedBox(height: 10),
            Text(
              t.staffMenuEmptyTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              t.staffMenuEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            _addItemButton(t),
          ],
        ),
      ),
    );
  }

  // ---------------- Tabs ----------------

  Widget _categoryTabs(AppLocalizations t, List<_CatModel> cats) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F3F3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(cats.length, (i) {
              final isActive = i == _tabIndex;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() => _tabIndex = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? CafeStaffMenuPage._teal : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      cats[i].label,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.black.withOpacity(0.55),
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ---------------- Add ----------------

  Widget _addItemButton(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          height: 38,
          child: ElevatedButton(
            onPressed: _goToAddItemPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: CafeStaffMenuPage._teal,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(
              t.staffMenuAddItem,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- Card ----------------

  Widget _productCard(AppLocalizations t, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final title = _pickLocalized(data, 'name');

    //  NEW: support both new storage images and old asset images
    final imageUrl = _safeString(data, 'imageUrl');
    final imageAsset = _safeString(data, 'imageAsset');

    final double basePrice = _safeNum(data, 'price', fallback: 0).toDouble();
    final int prep = _safeNum(data, 'prepMinutes', fallback: 0).toInt();

    final optionGroups = (data['optionGroups'] is List) ? List.from(data['optionGroups']) : <dynamic>[];
    final sizeLines = _extractOptionPriceLines(optionGroups, basePrice);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CafeStaffMenuPage._teal.withOpacity(0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 12),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _thumb(imageUrl: imageUrl, assetPath: imageAsset),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? t.staffMenuUnknownItem : title,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                  ),
                  const SizedBox(height: 6),

                  if (sizeLines.isNotEmpty) ...[
                    ...sizeLines.map(
                          (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                            color: Colors.black.withOpacity(0.65),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      "${t.staffMenuPriceLabel}: ${basePrice.toStringAsFixed(2)} ${t.sar}",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        color: Colors.black.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${t.staffMenuPrepLabel}: $prep ${t.min}",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        color: Colors.black.withOpacity(0.65),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: ElevatedButton(
                            onPressed: () => _goToEditItemPage(doc.id),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CafeStaffMenuPage._teal,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              t.staffMenuEditItem,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _deleteButton(t, doc.id, title),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ UPDATED: thumb supports network OR asset
  Widget _thumb({required String imageUrl, required String assetPath}) {
    final border = Border.all(color: Colors.black.withOpacity(0.08));

    Widget placeholder() {
      return Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(14),
          border: border,
        ),
        child: Icon(Icons.local_cafe, color: Colors.black.withOpacity(0.25)),
      );
    }

    // ✅ Prefer network image if available
    if (imageUrl.trim().isNotEmpty) {
      return Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          // loading (nice)
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
                      : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Center(
            child: Icon(Icons.image_not_supported, color: Colors.black.withOpacity(0.25)),
          ),
        ),
      );
    }

    // ✅ fallback to local asset (old products)
    if (assetPath.trim().isNotEmpty) {
      return Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(Icons.image_not_supported, color: Colors.black.withOpacity(0.25)),
          ),
        ),
      );
    }

    return placeholder();
  }

  Widget _deleteButton(AppLocalizations t, String docId, String title) {
    return SizedBox(
      width: 44,
      height: 44,
      child: OutlinedButton(
        onPressed: () => _confirmDelete(t, docId, title),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE74C3C),
          side: const BorderSide(color: Color(0xFFE74C3C), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.zero,
        ),
        child: const Icon(Icons.delete_outline, size: 22),
      ),
    );
  }

  // ---------------- Navigation ----------------

  void _goToAddItemPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CafeStaffAddProductPage(cafeId: widget.cafeId),
      ),
    );
  }

  Future<void> _goToEditItemPage(String productDocId) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CafeStaffEditProductPage(
          cafeId: widget.cafeId,
          productDocId: productDocId,
        ),
      ),
    );

    if (changed == true && mounted) {
      setState(() {});
    }
  }

  // ---------------- Delete ----------------

  Future<void> _confirmDelete(AppLocalizations t, String docId, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.staffMenuDeleteTitle),
        content: Text(
          title.isEmpty ? t.staffMenuDeleteBody : "${t.staffMenuDeleteBody}\n\n“$title”",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t.staffMenuDeleteConfirm,
              style: const TextStyle(color: Color(0xFFE74C3C), fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _productsRef.doc(docId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.staffMenuDeletedSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    }
  }

  // ---------------- Categories ----------------

  List<_CatModel> _buildCategories(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final map = <String, _CatModel>{};

    for (final d in docs) {
      final data = d.data();
      final key = _categoryKey(data);
      if (key.isEmpty) continue;

      final label = _pickLocalized(data, 'category').trim();
      final finalLabel = label.isNotEmpty ? label : key;

      map.putIfAbsent(key, () => _CatModel(key: key, label: finalLabel));
    }

    final list = map.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    if (list.isEmpty) {
      return [
        _CatModel(
          key: 'uncategorized',
          label: AppLocalizations.of(context)!.staffMenuUncategorized,
        )
      ];
    }

    return list;
  }

  String _categoryKey(Map<String, dynamic> data) {
    final catEn = _safeString(data, 'category_en').trim();
    final cat = _safeString(data, 'category').trim();
    return (catEn.isNotEmpty ? catEn : cat);
  }

  String _pickLocalized(Map<String, dynamic> data, String baseKey) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    if (lang.startsWith('ar')) {
      final ar = _safeString(data, '${baseKey}_ar');
      if (ar.isNotEmpty) return ar;
    } else {
      final en = _safeString(data, '${baseKey}_en');
      if (en.isNotEmpty) return en;
    }
    return _safeString(data, baseKey);
  }

  // ---------------- Option lines ----------------

  List<String> _extractOptionPriceLines(List<dynamic> optionGroups, double basePrice) {
    if (optionGroups.isEmpty) return [];

    Map? group;
    for (final g in optionGroups) {
      if (g is Map && g['options'] is List) {
        group = g;
        break;
      }
    }
    if (group == null) return [];

    final options = (group['options'] is List) ? List.from(group['options']) : <dynamic>[];
    if (options.isEmpty) return [];

    final lines = <String>[];
    for (final o in options) {
      if (o is! Map) continue;

      final name = (o['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final delta = _safeNum(o, 'priceDelta', fallback: 0).toDouble();
      final price = basePrice + delta;

      lines.add("$name: ${price.toStringAsFixed(2)} ${AppLocalizations.of(context)!.sar}");
      if (lines.length >= 3) break;
    }

    return lines;
  }

  // ---------------- Safe helpers ----------------

  static String _safeString(Map data, String key, {String fallback = ''}) {
    final v = data[key];
    if (v == null) return fallback;
    return v.toString();
  }

  static num _safeNum(Map data, String key, {num fallback = 0}) {
    final v = data[key];
    if (v is num) return v;
    return fallback;
  }
}

class _CatModel {
  final String key;
  final String label;
  _CatModel({required this.key, required this.label});
}