// cafe_staff_edit_product_page.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class CafeStaffEditProductPage extends StatefulWidget {
  final String cafeId;
  final String productDocId;

  const CafeStaffEditProductPage({
    super.key,
    required this.cafeId,
    required this.productDocId,
  });

  static const _teal = Color(0xFF0E6F73);

  @override
  State<CafeStaffEditProductPage> createState() =>
      _CafeStaffEditProductPageState();
}

class _CafeStaffEditProductPageState
    extends State<CafeStaffEditProductPage> {
  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore
      .instance
      .collection('cafes')
      .doc(widget.cafeId)
      .collection('products')
      .doc(widget.productDocId);

  final _formKey = GlobalKey<FormState>();

  // Basic controllers
  final _nameEn = TextEditingController();
  final _nameAr = TextEditingController();

  final _descEn = TextEditingController();
  final _descAr = TextEditingController();

  final _catEn = TextEditingController();
  final _catAr = TextEditingController();

  final _price = TextEditingController();
  final _calories = TextEditingController();
  final _prepMinutes = TextEditingController();
  final _sortIndex = TextEditingController();

  bool _isActive = true;

  // Image state
  bool _uploadingImage = false;
  String _imageUrl = '';
  String _imagePath = '';
  String _imageAsset = '';

  bool _saving = false;

  // Sizes
  final List<_EditSize> _sizes = [];

  // Option groups
  final List<_EditOptionGroup> _groups = [];

  bool _didHydrate = false;

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
          t.staffEditProductTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(t),
            child: Text(
              t.save,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color:
                _saving ? Colors.black26 : CafeStaffEditProductPage._teal,
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("${t.error}: ${snap.error}"));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data();
          if (data == null) {
            return Center(child: Text(t.staffEditProductNotFound));
          }

          _hydrateOnce(data);

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
              children: [
                _sectionHeader(t.staffEditBasicInfoTitle),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    children: [
                      _labeledField(
                        label: t.staffEditNameEn,
                        controller: _nameEn,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t.staffEditRequiredField
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _labeledField(
                        label: t.staffEditNameAr,
                        controller: _nameAr,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t.staffEditRequiredField
                            : null,
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
                      _labeledField(
                        label: t.staffEditCategoryEn,
                        controller: _catEn,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t.staffEditRequiredField
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _labeledField(
                        label: t.staffEditCategoryAr,
                        controller: _catAr,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t.staffEditRequiredField
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _imagePickerBox(t),
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
                        color: CafeStaffEditProductPage._teal,
                      ),
                      label: Text(
                        t.staffAddAddSize,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: CafeStaffEditProductPage._teal,
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
                          return _isValidNum(v)
                              ? null
                              : t.staffEditInvalidNumber;
                        },
                        hint: t.staffAddBasePriceHint,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                _sectionHeader(t.staffAddOtherDetailsTitle),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    children: [
                      _labeledField(
                        label: t.staffEditCalories,
                        controller: _calories,
                        keyboardType: TextInputType.number,
                        validator: (v) => _isValidInt(v, allowEmpty: true)
                            ? null
                            : t.staffEditInvalidNumber,
                        hint: "0",
                      ),
                      const SizedBox(height: 12),
                      _labeledField(
                        label: t.staffEditPrepMinutes,
                        controller: _prepMinutes,
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                        _isValidInt(v) ? null : t.staffEditInvalidNumber,
                        hint: "0",
                      ),
                      const SizedBox(height: 12),
                      _labeledField(
                        label: t.staffEditSortIndexOptional,
                        controller: _sortIndex,
                        keyboardType: TextInputType.number,
                        validator: (v) => _isValidInt(v, allowEmpty: true)
                            ? null
                            : t.staffEditInvalidNumber,
                        hint: t.staffEditGroupMaxSelectHint,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                _sectionHeader(t.staffEditActiveVisibleInMenu),
                const SizedBox(height: 10),
                _card(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          t.staffEditActiveVisibleInMenu,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Switch(
                        value: _isActive,
                        activeColor: CafeStaffEditProductPage._teal,
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
                      child: _sectionHeader(t.staffEditCustomizationsTitle),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : () => _addGroup(),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          t.staffEditAddGroup,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CafeStaffEditProductPage._teal,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_groups.isEmpty)
                  _softHintCard(t.staffEditNoCustomizationsYet)
                else
                  ..._groups.map(
                        (g) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _groupCard(t, g),
                    ),
                  ),

                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: CafeStaffEditProductPage._teal,
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
          color: CafeStaffEditProductPage._teal,
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

  Widget _imagePickerBox(AppLocalizations t) {
    final hasImage =
        (_imageUrl.trim().isNotEmpty) || (_imageAsset.trim().isNotEmpty);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _uploadingImage ? null : () => _pickAndUploadImage(t),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.black.withOpacity(0.18),
            width: 1.2,
          ),
        ),
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
                t.staffEditUploadingImage,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.black.withOpacity(0.65),
                ),
              ),
            ],
          )
              : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasImage
                    ? Icons.check_circle_outline
                    : Icons.cloud_upload_outlined,
                size: 28,
                color: hasImage
                    ? const Color(0xFF1E7E34)
                    : Colors.black.withOpacity(0.45),
              ),
              const SizedBox(height: 10),
              Text(
                hasImage
                    ? t.staffEditImageSelected
                    : t.staffEditPickImage,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.black.withOpacity(0.78),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.staffEditPickImageHint,
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
            validator: (v) => (v == null || v.trim().isEmpty)
                ? t.staffEditRequiredField
                : null,
            hint: t.staffAddSizeNameHint,
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffAddSizePriceSar,
            controller: s.priceCtrl,
            keyboardType: TextInputType.number,
            validator: (v) => _isValidNum(v) ? null : t.staffEditInvalidNumber,
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
                  activeColor: CafeStaffEditProductPage._teal,
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
                onPressed: _saving ? null : () => _confirmDeleteGroup(t, g),
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
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffEditGroupTitleAr,
            controller: g.titleArCtrl,
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
                  activeColor: CafeStaffEditProductPage._teal,
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
                  color: CafeStaffEditProductPage._teal,
                ),
                label: Text(
                  t.staffEditAddOption,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: CafeStaffEditProductPage._teal,
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

  Widget _optionCard(AppLocalizations t, _EditOptionGroup g, _EditOption o) {
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
                onPressed: _saving ? null : () => _confirmDeleteOption(t, g, o),
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
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffEditOptionNameAr,
            controller: o.nameArCtrl,
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: t.staffEditOptionPriceDelta,
            controller: o.priceDeltaCtrl,
            keyboardType: TextInputType.number,
            validator: (v) => _isValidNum(v) ? null : t.staffEditInvalidNumber,
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

  void _hydrateOnce(Map<String, dynamic> data) {
    if (_didHydrate) return;
    _didHydrate = true;

    _nameEn.text = _safeString(
      data,
      'name_en',
      fallback: _safeString(data, 'name'),
    );
    _nameAr.text = _safeString(
      data,
      'name_ar',
      fallback: _safeString(data, 'nameAr', fallback: ''),
    );

    _descEn.text = _safeString(
      data,
      'description_en',
      fallback: _safeString(
        data,
        'desc_en',
        fallback: _safeString(data, 'descriptionEn', fallback: ''),
      ),
    );
    _descAr.text = _safeString(
      data,
      'description_ar',
      fallback: _safeString(
        data,
        'desc_ar',
        fallback: _safeString(data, 'descriptionAr', fallback: ''),
      ),
    );

    _catEn.text = _safeString(
      data,
      'category_en',
      fallback: _safeString(data, 'category'),
    );
    _catAr.text = _safeString(
      data,
      'category_ar',
      fallback: _safeString(data, 'categoryAr', fallback: ''),
    );

    _imageUrl = _safeString(data, 'imageUrl');
    _imagePath = _safeString(data, 'imagePath');
    _imageAsset = _safeString(data, 'imageAsset');

    _price.text = _safeNum(data, 'price', fallback: 0).toString();
    _calories.text = _safeNum(data, 'calories', fallback: 0).toString();
    _prepMinutes.text = _safeNum(data, 'prepMinutes', fallback: 0).toString();

    final sortRaw = data['sortIndex'];
    _sortIndex.text = (sortRaw is num) ? sortRaw.toInt().toString() : '';

    _isActive = (data['isActive'] is bool) ? data['isActive'] as bool : true;

    final rawSizes = data['sizes'];
    final parsedSizes = _parseSizes(rawSizes);
    _sizes
      ..clear()
      ..addAll(parsedSizes);

    final rawGroups = data['optionGroups'];
    final parsedGroups = _parseGroups(rawGroups);
    _groups
      ..clear()
      ..addAll(parsedGroups);
  }

  List<_EditSize> _parseSizes(dynamic raw) {
    if (raw is! List) return [];

    final list = <_EditSize>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);

      final name = (m['name'] ?? '').toString();
      final price = (m['price'] is num) ? (m['price'] as num).toDouble() : 0.0;
      final calories =
      (m['calories'] is num) ? (m['calories'] as num).toInt() : null;
      final isAvailable =
      (m['isAvailable'] is bool) ? (m['isAvailable'] as bool) : true;

      list.add(
        _EditSize(
          name: name,
          price: price,
          calories: calories,
          isAvailable: isAvailable,
        ),
      );
    }
    return list;
  }

  List<_EditOptionGroup> _parseGroups(dynamic raw) {
    if (raw is! List) return [];

    final list = <_EditOptionGroup>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);

      final id = (m['id'] ?? '').toString().trim();
      final type = (m['type'] ?? 'single').toString().trim().toLowerCase();
      final required =
      (m['required'] is bool) ? (m['required'] as bool) : false;

      final titleEn =
      (m['title_en'] ?? m['titleEn'] ?? m['title'] ?? '').toString();
      final titleAr =
      (m['title_ar'] ?? m['titleAr'] ?? '').toString();

      final maxSelect =
      (m['maxSelect'] is num) ? (m['maxSelect'] as num).toInt() : null;

      final optionsRaw = m['options'];
      final options = <_EditOption>[];
      if (optionsRaw is List) {
        for (final o in optionsRaw) {
          if (o is! Map) continue;
          final om = Map<String, dynamic>.from(o);

          final optId = (om['id'] ?? '').toString().trim();
          final nameEn =
          (om['name_en'] ?? om['nameEn'] ?? om['name'] ?? '').toString();
          final nameAr =
          (om['name_ar'] ?? om['nameAr'] ?? '').toString();
          final priceDelta =
          (om['priceDelta'] is num) ? (om['priceDelta'] as num).toDouble() : 0.0;
          final caloriesDelta =
          (om['caloriesDelta'] is num) ? (om['caloriesDelta'] as num).toInt() : null;

          options.add(
            _EditOption(
              id: optId,
              nameEn: nameEn,
              nameAr: nameAr,
              priceDelta: priceDelta,
              caloriesDelta: caloriesDelta,
            ),
          );
        }
      }

      list.add(
        _EditOptionGroup(
          id: id,
          type: (type == 'multi') ? 'multi' : 'single',
          required: required,
          maxSelect: maxSelect,
          titleEn: titleEn,
          titleAr: titleAr,
          options: options,
        ),
      );
    }
    return list;
  }

  Future<void> _pickAndUploadImage(AppLocalizations t) async {
    final picker = ImagePicker();

    try {
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _uploadingImage = true);

      final file = File(picked.path);
      final ext = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';

      final storagePath =
          "cafes/${widget.cafeId}/products/${widget.productDocId}/${DateTime.now().millisecondsSinceEpoch}.$ext";

      final ref = FirebaseStorage.instance.ref(storagePath);

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      setState(() {
        _imageUrl = url;
        _imagePath = storagePath;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.staffEditImageUploadSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

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

  Future<void> _confirmDeleteGroup(
      AppLocalizations t,
      _EditOptionGroup g,
      ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.staffEditDeleteGroupTitle),
        content: Text(t.staffEditDeleteGroupBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t.staffEditDelete,
              style: const TextStyle(
                color: Color(0xFFE74C3C),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() => _groups.remove(g));
    }
  }

  Future<void> _confirmDeleteOption(
      AppLocalizations t,
      _EditOptionGroup g,
      _EditOption o,
      ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.staffEditDeleteOptionTitle),
        content: Text(t.staffEditDeleteOptionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t.staffEditDelete,
              style: const TextStyle(
                color: Color(0xFFE74C3C),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() => g.options.remove(o));
    }
  }

  Future<void> _save(AppLocalizations t) async {
    if (!_formKey.currentState!.validate()) return;

    for (final g in _groups) {
      for (final o in g.options) {
        final en = o.nameEnCtrl.text.trim();
        final ar = o.nameArCtrl.text.trim();
        if (en.isEmpty && ar.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.staffEditOptionNameRequired)),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);

    try {
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
        'sortIndex': _sortIndex.text.trim().isEmpty
            ? null
            : (int.tryParse(_sortIndex.text.trim()) ?? 0),
        'isActive': _isActive,
        'imageUrl': _imageUrl.trim(),
        'imagePath': _imagePath.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final sizesPayload = _sizes.map((s) {
        return {
          'name': s.nameCtrl.text.trim(),
          'price': double.tryParse(s.priceCtrl.text.trim()) ?? 0.0,
          'calories': int.tryParse(s.caloriesCtrl.text.trim()) ?? 0,
          'isAvailable': s.isAvailable,
        };
      }).toList();

      payload['sizes'] = sizesPayload;

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

        final maxSelect = (g.type == 'multi')
            ? (g.maxSelectCtrl.text.trim().isEmpty
            ? null
            : (int.tryParse(g.maxSelectCtrl.text.trim()) ?? 0))
            : null;

        final optsPayload = <Map<String, dynamic>>[];
        for (final o in g.options) {
          final nameEn = o.nameEnCtrl.text.trim();
          final nameAr = o.nameArCtrl.text.trim();
          final delta = double.tryParse(o.priceDeltaCtrl.text.trim()) ?? 0.0;
          final caloriesDelta =
              int.tryParse(o.caloriesDeltaCtrl.text.trim()) ?? 0;

          final optId = o.id.trim().isNotEmpty
              ? o.id.trim()
              : _slug(
            nameEn.isNotEmpty
                ? nameEn
                : (nameAr.isNotEmpty
                ? nameAr
                : 'opt_${DateTime.now().millisecondsSinceEpoch}'),
          );

          optsPayload.add({
            'id': optId,
            'name_en': nameEn,
            'name_ar': nameAr,
            'name': nameEn.isNotEmpty ? nameEn : nameAr,
            'priceDelta': delta,
            'caloriesDelta': caloriesDelta,
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
          'options': optsPayload,
        });
      }

      payload['optionGroups'] = optionGroupsPayload;

      payload.removeWhere((k, v) => v == null);

      await _docRef.update(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.staffEditSavedSuccess)),
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
  String type;
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

  int? get maxSelect {
    final s = maxSelectCtrl.text.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }
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
        priceDeltaCtrl = TextEditingController(text: priceDelta.toString()),
        caloriesDeltaCtrl = TextEditingController(
          text: caloriesDelta == null ? '' : caloriesDelta.toString(),
        );
}