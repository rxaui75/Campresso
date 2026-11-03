import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'cafe_staff_add_ad_page.dart';
import 'cafe_staff_edit_ad_page.dart';

class CafeStaffAdsPage extends StatefulWidget {
  final String cafeId;
  const CafeStaffAdsPage({super.key, required this.cafeId});

  @override
  State<CafeStaffAdsPage> createState() => _CafeStaffAdsPageState();
}

class _CafeStaffAdsPageState extends State<CafeStaffAdsPage> {
  static const teal = Color(0xFF0E6F73);

  CollectionReference<Map<String, dynamic>> get _adsRef =>
      FirebaseFirestore.instance.collection('cafes').doc(widget.cafeId).collection('ads');

  Future<void> _confirmDelete(AppLocalizations t, String adId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.staffAdsDeleteConfirmTitle),
        content: Text(t.staffAdsDeleteConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.staffAdsDelete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _adsRef.doc(adId).delete();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.staffAdsDeletedSnack)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0.6,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(t.staffAdsTitle, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CafeStaffAddAdPage(cafeId: widget.cafeId),
                  ),
                );
                if (ok == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.staffAdsAddedSuccess)),
                  );
                }
              },
              icon: const Icon(Icons.add, size: 18, color: Colors.white),
              label: Text(
                t.staffAdsAddButton,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _adsRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("${t.error}: ${snap.error}"));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.staffAdsNoAds,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();

              final title = (data['title'] ?? '').toString();
              final body = (data['body'] ?? '').toString();
              final imageUrl = (data['imageUrl'] ?? '').toString();
              final isActive = (data['isActive'] is bool) ? data['isActive'] as bool : true;

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: teal.withOpacity(0.35), width: 1.2),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 16,
                      offset: const Offset(0, 10),
                      color: Colors.black.withOpacity(0.05),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 90,
                        height: 90,
                        color: Colors.black.withOpacity(0.06),
                        child: imageUrl.isEmpty
                            ? Icon(Icons.image_outlined, color: Colors.black.withOpacity(0.35))
                            : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.image_outlined,
                            color: Colors.black.withOpacity(0.35),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title.isEmpty ? "-" : title,
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: isActive ? const Color(0xFFE6F4EA) : const Color(0xFFF2F4F7),
                                ),
                                child: Text(
                                  isActive ? t.staffAdsStatusActive : t.staffAdsStatusHidden,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11.5,
                                    color: isActive ? const Color(0xFF2E7D32) : Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            body.isEmpty ? "-" : body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: teal,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      elevation: 0,
                                    ),
                                    onPressed: () async {
                                      final ok = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CafeStaffEditAdPage(
                                            cafeId: widget.cafeId,
                                            adId: d.id,
                                          ),
                                        ),
                                      );

                                      if (ok == true && mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(t.saved)),
                                        );
                                      }
                                    },
                                    child: Text(
                                      t.staffAdsEditButton,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 40,
                                width: 46,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFE74C3C)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () => _confirmDelete(t, d.id),
                                  child: const Icon(Icons.delete_outline, color: Color(0xFFE74C3C)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}