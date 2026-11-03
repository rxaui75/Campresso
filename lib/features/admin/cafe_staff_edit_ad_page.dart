import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';
import 'package:crop_your_image/crop_your_image.dart';

class CafeStaffEditAdPage extends StatefulWidget {
  final String cafeId;
  final String adId;

  const CafeStaffEditAdPage({
    super.key,
    required this.cafeId,
    required this.adId,
  });

  @override
  State<CafeStaffEditAdPage> createState() => _CafeStaffEditAdPageState();
}

class _CafeStaffEditAdPageState extends State<CafeStaffEditAdPage> {
  static const teal = Color(0xFF0E6F73);

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  bool _visible = true;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingImage = false;
  bool _pickingImage = false;

  Uint8List? _pickedBytes;
  String? _existingImageUrl;
  String? _existingImagePath;

  String _actionType = 'cafe';
  String? _selectedCategoryKey;
  String? _selectedProductId;

  DocumentReference<Map<String, dynamic>> get _adDoc => FirebaseFirestore
      .instance
      .collection('cafes')
      .doc(widget.cafeId)
      .collection('ads')
      .doc(widget.adId);

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadAd() async {
    try {
      final snap = await _adDoc.get();
      if (!mounted) return;
      if (!snap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.orderTrackingNotFound),
          ),
        );
        Navigator.pop(context, false);
        return;
      }
      final data = snap.data() ?? <String, dynamic>{};
      _title.text = (data['title'] ?? '').toString();
      _body.text = (data['body'] ?? '').toString();
      final visibleVal = data['visible'];
      final isActiveVal = data['isActive'];
      _visible = visibleVal is bool
          ? visibleVal
          : (isActiveVal is bool ? isActiveVal : true);

      _existingImageUrl = (data['imageUrl'] ?? '').toString().trim();
      _existingImagePath = (data['imagePath'] ?? '').toString().trim();

      _actionType = (data['actionType'] ?? 'cafe').toString().trim();
      if (_actionType.isEmpty) _actionType = 'cafe';

      _selectedCategoryKey = (data['categoryKey'] ?? '').toString().trim().isEmpty
          ? null
          : (data['categoryKey'] ?? '').toString().trim();

      _selectedProductId = (data['productId'] ?? '').toString().trim().isEmpty
          ? null
          : (data['productId'] ?? '').toString().trim();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${AppLocalizations.of(context)!.error}: $e")),
      );
      Navigator.pop(context, false);
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<Map<String, String>> _uploadImage(AppLocalizations t) async {
    if (_pickedBytes == null || _pickedBytes!.isEmpty) {
      throw Exception(t.staffAdsImageRequired);
    }

    setState(() => _uploadingImage = true);

    try {
      const ext = 'jpg';
      final storagePath = "cafes/${widget.cafeId}/ads/${widget.adId}/main.$ext";
      final ref = FirebaseStorage.instance.ref(storagePath);

      final meta = SettableMetadata(contentType: 'image/jpeg');
      await ref.putData(_pickedBytes!, meta);

      final url = await ref.getDownloadURL();
      return {
        'imageUrl': url,
        'imagePath': storagePath,
      };
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  bool _validateAction(AppLocalizations t) {
    if (_actionType == 'category') {
      final key = (_selectedCategoryKey ?? '').trim();
      if (key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.staffEditRequiredField)),
        );
        return false;
      }
    }

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
    if (!_validateAction(t)) return;

    setState(() => _saving = true);

    try {
      String? imageUrl = _existingImageUrl;
      String? imagePath = _existingImagePath;

      if (_pickedBytes != null && _pickedBytes!.isNotEmpty) {
        final img = await _uploadImage(t);
        imageUrl = img['imageUrl'];
        imagePath = img['imagePath'];
      }

      final payload = <String, dynamic>{
        'title': _title.text.trim(),
        'body': _body.text.trim(),

        'visible': _visible,
        'isActive': _visible,

        'actionType': _actionType,
        'categoryKey': _actionType == 'category'
            ? (_selectedCategoryKey ?? '').trim()
            : FieldValue.delete(),
        'productId': _actionType == 'product'
            ? (_selectedProductId ?? '').trim()
            : FieldValue.delete(),

        'updatedAt': FieldValue.serverTimestamp(),
      };

      if ((imageUrl ?? '').trim().isNotEmpty) {
        payload['imageUrl'] = imageUrl!.trim();
      }
      if ((imagePath ?? '').trim().isNotEmpty) {
        payload['imagePath'] = imagePath!.trim();
      }

      await _adDoc.set(payload, SetOptions(merge: true));

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
    final disabled = _loading || _saving || _uploadingImage || _pickingImage;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.6,
        centerTitle: true,
        title: Text(
          "Edit Ad",
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
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
                        : _pickedBytes != null
                        ? Image.memory(
                      _pickedBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                        : ((_existingImageUrl ?? '').isNotEmpty
                        ? Image.network(
                      _existingImageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => _uploadPlaceholder(t),
                    )
                        : _uploadPlaceholder(t)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _label("Ads Name"),
            const SizedBox(height: 8),
            TextFormField(
              controller: _title,
              decoration: _deco("Original Coffee"),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? t.staffEditRequiredField : null,
            ),
            const SizedBox(height: 14),

            _label("Description"),
            const SizedBox(height: 8),
            TextFormField(
              controller: _body,
              maxLines: 4,
              decoration: _deco("Text Text Text"),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? t.staffEditRequiredField : null,
            ),
            const SizedBox(height: 18),

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

            _label("Ads Availability"),
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
                      "Control whether this ad is visible to customers",
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

  Widget _uploadPlaceholder(AppLocalizations t) {
    return Column(
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
              .map(
                (k) => DropdownMenuItem<String>(
              value: k,
              child: Text(
                k,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          )
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
          final label = nameEn.isNotEmpty ? nameEn : (nameAr.isNotEmpty ? nameAr : id);
          return (id: id, label: label);
        }).toList();

        return DropdownButtonFormField<String>(
          value: (_selectedProductId != null &&
              items.any((x) => x.id == _selectedProductId))
              ? _selectedProductId
              : null,
          items: items
              .map(
                (x) => DropdownMenuItem<String>(
              value: x.id,
              child: Text(
                x.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          )
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
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: teal, width: 1.4),
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