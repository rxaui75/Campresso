// cafe_staff_add_product_page.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

// ✅ Manual crop INSIDE Flutter (no native activity)
import 'package:crop_your_image/crop_your_image.dart';

class CafeStaffAddProductPage extends StatefulWidget {
  final String cafeId;

  const CafeStaffAddProductPage({
    super.key,
    required this.cafeId,
  });

  static const _teal = Color(0xFF0E6F73);

  @override
  State<CafeStaffAddProductPage> createState() =>
      _CafeStaffAddProductPageState();
}

class _CafeStaffAddProductPageState extends State<CafeStaffAddProductPage> {
  CollectionReference<Map<String, dynamic>> get _colRef => FirebaseFirestore
      .instance
      .collection('cafes')
      .doc(widget.cafeId)
      .collection('products');

  final _formKey = GlobalKey<FormState>();

  // -------- Basic fields --------
  final _nameEn = TextEditingController();
  final _nameAr = TextEditingController();

  final _descEn = TextEditingController(); // optional
  final _descAr = TextEditingController(); // optional

  final _catEn = TextEditingController();
  final _catAr = TextEditingController();

  final _price = TextEditingController(); // base price fallback
  final _calories = TextEditingController(); // base product calories
  final _prepMinutes = TextEditingController();
  final _sortIndex = TextEditingController();

  bool _isActive = true;

  // ✅ Category picker state
  String? _selectedCategoryKey; // "en||ar"
  bool _addingNewCategory = false;

  // -------- Image upload state --------
  bool _uploadingImage = false;
  bool _pickingImage = false;
  String _imageUrl = '';
  String _imagePath = '';

  XFile? _pickedXFile;
  Uint8List? _pickedBytes;

  // -------- Sizes --------
  final List<_EditSize> _sizes = [];

  // -------- Option Groups / Additions --------
  final List<_EditOptionGroup> _groups = [];

  bool _saving = false;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    _descEn.dispose();
    _descAr.dispose();
    _catEn.dispose();
    _catAr.dispose();
    _price.dispose();
    _calories.dispose();
    _prepMinutes.dispose();
    _sortIndex.dispose();

    for (final s in _sizes) {
      s.nameCtrl.dispose();
      s.priceCtrl.dispose();
      s.caloriesCtrl.dispose();
    }

    for (final g in _groups) {
      g.titleEnCtrl.dispose();
      g.titleArCtrl.dispose();
      g.maxSelectCtrl.dispose();
      for (final o in g.options) {
        o.nameEnCtrl.dispose();
        o.nameArCtrl.dispose();
        o.priceDeltaCtrl.dispose();
        o.caloriesDeltaCtrl.dispose();
      }
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const pageBg = Color(0xFFF6F7FB);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          t.staffAddItemTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          children: [
            _imagePickerTopCard(t),
            const SizedBox(height: 14),

            _sectionHeader(t.staffAddBasicInformationTitle),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  _labeledField(
                    label: t.staffAddProductNameEn,
                    controller: _nameEn,
                    validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? t.staffEditRequiredField
                        : null,
                    hint: t.staffAddProductNameEnHint,
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    label: t.staffAddProductNameAr,
                    controller: _nameAr,
                    validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? t.staffEditRequiredField
                        : null,
                    hint: t.staffAddProductNameArHint,
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    label: t.staffAddDescriptionEnOptional,
                    controller: _descEn,
                    maxLines: 3,
                    hint: t.staffAddDescriptionEnHint,
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    label: t.staffAddDescriptionArOptional,
                    controller: _descAr,
                    maxLines: 3,
                    hint: t.staffAddDescriptionArHint,
                  ),
                  const SizedBox(height: 12),
                  _categoryPicker(t),
                  if (_addingNewCategory) ...[
                    const SizedBox(height: 12),
                    _labeledField(
                      label: t.staffAddCategoryEn,
                      controller: _catEn,
                      validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? t.staffEditRequiredField
                          : null,
                      hint: t.staffAddCategoryEnHint,
                    ),
                    const SizedBox(height: 12),
                    _labeledField(
                      label: t.staffAddCategoryAr,
                      controller: _catAr,
                      validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? t.staffEditRequiredField
                          : null,
                      hint: t.staffAddCategoryArHint,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(child: _sectionHeader(t.staffAddSizesPricesTitle)),
                TextButton.icon(
                  onPressed: _saving ? null : _addSize,
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                    color: CafeStaffAddProductPage._teal,
                  ),
                  label: Text(
                    t.staffAddAddSize,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: CafeStaffAddProductPage._teal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _card(
              child: Column(
                children: [
                  if (_sizes.isEmpty)
                    _softHintCard(t.staffAddNoSizesHint)
                  else
                    ..._sizes.map(
                          (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _sizeCard(t, s),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _labeledField(
                    label: t.staffAddBasePriceIfNoSizes,
                    controller: _price,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final hasSizes = _sizes.isNotEmpty;
                      if (hasSizes) return null;
                      if (v == null || v.trim().isEmpty) {
                        return t.staffAddBasePriceRequiredOrAddSizes;
                      }
                      return _isValidNum(v) ? null : t.staffEditInvalidNumber;
                    },
                    hint: t.staffAddBasePriceHint,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(child: _sectionHeader(t.staffEditCustomizationsTitle)),
                TextButton.icon(
                  onPressed: _saving ? null : _addGroup,
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                    color: CafeStaffAddProductPage._teal,
                  ),
                  label: Text(
                    t.staffEditAddGroup,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: CafeStaffAddProductPage._teal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_groups.isEmpty)
              _softHintCard(t.staffAddNoAddonsHint)
            else
              ..._groups.map(
                    (g) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _groupCard(t, g),
                ),
              ),

            const SizedBox(height: 14),

            _sectionHeader(t.staffAddOtherDetailsTitle),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  _labeledField(
                    label: t.staffAddCaloriesOptional,
                    controller: _calories,
                    keyboardType: TextInputType.number,
                    validator: (v) => _isValidInt(v, allowEmpty: true)
                        ? null
                        : t.staffEditInvalidNumber,
                    hint: t.staffAddCaloriesHint,
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    label: t.staffAddPrepMinutes,
                    controller: _prepMinutes,
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                    _isValidInt(v) ? null : t.staffEditInvalidNumber,
                    hint: t.staffAddPrepMinutesHint,
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    label: t.staffAddSortIndexOptional,
                    controller: _sortIndex,
                    keyboardType: TextInputType.number,
                    validator: (v) => _isValidInt(v, allowEmpty: true)
                        ? null
                        : t.staffEditInvalidNumber,
                    hint: t.staffAddSortIndexHint,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            _sectionHeader(t.staffAddProductAvailabilityTitle),
            const SizedBox(height: 10),
            _card(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.staffAddProductAvailabilityBody,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Switch(
                    value: _isActive,
                    activeColor: CafeStaffAddProductPage._teal,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _isActive = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : () => _save(t),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CafeStaffAddProductPage._teal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Text(
                        t.save,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE74C3C),
                        side: const BorderSide(color: Color(0xFFE74C3C)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        t.cancel,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Category Picker ----------------

  Widget _categoryPicker(AppLocalizations t) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _colRef.snapshots(),
      builder: (context, snap) {
        final opts = <_CategoryOption>[];

        if (snap.hasData) {
          final set = <String>{};
          for (final d in snap.data!.docs) {
            final data = d.data();
            final en = (data['category_en'] ?? '').toString().trim();
            final ar = (data['category_ar'] ?? '').toString().trim();

            if (en.isEmpty && ar.isEmpty) continue;

            final enFixed = en.isEmpty ? ar : en;
            final arFixed = ar.isEmpty ? en : ar;

            final key = "$enFixed||$arFixed";
            if (set.add(key)) {
              opts.add(_CategoryOption(en: enFixed, ar: arFixed));
            }
          }

          opts.sort((a, b) => a.en.toLowerCase().compareTo(b.en.toLowerCase()));
        }

        const addNewKey = "__ADD_NEW__";

        if (opts.isEmpty && !_addingNewCategory) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _addingNewCategory = true;
              _selectedCategoryKey = addNewKey;
              _catEn.clear();
              _catAr.clear();
            });
          });
        }

        final disabled = _saving || _uploadingImage || _pickingImage;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.staffAddCategorySelectLabel,
              style: TextStyle(
                color: Colors.black.withOpacity(0.62),
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedCategoryKey,
              isExpanded: true,
              decoration: _inputDeco(hint: t.staffAddCategorySelectHint),
              validator: (_) {
                if (_addingNewCategory) {
                  if (_catEn.text.trim().isEmpty || _catAr.text.trim().isEmpty) {
                    return t.staffEditRequiredField;
                  }
                  return null;
                }

                if (_selectedCategoryKey == null ||
                    _selectedCategoryKey!.trim().isEmpty) {
                  return t.staffEditRequiredField;
                }
                return null;
              },
              items: [
                if (opts.isNotEmpty)
                  ...opts.map((c) {
                    final key = c.key;
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(
                        "${c.en}  •  ${c.ar}",
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                  }),
                const DropdownMenuItem<String>(
                  enabled: false,
                  value: "__DIVIDER__",
                  child: Divider(height: 1),
                ),
                DropdownMenuItem<String>(
                  value: addNewKey,
                  child: Text(
                    t.staffAddCategoryAddNewOption,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
              onChanged: disabled
                  ? null
                  : (v) {
                if (v == null || v == "__DIVIDER__") return;

                if (v == addNewKey) {
                  setState(() {
                    _selectedCategoryKey = addNewKey;
                    _addingNewCategory = true;
                    _catEn.clear();
                    _catAr.clear();
                  });
                  return;
                }

                final parts = v.split("||");
                final en = parts.isNotEmpty ? parts[0] : '';
                final ar = parts.length > 1 ? parts[1] : '';

                setState(() {
                  _selectedCategoryKey = v;
                  _addingNewCategory = false;
                  _catEn.text = en;
                  _catAr.text = ar;
                });
              },
            ),
            if (!_addingNewCategory &&
                _selectedCategoryKey != null &&
                _selectedCategoryKey != addNewKey) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                child: Text(
                  t.staffAddCategorySelectedInfo(
                    _catEn.text.trim(),
                    _catAr.text.trim(),
                  ),
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.62),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // ---------------- UI blocks ----------------

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: CafeStaffAddProductPage._teal,
        fontWeight: FontWeight.w900,
        fontSize: 13,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _softHintCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.black.withOpacity(0.62),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  InputDecoration _inputDeco({required String hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: CafeStaffAddProductPage._teal,
          width: 1.4,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.black.withOpacity(0.62),
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          decoration: _inputDeco(hint: hint ?? ''),
        ),
      ],
    );
  }

  Widget _imagePickerTopCard(AppLocalizations t) {
    final hasImage = _pickedBytes != null;
    final disabled = _uploadingImage || _saving || _pickingImage;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: disabled ? null : () => _pickAndManualCrop(t),
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 10),
              color: Colors.black.withOpacity(0.05),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.black.withOpacity(0.18),
              width: 1.2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Center(
            child: _uploadingImage
                ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  t.staffAddUploading,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withOpacity(0.65),
                  ),
                ),
              ],
            )
                : _pickingImage
                ? Text(
              t.staffAddUploading,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black.withOpacity(0.65),
              ),
            )
                : hasImage
                ? Image.memory(
              _pickedBytes!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            )
                : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 28,
                  color: Colors.black.withOpacity(0.45),
                ),
                const SizedBox(height: 10),
                Text(
                  t.staffAddClickHere,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withOpacity(0.78),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.staffAddUploadHint,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sizeCard(AppLocalizations t, _EditSize s) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.nameCtrl.text.trim().isEmpty
                      ? t.staffAddAddSize
                      : s.nameCtrl.text.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: _saving ? null : () => setState(() => _sizes.remove(s)),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFE74C3C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _labeledField(
            label: t.staffAddSizeName,
            controller: s.nameCtrl,
            validator: (v) =>
            (v == null || v.trim().isEmpty)
                ? t.staffEditRequiredField
                : null,
            hint: t.staffAddSizeNameHint,
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffAddSizePriceSar,
            controller: s.priceCtrl,
            keyboardType: TextInputType.number,
            validator: (v) =>
            _isValidNum(v) ? null : t.staffEditInvalidNumber,
            hint: t.staffAddSizePriceHint,
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffAddCaloriesOptional,
            controller: s.caloriesCtrl,
            keyboardType: TextInputType.number,
            validator: (v) => _isValidInt(v, allowEmpty: true)
                ? null
                : t.staffEditInvalidNumber,
            hint: t.staffAddCaloriesHint,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.staffAddAvailable,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Switch(
                  value: s.isAvailable,
                  activeColor: CafeStaffAddProductPage._teal,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => s.isAvailable = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(AppLocalizations t, _EditOptionGroup g) {
    final titlePreview = g.titleEnCtrl.text.trim().isNotEmpty
        ? g.titleEnCtrl.text.trim()
        : (g.titleArCtrl.text.trim().isNotEmpty
        ? g.titleArCtrl.text.trim()
        : t.staffEditCustomizationGroup);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titlePreview,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
              IconButton(
                onPressed: _saving ? null : () => setState(() => _groups.remove(g)),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFE74C3C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _labeledField(
            label: t.staffEditGroupTitleEn,
            controller: g.titleEnCtrl,
            validator: (v) {
              if (g.titleEnCtrl.text.trim().isEmpty &&
                  g.titleArCtrl.text.trim().isEmpty) {
                return t.staffEditRequiredField;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffEditGroupTitleAr,
            controller: g.titleArCtrl,
            validator: (v) {
              if (g.titleEnCtrl.text.trim().isEmpty &&
                  g.titleArCtrl.text.trim().isEmpty) {
                return t.staffEditRequiredField;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _dropdownRow(
            label: t.staffEditGroupType,
            child: DropdownButtonFormField<String>(
              value: g.type,
              items: [
                DropdownMenuItem(
                  value: 'single',
                  child: Text(t.staffEditGroupTypeSingle),
                ),
                DropdownMenuItem(
                  value: 'multi',
                  child: Text(t.staffEditGroupTypeMulti),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                if (v == null) return;
                setState(() {
                  g.type = v;
                  if (g.type == 'single') {
                    g.maxSelectCtrl.text = '';
                  }
                });
              },
              decoration: _inputDeco(hint: ''),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.staffEditGroupRequired,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Switch(
                  value: g.required,
                  activeColor: CafeStaffAddProductPage._teal,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => g.required = v),
                ),
              ],
            ),
          ),
          if (g.type == 'multi') ...[
            const SizedBox(height: 12),
            _labeledField(
              label: t.staffEditGroupMaxSelectOptional,
              controller: g.maxSelectCtrl,
              keyboardType: TextInputType.number,
              validator: (v) => _isValidInt(v, allowEmpty: true)
                  ? null
                  : t.staffEditInvalidNumber,
              hint: t.staffEditGroupMaxSelectHint,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  t.staffEditOptionsTitle,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.70),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _saving ? null : () => _addOptionToGroup(g),
                icon: const Icon(
                  Icons.add,
                  size: 18,
                  color: CafeStaffAddProductPage._teal,
                ),
                label: Text(
                  t.staffEditAddOption,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: CafeStaffAddProductPage._teal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (g.options.isEmpty)
            _softHintCard(t.staffEditNoOptionsInGroup)
          else
            ...g.options.map(
                  (o) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _optionCard(t, g, o),
              ),
            ),
        ],
      ),
    );
  }

  Widget _optionCard(
      AppLocalizations t,
      _EditOptionGroup g,
      _EditOption o,
      ) {
    final preview = o.nameEnCtrl.text.trim().isNotEmpty
        ? o.nameEnCtrl.text.trim()
        : (o.nameArCtrl.text.trim().isNotEmpty
        ? o.nameArCtrl.text.trim()
        : t.staffEditOption);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  preview,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => g.options.remove(o)),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFE74C3C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _labeledField(
            label: t.staffEditOptionNameEn,
            controller: o.nameEnCtrl,
            validator: (v) {
              if (o.nameEnCtrl.text.trim().isEmpty &&
                  o.nameArCtrl.text.trim().isEmpty) {
                return t.staffEditRequiredField;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffEditOptionNameAr,
            controller: o.nameArCtrl,
            validator: (v) {
              if (o.nameEnCtrl.text.trim().isEmpty &&
                  o.nameArCtrl.text.trim().isEmpty) {
                return t.staffEditRequiredField;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffEditOptionPriceDelta,
            controller: o.priceDeltaCtrl,
            keyboardType: TextInputType.number,
            validator: (v) =>
            _isValidNum(v) ? null : t.staffEditInvalidNumber,
            hint: "0.0",
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffAddCaloriesOptional,
            controller: o.caloriesDeltaCtrl,
            keyboardType: TextInputType.number,
            validator: (v) => _isValidInt(v, allowEmpty: true)
                ? null
                : t.staffEditInvalidNumber,
            hint: t.staffAddCaloriesHint,
          ),
        ],
      ),
    );
  }

  Widget _dropdownRow({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.black.withOpacity(0.62),
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  // ---------------- Actions ----------------

  void _addSize() {
    setState(() {
      _sizes.add(
        _EditSize(
          name: '',
          price: 0.0,
          calories: null,
          isAvailable: true,
        ),
      );
    });
  }

  void _addGroup() {
    setState(() {
      _groups.add(
        _EditOptionGroup(
          id: '',
          type: 'single',
          required: false,
          maxSelect: null,
          titleEn: '',
          titleAr: '',
          options: [],
        ),
      );
    });
  }

  void _addOptionToGroup(_EditOptionGroup g) {
    setState(() {
      g.options.add(
        _EditOption(
          id: '',
          nameEn: '',
          nameAr: '',
          priceDelta: 0.0,
          caloriesDelta: null,
        ),
      );
    });
  }

  Future<void> _pickAndManualCrop(AppLocalizations t) async {
    if (_pickingImage || _saving || _uploadingImage) return;

    setState(() => _pickingImage = true);

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (!mounted) return;
      if (picked == null) return;

      final originalBytes = await picked.readAsBytes();

      final croppedBytes = await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (_) => _ManualCropPage(
            title: t.staffAddCropTitle,
            imageBytes: originalBytes,
          ),
        ),
      );

      if (!mounted) return;
      if (croppedBytes == null) return;

      setState(() {
        _pickedXFile = picked;
        _pickedBytes = croppedBytes;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    } finally {
      if (!mounted) return;
      setState(() => _pickingImage = false);
    }
  }

  Future<void> _uploadPickedImageIfAny(
      AppLocalizations t,
      String newDocId,
      ) async {
    if (_pickedBytes == null || _pickedBytes!.isEmpty) {
      throw Exception(t.staffAddImageRequired);
    }

    setState(() => _uploadingImage = true);

    try {
      const ext = 'jpg';
      final storagePath = "cafes/${widget.cafeId}/products/$newDocId/main.$ext";
      final ref = FirebaseStorage.instance.ref(storagePath);

      final metadata = SettableMetadata(contentType: 'image/jpeg');

      await ref.putData(_pickedBytes!, metadata);
      final url = await ref.getDownloadURL();

      _imageUrl = url;
      _imagePath = storagePath;
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _save(AppLocalizations t) async {
    if (!_formKey.currentState!.validate()) return;

    if (_pickedBytes == null || _pickedBytes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.staffAddImageRequired)),
      );
      return;
    }

    // Validate options manually
    for (final g in _groups) {
      for (final o in g.options) {
        if (o.nameEnCtrl.text.trim().isEmpty &&
            o.nameArCtrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.staffEditOptionNameRequired)),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);

    try {
      final docRef = _colRef.doc();
      final newId = docRef.id;

      await _uploadPickedImageIfAny(t, newId);

      final sizesPayload = _sizes.map((s) {
        return {
          'name': s.nameCtrl.text.trim(),
          'price': double.tryParse(s.priceCtrl.text.trim()) ?? 0.0,
          'calories': int.tryParse(s.caloriesCtrl.text.trim()) ?? 0,
          'isAvailable': s.isAvailable,
        };
      }).toList();

      final optionGroupsPayload = <Map<String, dynamic>>[];

      for (final g in _groups) {
        final titleEn = g.titleEnCtrl.text.trim();
        final titleAr = g.titleArCtrl.text.trim();

        final groupId = g.id.trim().isNotEmpty
            ? g.id.trim()
            : _slug(
          titleEn.isNotEmpty
              ? titleEn
              : (titleAr.isNotEmpty
              ? titleAr
              : 'group_${DateTime.now().millisecondsSinceEpoch}'),
        );

        final maxSelect = g.type == 'multi'
            ? (g.maxSelectCtrl.text.trim().isEmpty
            ? null
            : (int.tryParse(g.maxSelectCtrl.text.trim()) ?? 0))
            : null;

        final optionsPayload = <Map<String, dynamic>>[];
        for (final o in g.options) {
          final nameEn = o.nameEnCtrl.text.trim();
          final nameAr = o.nameArCtrl.text.trim();
          final optionId = o.id.trim().isNotEmpty
              ? o.id.trim()
              : _slug(
            nameEn.isNotEmpty
                ? nameEn
                : (nameAr.isNotEmpty
                ? nameAr
                : 'opt_${DateTime.now().millisecondsSinceEpoch}'),
          );

          optionsPayload.add({
            'id': optionId,
            'name_en': nameEn,
            'name_ar': nameAr,
            'name': nameEn.isNotEmpty ? nameEn : nameAr,
            'priceDelta': double.tryParse(o.priceDeltaCtrl.text.trim()) ?? 0.0,
            'caloriesDelta':
            int.tryParse(o.caloriesDeltaCtrl.text.trim()) ?? 0,
          });
        }

        optionGroupsPayload.add({
          'id': groupId,
          'type': g.type,
          'required': g.required,
          if (maxSelect != null) 'maxSelect': maxSelect,
          'title_en': titleEn,
          'title_ar': titleAr,
          'title': titleEn.isNotEmpty ? titleEn : titleAr,
          'options': optionsPayload,
        });
      }
      final sortText = _sortIndex.text.trim();

      final payload = <String, dynamic>{
        'name_en': _nameEn.text.trim(),
        'name_ar': _nameAr.text.trim(),
        'description_en': _descEn.text.trim(),
        'description_ar': _descAr.text.trim(),
        'category_en': _catEn.text.trim(),
        'category_ar': _catAr.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0.0,
        'calories': int.tryParse(_calories.text.trim()) ?? 0,
        'prepMinutes': int.tryParse(_prepMinutes.text.trim()) ?? 0,
        'sortIndex': sortText.isEmpty ? null : (int.tryParse(sortText) ?? 0),
        'isActive': _isActive,
        'imageUrl': _imageUrl.trim(),
        'imagePath': _imagePath.trim(),
        'sizes': sizesPayload,
        'optionGroups': optionGroupsPayload,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      payload.removeWhere((k, v) => v == null);

      await docRef.set(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.staffAddItemAddedSuccess)),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------- Utils ----------------

  bool _isValidNum(String? v) {
    if (v == null) return false;
    return double.tryParse(v.trim()) != null;
  }

  bool _isValidInt(String? v, {bool allowEmpty = false}) {
    if (v == null) return false;
    final s = v.trim();
    if (allowEmpty && s.isEmpty) return true;
    return int.tryParse(s) != null;
  }

  String _slug(String input) {
    final s = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'id_${DateTime.now().millisecondsSinceEpoch}' : s;
  }
}

// ---------------- Manual Crop Page ----------------

class _ManualCropPage extends StatefulWidget {
  final String title;
  final Uint8List imageBytes;

  const _ManualCropPage({
    required this.title,
    required this.imageBytes,
  });

  @override
  State<_ManualCropPage> createState() => _ManualCropPageState();
}

class _ManualCropPageState extends State<_ManualCropPage> {
  final _controller = CropController();
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _cropping
                ? null
                : () {
              setState(() => _cropping = true);
              _controller.crop();
            },
            child: _cropping
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : Text(
              t.staffAddCropDone,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Crop(
                image: widget.imageBytes,
                controller: _controller,
                aspectRatio: 1,
                interactive: true,
                onCropped: (Uint8List croppedData) {
                  if (!mounted) return;
                  Navigator.pop(context, croppedData);
                },
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _cropping
                          ? null
                          : () => Navigator.pop(context, null),
                      child: Text(
                        t.cancel,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Internal models ----------------

class _EditSize {
  bool isAvailable;
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController caloriesCtrl;

  _EditSize({
    required String name,
    required double price,
    required int? calories,
    required this.isAvailable,
  })  : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(text: price.toStringAsFixed(2)),
        caloriesCtrl = TextEditingController(
          text: calories == null ? '' : calories.toString(),
        );
}

class _EditOptionGroup {
  String id;
  String type; // single | multi
  bool required;

  final TextEditingController titleEnCtrl;
  final TextEditingController titleArCtrl;
  final TextEditingController maxSelectCtrl;

  final List<_EditOption> options;

  _EditOptionGroup({
    required this.id,
    required this.type,
    required this.required,
    required int? maxSelect,
    required String titleEn,
    required String titleAr,
    required this.options,
  })  : titleEnCtrl = TextEditingController(text: titleEn),
        titleArCtrl = TextEditingController(text: titleAr),
        maxSelectCtrl = TextEditingController(
          text: maxSelect == null ? '' : maxSelect.toString(),
        );
}

class _EditOption {
  String id;
  final TextEditingController nameEnCtrl;
  final TextEditingController nameArCtrl;
  final TextEditingController priceDeltaCtrl;
  final TextEditingController caloriesDeltaCtrl;

  _EditOption({
    required this.id,
    required String nameEn,
    required String nameAr,
    required double priceDelta,
    required int? caloriesDelta,
  })  : nameEnCtrl = TextEditingController(text: nameEn),
        nameArCtrl = TextEditingController(text: nameAr),
        priceDeltaCtrl = TextEditingController(
          text: priceDelta.toStringAsFixed(2),
        ),
        caloriesDeltaCtrl = TextEditingController(
          text: caloriesDelta == null ? '' : caloriesDelta.toString(),
        );
}

class _CategoryOption {
  final String en;
  final String ar;

  _CategoryOption({required this.en, required this.ar});

  String get key => "$en||$ar";
}