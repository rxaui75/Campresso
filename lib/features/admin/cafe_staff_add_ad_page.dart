import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';
import 'package:crop_your_image/crop_your_image.dart';

class CafeStaffAddAdPage extends StatefulWidget {
  final String cafeId;
  const CafeStaffAddAdPage({super.key, required this.cafeId});

  @override
  State<CafeStaffAddAdPage> createState() => _CafeStaffAddAdPageState();
}

class _CafeStaffAddAdPageState extends State<CafeStaffAddAdPage> {
  static const teal = Color(0xFF0E6F73);

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  /// ✅ هذا هو "Visible"
  bool _visible = true;

  bool _saving = false;
  bool _uploadingImage = false;
  bool _pickingImage = false;

  Uint8List? _pickedBytes;

  /// ✅ NEW: Ad Action
  /// cafe => open cafe only
  /// category => open a category tab in cafe
  /// product => open specific product in cafe
  String _actionType = 'cafe';

  /// ✅ NEW: Selected category key (category_en)
  String? _selectedCategoryKey;

  /// ✅ NEW: Selected product id (doc id in cafes/{cafeId}/products)
  String? _selectedProductId;

  CollectionReference<Map<String, dynamic>> get _adsRef => FirebaseFirestore
      .instance
      .collection('cafes')
      .doc(widget.cafeId)
      .collection('ads');

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickAndCrop(AppLocalizations t) async {
    if (_pickingImage || _saving || _uploadingImage) return;
    setState(() => _pickingImage = true);

    try {
      final picker = ImagePicker();
      final picked =
      await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (!mounted) return;
      if (picked == null) return;

      final bytes = await picked.readAsBytes();

      final cropped = await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (_) => _ManualCropPage(
            title: t.staffAdsCropTitle,
            imageBytes: bytes,
          ),
        ),
      );

      if (!mounted) return;
      if (cropped == null) return;

      setState(() => _pickedBytes = cropped);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("${t.error}: $e")));
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<Map<String, String>> _uploadImage(AppLocalizations t, String adId) async {
    if (_pickedBytes == null || _pickedBytes!.isEmpty) {
      throw Exception(t.staffAdsImageRequired);
    }

    setState(() => _uploadingImage = true);

    try {
      const ext = 'jpg';
      final storagePath = "cafes/${widget.cafeId}/ads/$adId/main.$ext";
      final ref = FirebaseStorage.instance.ref(storagePath);

      final meta = SettableMetadata(contentType: 'image/jpeg');
      await ref.putData(_pickedBytes!, meta);

      final url = await ref.getDownloadURL();
      return {'imageUrl': url, 'imagePath': storagePath};
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  bool _validateAction(AppLocalizations t) {
    // If category => must pick category
    if (_actionType == 'category') {
      final key = (_selectedCategoryKey ?? '').trim();
      if (key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.staffEditRequiredField)),
        );
        return false;
      }
    }

    // If product => must pick productId
    if (_actionType == 'product') {
      final pid = (_selectedProductId ?? '').trim();
      if (pid.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.staffEditRequiredField)),
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _save(AppLocalizations t) async {
    if (!_formKey.currentState!.validate()) return;

    if (_pickedBytes == null || _pickedBytes!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.staffAdsImageRequired)));
      return;}
    if (!_validateAction(t)) return;
    setState(() => _saving = true);
    try {
      final doc = _adsRef.doc();
      final adId = doc.id;

      final img = await _uploadImage(t, adId);

      final user = FirebaseAuth.instance.currentUser;
      final creatorEmail = (user?.email ?? '').trim();
      final creatorUid = (user?.uid ?? '').trim();

      final payload = <String, dynamic>{
        'adId': adId,
        'cafeId': widget.cafeId,

        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'imageUrl': img['imageUrl'],
        'imagePath': img['imagePath'],

        'visible': _visible,
        'isActive': _visible, // backward compat

        'actionType': _actionType, // cafe / category / product
        if (_actionType == 'category')
          'categoryKey': (_selectedCategoryKey ?? '').trim(),
        if (_actionType == 'product')
          'productId': (_selectedProductId ?? '').trim(),

        'type': 'ad',
        'createdByUid': creatorUid,
        if (creatorEmail.isNotEmpty) 'createdByEmail': creatorEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await doc.set(payload);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.saved)),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("${t.error}: $e")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final hasImage = _pickedBytes != null;
    final disabled = _saving || _uploadingImage || _pickingImage;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.6,
        centerTitle: true,
        title: Text(
          t.staffAdsAddTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: disabled ? null : () => _pickAndCrop(t),
              child: Container(
                height: 170,
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
                  clipBehavior: Clip.antiAlias,
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
                          t.staffAdsUploading,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withOpacity(0.65),
                          ),
                        ),
                      ],
                    )
                        : _pickingImage
                        ? Text(
                      t.staffAdsUploading,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.black.withOpacity(0.65),
                      ),
                    )
                        : hasImage
                        ? Image.memory(
                      _pickedBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                        : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 30,
                          color: Colors.black.withOpacity(0.45),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          t.staffAdsClickHere,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.black.withOpacity(0.78),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.staffAdsUploadHint,
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
            ),
            const SizedBox(height: 14),

            _label(t.staffAdsNameLabel),
            const SizedBox(height: 8),
            TextFormField(
              controller: _title,
              decoration: _deco(t.staffAdsNameHint),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? t.staffEditRequiredField : null,
            ),
            const SizedBox(height: 14),

            _label(t.staffAdsDescriptionLabel),
            const SizedBox(height: 8),
            TextFormField(
              controller: _body,
              maxLines: 4,
              decoration: _deco(t.staffAdsDescriptionHint),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? t.staffEditRequiredField : null,
            ),
            const SizedBox(height: 18),

            /// ✅ NEW: Link Type / Action
            _label("Ad action"),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _actionTile(
                    title: "Open cafe",
                    value: 'cafe',
                    disabled: disabled,
                  ),
                  _actionTile(
                    title: "Open category tab",
                    value: 'category',
                    disabled: disabled,
                  ),
                  _actionTile(
                    title: "Open product",
                    value: 'product',
                    disabled: disabled,
                  ),

                  if (_actionType == 'category') ...[
                    const SizedBox(height: 12),
                    _categoryPicker(disabled: disabled),
                  ],

                  if (_actionType == 'product') ...[
                    const SizedBox(height: 12),
                    _productPicker(disabled: disabled),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 18),

            _label(t.staffAdsAvailabilityTitle),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.staffAdsAvailabilityBody,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Switch(
                    value: _visible,
                    activeColor: teal,
                    onChanged: disabled ? null : (v) => setState(() => _visible = v),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: teal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: disabled ? null : () => _save(t),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE74C3C)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: disabled ? null : () => Navigator.pop(context, false),
                      child: Text(
                        t.cancel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFE74C3C),
                        ),
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

  Widget _actionTile({
    required String title,
    required String value,
    required bool disabled,
  }) {
    final selected = _actionType == value;
    return InkWell(
      onTap: disabled
          ? null
          : () => setState(() {
        _actionType = value;

        // clear irrelevant selections
        if (_actionType != 'category') _selectedCategoryKey = null;
        if (_actionType != 'product') _selectedProductId = null;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            _RadioCircle(selected: selected),
          ],
        ),
      ),
    );
  }

  Widget _categoryPicker({required bool disabled}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('cafes')
          .doc(widget.cafeId)
          .collection('products')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final docs = snap.data?.docs ?? [];

        final keys = <String>{};
        for (final d in docs) {
          final m = d.data();
          final key = (m['category_en'] ?? m['categoryEn'] ?? m['category'] ?? '')
              .toString()
              .trim();
          if (key.isNotEmpty) keys.add(key);
        }

        final list = keys.toList()..sort();

        return DropdownButtonFormField<String>(
          value: (_selectedCategoryKey != null && list.contains(_selectedCategoryKey))
              ? _selectedCategoryKey
              : null,
          items: list
              .map((k) => DropdownMenuItem<String>(
            value: k,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800)),
          ))
              .toList(),
          onChanged: disabled ? null : (v) => setState(() => _selectedCategoryKey = v),
          decoration: _deco("Choose category (category_en)"),
          validator: (v) {
            if (_actionType == 'category' && (v == null || v.trim().isEmpty)) {
              return "Required";
            }
            return null;
          },
        );
      },
    );
  }

  Widget _productPicker({required bool disabled}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('cafes')
          .doc(widget.cafeId)
          .collection('products')
          .orderBy('name_en')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final docs = snap.data?.docs ?? [];

        final items = docs.map((d) {
          final m = d.data();
          final id = d.id;
          final nameEn = (m['name_en'] ?? m['nameEn'] ?? m['name'] ?? '').toString().trim();
          final nameAr = (m['name_ar'] ?? m['nameAr'] ?? '').toString().trim();
          final label = (nameEn.isNotEmpty)
              ? nameEn
              : (nameAr.isNotEmpty ? nameAr : id);
          return (id: id, label: label);
        }).toList();

        return DropdownButtonFormField<String>(
          value: (_selectedProductId != null &&
              items.any((x) => x.id == _selectedProductId))
              ? _selectedProductId
              : null,
          items: items
              .map((x) => DropdownMenuItem<String>(
            value: x.id,
            child: Text(x.label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ))
              .toList(),
          onChanged: disabled ? null : (v) => setState(() => _selectedProductId = v),
          decoration: _deco("Choose product"),
          validator: (v) {
            if (_actionType == 'product' && (v == null || v.trim().isEmpty)) {
              return "Required";
            }
            return null;
          },
        );
      },
    );
  }

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      color: Colors.black.withOpacity(0.62),
      fontWeight: FontWeight.w900,
      fontSize: 12.5,
    ),
  );

  InputDecoration _deco(String hint) => InputDecoration(
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
      borderSide: const BorderSide(color: teal, width: 1.4),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
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
              width: 36,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text(
              "Done",
              style: TextStyle(
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
                interactive: true,
                onCropped: (Uint8List croppedData) =>
                    Navigator.pop(context, croppedData),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _cropping ? null : () => Navigator.pop(context, null),
                child: const Text(
                  "Cancel",
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
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