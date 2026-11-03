import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:campresso/features/user/cafe_details_page.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

const String kAppLogoAsset = 'assets/images/logocolor.png';

enum CafeType { dunkin, selu, window }

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _primary = Color(0xFF0E6F73);

  GoogleMapController? _map;
  bool _didAutoFit = false;

  String? _firstName;
  bool _loadingUserName = true;

  // 📍 Locations
  static const _dunkin = LatLng(24.8548852, 46.7183096);
  static const _selu = LatLng(24.8552314, 46.7179780);
  static const _window = LatLng(24.8535667, 46.7179924);

  final Map<CafeType, String> _cafeIds = const {
    CafeType.dunkin: "dunkin",
    CafeType.selu: "selu",
    CafeType.window: "window",
  };

  final Map<CafeType, String> _cafeNamesEn = const {
    CafeType.dunkin: "Dunkin Donuts",
    CafeType.selu: "Selu Cafe",
    CafeType.window: "Window Coffee",
  };

  final Map<CafeType, String> _cafeNamesAr = const {
    CafeType.dunkin: "دانكن دونتس",
    CafeType.selu: "سيلو كافيه",
    CafeType.window: "نافذة القهوة",
  };

  final Map<CafeType, String> _cafeLogos = const {
    CafeType.dunkin: "assets/images/cafes/dunkin.png",
    CafeType.selu: "assets/images/cafes/selu.png",
    CafeType.window: "assets/images/cafes/window.jpeg",
  };

  final Map<CafeType, double> _distanceKm = const {
    CafeType.dunkin: 3.8,
    CafeType.selu: 5.8,
    CafeType.window: 6.0,
  };

  final Map<CafeType, LatLng> _positions = const {
    CafeType.dunkin: _dunkin,
    CafeType.selu: _selu,
    CafeType.window: _window,
  };

  final Map<CafeType, String> _pinAssets = const {
    CafeType.dunkin: 'assets/markers/dunkin_pin.png',
    CafeType.selu: 'assets/markers/selu_pin.png',
    CafeType.window: 'assets/markers/window_pin.png',
  };

  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUserName();
    _initMarkers();
  }

  Future<void> _loadCurrentUserName() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _firstName = null;
          _loadingUserName = false;
        });
        return;
      }

      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      final data = doc.data() ?? {};
      final firstName = (data['firstName'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _firstName = firstName.isEmpty ? null : firstName;
        _loadingUserName = false;
      });
    } catch (e) {
      debugPrint('❌ loadCurrentUserName error in MapPage: $e');
      if (!mounted) return;
      setState(() {
        _firstName = null;
        _loadingUserName = false;
      });
    }
  }

  bool _isMorning() {
    final now = DateTime.now();
    return now.hour < 12;
  }

  String _buildGreeting(AppLocalizations t) {
    final trimmedName = (_firstName ?? '').trim();
    final isMorning = _isMorning();

    if (!_loadingUserName && trimmedName.isNotEmpty) {
      return isMorning
          ? t.goodMorningWithName(trimmedName)
          : t.goodAfternoonWithName(trimmedName);
    }

    return isMorning ? t.goodMorning : t.goodAfternoon;
  }

  bool _isCafeClosedNow() {
    final now = DateTime.now();
    final isFri = now.weekday == DateTime.friday;
    final isSat = now.weekday == DateTime.saturday;
    if (isFri || isSat) return true;

    final h = now.hour;
    if (h >= 17 || h < 8) return true;

    return false;
  }

  String _crowdLevelForCafe(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (_isCafeClosedNow()) return t.closed;
    return t.crowded;
  }

  Future<void> _initMarkers() async {
    final icons = <CafeType, BitmapDescriptor>{};

    for (final c in CafeType.values) {
      try {
        icons[c] = await _loadMarker(_pinAssets[c]!);
      } catch (e) {
        debugPrint("❌ Failed to load marker for $c: $e");
        icons[c] = BitmapDescriptor.defaultMarker;
      }
    }

    if (!mounted) return;
    setState(() {
      _markers = {
        for (final c in CafeType.values)
          Marker(
            markerId: MarkerId(_cafeIds[c]!),
            position: _positions[c]!,
            icon: icons[c]!,
            onTap: () => _openCafe(c),
          ),
      };
    });
  }

  Future<BitmapDescriptor> _loadMarker(String asset) async {
    final data = await rootBundle.load(asset);

    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 170,
    );

    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception("toByteData returned null for $asset");
    }

    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
  }

  void _openCafe(CafeType cafe) {
    final t = AppLocalizations.of(context)!;

    if (_isCafeClosedNow()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.cafeClosedNow)),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CafeDetailsPage(
          cafeId: _cafeIds[cafe]!,
          cafeNameEn: _cafeNamesEn[cafe]!,
          cafeNameAr: _cafeNamesAr[cafe]!,
          cafeLogoAsset: _cafeLogos[cafe]!,
          distanceKm: _distanceKm[cafe]!,
          crowdLevel: _crowdLevelForCafe(context),
        ),
      ),
    );
  }

  Future<void> _autoFit() async {
    if (_map == null || _didAutoFit) return;
    _didAutoFit = true;

    final bounds = _boundsFromLatLngList([_dunkin, _selu, _window]);
    await _map!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 120));
  }

  Future<void> _zoomIn() async {
    if (_map == null) return;
    await _map!.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    if (_map == null) return;
    await _map!.animateCamera(CameraUpdate.zoomOut());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(24.8505, 46.7285),
              zoom: 14.6,
            ),
            onMapCreated: (c) {
              _map = c;
              _autoFit();
            },
            markers: _markers,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            padding: const EdgeInsets.only(top: 170),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                _ZoomButton(icon: Icons.add, onTap: _zoomIn),
                const SizedBox(height: 10),
                _ZoomButton(icon: Icons.remove, onTap: _zoomOut),
              ],
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _HomeLikeHeader(
                  primary: _primary,
                  title: _buildGreeting(t),
                  subtitle: t.mapLocationSubtitle,
                  isAr: isAr,
                  onBack: () => Navigator.pop(context),
                  onRefresh: () {
                    _didAutoFit = false;
                    _autoFit();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double x0 = list.first.latitude;
    double x1 = x0;
    double y0 = list.first.longitude;
    double y1 = y0;

    for (final p in list) {
      if (p.latitude > x1) x1 = p.latitude;
      if (p.latitude < x0) x0 = p.latitude;
      if (p.longitude > y1) y1 = p.longitude;
      if (p.longitude < y0) y0 = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(x0, y0),
      northeast: LatLng(x1, y1),
    );
  }
}

/* ================= HEADER ================= */

class _HomeLikeHeader extends StatelessWidget {
  final Color primary;
  final String title;
  final String subtitle;
  final bool isAr;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  const _HomeLikeHeader({
    required this.primary,
    required this.title,
    required this.subtitle,
    required this.isAr,
    required this.onBack,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iconBox(Icons.arrow_back_ios_new, onBack),
                const SizedBox(width: 10),
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(
                    kAppLogoAsset,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                      isAr ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment:
                          isAr ? Alignment.centerRight : Alignment.centerLeft,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: isAr ? TextAlign.right : TextAlign.left,
                            style: TextStyle(
                              color: primary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 15,
                              color: Colors.black54,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Align(
                                alignment: isAr
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign:
                                  isAr ? TextAlign.right : TextAlign.left,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _iconBox(Icons.refresh, onRefresh, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ZoomButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: const Color(0xFF0E6F73)),
        ),
      ),
    );
  }
}