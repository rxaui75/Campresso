import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'delivery/delivery_controller.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'cafe_details_page.dart';
import 'map_page.dart';

// ✅ Tabs
import 'orders_page.dart';
import 'order_tracking_page.dart';
import 'notifications_page.dart';

// ✅ Profile Page
import '/features/user/profile/user_profile_page.dart';

// ✅ Seed

import '/core/customization_templates.dart';

// ✅ ML
import 'package:campresso/features/ml/crowd_ml_service.dart';

class UserHomePage extends StatefulWidget {
  final int initialIndex;
  final String? openOrderId;

  const UserHomePage({
    super.key,
    this.initialIndex = 0,
    this.openOrderId,
  });

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  static const _bg = Color(0xFFF6FAFA);

  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    DeliveryController.instance.start();

    _navIndex = widget.initialIndex;

    _seedOptionsOnce();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final oid = widget.openOrderId;
      if (oid == null || oid.trim().isEmpty) return;

      final orderNumber = oid.hashCode.abs() % 100000;

      if (mounted) setState(() => _navIndex = 1);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingPage(
            orderId: oid,
            orderNumber: orderNumber,
          ),
        ),
      );
    });
  }

  Future<void> _seedOptionsOnce() async {
    if (!kDebugMode) return;
    try {
      await CustomizationSeeder.seedDunkinOptionGroups();
    } catch (e) {
      debugPrint('❌ optionGroups seeding error: $e');
    }
  }

  void _onNavTap(int i) {
    if (i == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MapPage()),
      );
      return;
    }
    setState(() => _navIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(
        index: _navIndex,
        children: const [
          _HomeTab(),
          OrdersPage(),
          SizedBox.shrink(),
          NotificationsPage(asTab: true),
          ProfilePage(asTab: true),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF8B5A3C),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MapPage()),
          );
        },
        child: const Icon(Icons.location_on, color: Colors.white),
      ),
      bottomNavigationBar: _BottomNav(
        index: _navIndex,
        onTap: _onNavTap,
      ),
    );
  }
}

/// =====================================================================
/// ✅ HOME TAB (Closed > ML > Orders Assist > Fallback)
/// =====================================================================

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  static const _primary = Color(0xFF0E6F73);
  static const _bg = Color(0xFFF6FAFA);

  final _search = TextEditingController();

  Position? _pos;
  String _locationText = '';
  bool _loadingLocation = true;

  String? _firstName;
  bool _loadingUserName = true;

  // ✅ ML
  final CrowdMLService _ml = CrowdMLService();
  bool _mlReady = false;

  // ✅ Orders-based assist
  Map<String, int> _recentOrderCounts = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  Timer? _ordersRefreshTimer;

  static const Duration _ordersWindow = Duration(minutes: 45);

  static const int _mediumThreshold = 4;
  static const int _highThreshold = 10;

  @override
  void initState() {
    super.initState();
    _locationText = '...';

    _initLocation();
    _initML();
    _loadCurrentUserName();

    _startOrdersListener();
    _ordersRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _restartOrdersListener();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _ml.dispose();
    _ordersSub?.cancel();
    _ordersRefreshTimer?.cancel();
    super.dispose();
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
      debugPrint('❌ loadCurrentUserName error: $e');
      if (!mounted) return;
      setState(() {
        _firstName = null;
        _loadingUserName = false;
      });
    }
  }

  Future<void> _initML() async {
    try {
      await _ml.init();
      if (!mounted) return;
      setState(() => _mlReady = true);
      if (kDebugMode) debugPrint('✅ ML ready in HomePage');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ ML init failed in HomePage: $e');
      if (!mounted) return;
      setState(() => _mlReady = false);
    }
  }

  Future<void> _initLocation() async {
    final t = AppLocalizations.of(context)!;

    setState(() {
      _loadingLocation = true;
      _locationText = t.gettingLocation;
    });

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() {
          _locationText = t.locationOff;
          _loadingLocation = false;
        });
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _locationText = t.locationPermissionDenied;
          _loadingLocation = false;
        });
        return;
      }

      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _pos = p;

      String nice =
          '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';

      try {
        final places = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (places.isNotEmpty) {
          final place = places.first;
          final street = (place.street ?? '').trim();
          final locality = (place.locality ?? '').trim();
          final text = [street, locality].where((s) => s.isNotEmpty).join(', ');
          if (text.isNotEmpty) nice = text;
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _locationText = nice;
        _loadingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationText = '${t.locationError}: $e';
        _loadingLocation = false;
      });
    }
  }

  Future<void> _refreshHome() async {
    await _initLocation();
    await _loadCurrentUserName();
    _restartOrdersListener();
    if (!_mlReady) {
      await _initML();
    }
    if (mounted) setState(() {});
  }

  bool _isCafeClosedNow(DateTime now) {
    final isFri = now.weekday == DateTime.friday;
    final isSat = now.weekday == DateTime.saturday;
    if (isFri || isSat) return true;

    final h = now.hour;
    if (h >= 17 || h < 8) return true;

    return false;
  }

  int _dayIndex(DateTime now) {
    switch (now.weekday) {
      case DateTime.sunday:
        return 0;
      case DateTime.monday:
        return 1;
      case DateTime.tuesday:
        return 2;
      case DateTime.wednesday:
        return 3;
      case DateTime.thursday:
        return 4;
      case DateTime.friday:
        return 5;
      case DateTime.saturday:
        return 6;
      default:
        return 1;
    }
  }

  void _startOrdersListener() {
    final cutoff = DateTime.now().subtract(_ordersWindow);

    final q = FirebaseFirestore.instance
        .collection('orders')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff));

    _ordersSub?.cancel();
    _ordersSub = q.snapshots().listen((snap) {
      final counts = <String, int>{};

      for (final d in snap.docs) {
        final data = d.data();

        final cafeId = (data['cafeId'] ?? '').toString().trim();
        if (cafeId.isEmpty) continue;

        final cancelledAt = data['cancelledAt'];
        if (cancelledAt != null) continue;

        final status = (data['status'] ?? '').toString().toLowerCase().trim();
        if (status == 'cancelled' || status == 'canceled') continue;

        counts[cafeId] = (counts[cafeId] ?? 0) + 1;
      }

      if (!mounted) return;
      setState(() => _recentOrderCounts = counts);

      if (kDebugMode) {
        debugPrint(
          '✅ recent orders window=${_ordersWindow.inMinutes}m counts=$_recentOrderCounts',
        );
      }
    }, onError: (e) {
      debugPrint('❌ orders listener error: $e');
    });
  }

  void _restartOrdersListener() {
    if (kDebugMode) debugPrint('🔄 restarting orders listener...');
    _startOrdersListener();
  }

  CrowdLevel _crowdFromOrders(String cafeId) {
    final c = _recentOrderCounts[cafeId] ?? 0;
    if (c >= _highThreshold) return CrowdLevel.high;
    if (c >= _mediumThreshold) return CrowdLevel.medium;
    return CrowdLevel.low;
  }

  CrowdLevel _predictCrowdFallback(String cafeId) {
    final hour = DateTime.now().hour;

    int base;
    if (hour >= 11 && hour < 13) {
      base = 2;
    } else if (hour >= 10 && hour < 11) {
      base = 1;
    } else {
      base = 0;
    }

    final salt = cafeId.codeUnits.fold<int>(0, (a, b) => a + b);
    final r = Random(salt + DateTime.now().day).nextInt(10);
    final bump = (r > 7) ? 1 : 0;

    final v = (base + bump).clamp(0, 2);
    return CrowdLevel.values[v];
  }

  CrowdLevel? _predictCrowdFromMl() {
    if (!_mlReady) return null;

    final now = DateTime.now();
    final day = _dayIndex(now);
    final hour = now.hour;
    final isClosed = _isCafeClosedNow(now) ? 1 : 0;

    final pred = _ml.predict(
      day: day,
      hour: hour,
      isClosed: isClosed,
      debug: kDebugMode,
    );

    if (kDebugMode) {
      debugPrint(
        '🤖 ML baseline => $pred (day=$day hour=$hour isClosed=$isClosed)',
      );
    }

    return pred;
  }

  CrowdLevel _combineMlWithOrders({
    required CrowdLevel mlCrowd,
    required CrowdLevel ordersCrowd,
  }) {
    if (ordersCrowd == CrowdLevel.high) return CrowdLevel.high;

    if (ordersCrowd == CrowdLevel.medium) {
      if (mlCrowd == CrowdLevel.low) return CrowdLevel.medium;
      return mlCrowd;
    }

    return mlCrowd;
  }

  CrowdLevel _predictCrowd(String cafeId) {
    final now = DateTime.now();

    if (_isCafeClosedNow(now)) return CrowdLevel.closed;

    final mlCrowd = _predictCrowdFromMl();

    if (mlCrowd != null && _recentOrderCounts.isNotEmpty) {
      final ordersCrowd = _crowdFromOrders(cafeId);
      return _combineMlWithOrders(
        mlCrowd: mlCrowd,
        ordersCrowd: ordersCrowd,
      );
    }

    if (mlCrowd != null) return mlCrowd;

    if (_recentOrderCounts.isNotEmpty) {
      return _crowdFromOrders(cafeId);
    }

    return _predictCrowdFallback(cafeId);
  }

  String _logoForCafeId(String id) {
    switch (id) {
      case 'dunkin':
        return 'assets/images/cafes/dunkin.png';
      case 'window':
        return 'assets/images/cafes/window.jpeg';
      case 'selu':
        return 'assets/images/cafes/selu.png';
      default:
        return 'assets/images/cafes/default.png';
    }
  }

  String _arabicNameForCafeId(String id) {
    switch (id) {
      case 'dunkin':
        return 'دانكن';
      case 'window':
        return 'ويندو';
      case 'selu':
        return 'سيلو';
      default:
        return '';
    }
  }

  String _crowdText(BuildContext context, CrowdLevel c) {
    final t = AppLocalizations.of(context)!;
    switch (c) {
      case CrowdLevel.low:
        return t.low;
      case CrowdLevel.medium:
        return t.medium;
      case CrowdLevel.high:
        return t.high;
      case CrowdLevel.closed:
        return t.closed;
    }
  }

  double? _distanceMeters(GeoPoint cafeLocation) {
    if (_pos == null) return null;
    return Geolocator.distanceBetween(
      _pos!.latitude,
      _pos!.longitude,
      cafeLocation.latitude,
      cafeLocation.longitude,
    );
  }

  Future<void> _openAdToCafeDetails(Map<String, dynamic> adData) async {
    final t = AppLocalizations.of(context)!;

    final cafeId = (adData['cafeId'] ?? '').toString().trim();
    if (cafeId.isEmpty) return;

    final actionType = (adData['actionType'] ?? 'cafe').toString().trim();

    final categoryKey = (adData['categoryKey'] ??
        adData['category_en'] ??
        adData['categoryEn'] ??
        adData['category'] ??
        '')
        .toString()
        .trim();

    final productId = (adData['productId'] ??
        adData['highlightProductId'] ??
        adData['product_id'] ??
        '')
        .toString()
        .trim();

    try {
      final cafeDoc =
      await FirebaseFirestore.instance.collection('cafes').doc(cafeId).get();
      final cafe = cafeDoc.data() ?? {};

      final cafeNameEn =
      (cafe['name_en'] ?? cafe['nameEn'] ?? '').toString().trim();
      final cafeNameAr =
      (cafe['name_ar'] ?? cafe['nameAr'] ?? '').toString().trim();

      double distanceKm = 0.0;
      final loc = cafe['location'];
      if (loc is GeoPoint) {
        final m = _distanceMeters(loc);
        if (m != null) distanceKm = m / 1000.0;
      }

      final crowd = _predictCrowd(cafeId);
      final crowdLevel = _crowdText(context, crowd);

      final logoAsset = (cafe['logoAsset'] ?? '').toString().trim();
      final resolvedLogo =
      logoAsset.isNotEmpty ? logoAsset : _logoForCafeId(cafeId);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CafeDetailsPage(
            cafeId: cafeId,
            cafeNameEn: cafeNameEn.isNotEmpty ? cafeNameEn : cafeId,
            cafeNameAr:
            cafeNameAr.isNotEmpty ? cafeNameAr : _arabicNameForCafeId(cafeId),
            cafeLogoAsset: resolvedLogo,
            distanceKm: distanceKm,
            crowdLevel: crowdLevel,
            initialCategoryKey:
            (actionType == 'category' && categoryKey.isNotEmpty)
                ? categoryKey
                : null,
            highlightProductId:
            (actionType == 'product' && productId.isNotEmpty)
                ? productId
                : null,
            autoOpenProduct: (actionType == 'product' && productId.isNotEmpty),
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ openAdToCafeDetails error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.failedToOpenOffer)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cafesQuery =
    FirebaseFirestore.instance.collection('cafes').orderBy('name');

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshHome,
          color: _primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: _bg,
                elevation: 0,
                automaticallyImplyLeading: false,
                toolbarHeight: 96,
                flexibleSpace: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: _Header(
                      firstName: _firstName,
                      loadingUserName: _loadingUserName,
                      locationText:
                      _locationText.isEmpty ? t.gettingLocation : _locationText,
                      loading: _loadingLocation,
                      onRefresh: _refreshHome,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _AdsCarousel(
                    onTapAd: (adData) => _openAdToCafeDetails(adData),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeaderDelegate(
                  height: 62,
                  child: Container(
                    color: _bg,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _SearchBar(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: cafesQuery.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            '${t.errorLoadingCafes}: ${snapshot.error}',
                            style: TextStyle(color: Colors.red.withOpacity(0.8)),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(18),
                          child: Center(child: Text(t.noCafesFound)),
                        );
                      }

                      final lang = Localizations.localeOf(context).languageCode;

                      String cafeNameFromData(Map<String, dynamic> data) {
                        final en = (data['name_en'] ?? '').toString().trim();
                        final ar = (data['name_ar'] ?? '').toString().trim();

                        if (lang == 'ar') {
                          return ar.isNotEmpty
                              ? ar
                              : (en.isNotEmpty ? en : t.cafeDefaultName);
                        }
                        return en.isNotEmpty
                            ? en
                            : (ar.isNotEmpty ? ar : t.cafeDefaultName);
                      }

                      bool matchesSearchByLang(Map<String, dynamic> data) {
                        final q = _search.text.trim().toLowerCase();
                        if (q.isEmpty) return true;

                        final name = cafeNameFromData(data).toLowerCase();
                        return name.contains(q);
                      }

                      final filtered =
                      docs.where((d) => matchesSearchByLang(d.data())).toList();

                      if (filtered.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(18),
                          child: Center(child: Text(t.noResults)),
                        );
                      }

                      return Column(
                        children: filtered.map((d) {
                          final data = d.data();
                          final id = d.id;

                          final displayName = cafeNameFromData(data);

                          final cafeNameEn =
                          (data['name_en'] ?? displayName).toString();
                          final cafeNameAr = (data['name_ar'] ?? '').toString();

                          final loc = data['location'] as GeoPoint?;
                          final distance =
                          (loc == null) ? null : _distanceMeters(loc);

                          final crowd = _predictCrowd(id);

                          final cafe = _Cafe(
                            id: id,
                            name: displayName,
                            logoAsset: _logoForCafeId(id),
                          );

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _CafeCard(
                              cafe: cafe,
                              distanceMeters: distance,
                              crowd: crowd,
                              onTap: () {
                                final distanceKm =
                                (distance == null) ? 0.0 : (distance / 1000);

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CafeDetailsPage(
                                      cafeId: id,
                                      cafeNameEn: cafeNameEn,
                                      cafeNameAr: cafeNameAr.isNotEmpty
                                          ? cafeNameAr
                                          : _arabicNameForCafeId(id),
                                      cafeLogoAsset: _logoForCafeId(id),
                                      distanceKm: distanceKm,
                                      crowdLevel: _crowdText(context, crowd),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =====================================================================
/// ✅ Widgets
/// =====================================================================

class _Cafe {
  final String id;
  final String name;
  final String logoAsset;

  const _Cafe({
    required this.id,
    required this.name,
    required this.logoAsset,
  });
}

class _Header extends StatelessWidget {
  final String? firstName;
  final bool loadingUserName;
  final String locationText;
  final bool loading;
  final Future<void> Function() onRefresh;

  static const _primary = Color(0xFF0E6F73);

  const _Header({
    required this.firstName,
    required this.loadingUserName,
    required this.locationText,
    required this.loading,
    required this.onRefresh,
  });

  bool _isMorning() {
    final now = DateTime.now();
    return now.hour < 12;
  }

  String _buildGreeting(AppLocalizations t) {
    final trimmedName = (firstName ?? '').trim();
    final isMorning = _isMorning();

    if (!loadingUserName && trimmedName.isNotEmpty) {
      return isMorning
          ? t.goodMorningWithName(trimmedName)
          : t.goodAfternoonWithName(trimmedName);
    }

    return isMorning ? t.goodMorning : t.goodAfternoon;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final greetingText = _buildGreeting(t);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/images/logocolor.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  greetingText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _primary,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.black.withOpacity(0.55),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        locationText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.55),
                          fontWeight: FontWeight.w600,
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
        IconButton(
          onPressed: loading ? null : () => onRefresh(),
          icon: const Icon(Icons.refresh),
          color: _primary,
          tooltip: t.refreshLocation,
        ),
      ],
    );
  }
}

class _AdsCarousel extends StatefulWidget {
  final void Function(Map<String, dynamic> adData)? onTapAd;
  const _AdsCarousel({this.onTapAd});

  @override
  State<_AdsCarousel> createState() => _AdsCarouselState();
}

class _AdsCarouselState extends State<_AdsCarousel> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;

  static const _radius = 14.0;

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _startAutoPlay(int count) {
    _timer?.cancel();
    if (count <= 1) return;

    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final next = (_index + 1) % count;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOut,
      );
    });
  }

  Query<Map<String, dynamic>> _adsQuery() {
    return FirebaseFirestore.instance
        .collectionGroup('ads')
        .where('visible', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(12);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: AspectRatio(
        aspectRatio: 16 / 7,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _adsQuery().snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              debugPrint('❌ Ads query error: ${snap.error}');
              return _fallbackBanner(
                icon: Icons.broken_image_outlined,
                text: t.adsUnavailable,
              );
            }

            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs;

            final items = docs
                .map((d) => d.data())
                .where((m) {
              final url = (m['imageUrl'] ?? '').toString().trim();
              return url.isNotEmpty;
            })
                .toList();

            if (items.isEmpty) {
              return _fallbackBanner(
                icon: Icons.local_offer_outlined,
                text: t.noOffersYet,
              );
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _startAutoPlay(items.length);
            });

            return Stack(
              children: [
                PageView.builder(
                  controller: _page,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) {
                    final data = items[i];
                    final url = (data['imageUrl'] ?? '').toString().trim();

                    return InkWell(
                      onTap: () => widget.onTapAd?.call(data),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: Colors.black.withOpacity(0.06),
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) {
                          return _fallbackBanner(
                            icon: Icons.broken_image_outlined,
                            text: t.imageFailedToLoad,
                          );
                        },
                      ),
                    );
                  },
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(items.length, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 12 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _fallbackBanner({required IconData icon, required String text}) {
    return Container(
      color: Colors.black.withOpacity(0.06),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: Colors.black.withOpacity(0.45)),
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: t.search,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _CafeCard extends StatelessWidget {
  final _Cafe cafe;
  final double? distanceMeters;
  final CrowdLevel crowd;
  final VoidCallback? onTap;

  static const _primary = Color(0xFF0E6F73);

  const _CafeCard({
    required this.cafe,
    required this.distanceMeters,
    required this.crowd,
    this.onTap,
  });

  String _distanceText(BuildContext context) {
    if (distanceMeters == null) return '-- m';
    final m = distanceMeters!.round();
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '$m m';
  }

  String _crowdedLabel(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (crowd == CrowdLevel.closed) return t.closed;
    return t.crowded;
  }

  Color get _crowdColor {
    switch (crowd) {
      case CrowdLevel.low:
        return Colors.green;
      case CrowdLevel.medium:
        return Colors.orange;
      case CrowdLevel.high:
        return Colors.red;
      case CrowdLevel.closed:
        return Colors.grey;
    }
  }

  int get _barsCount {
    switch (crowd) {
      case CrowdLevel.low:
        return 2;
      case CrowdLevel.medium:
        return 4;
      case CrowdLevel.high:
        return 6;
      case CrowdLevel.closed:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isClosed = crowd == CrowdLevel.closed;
    final t = AppLocalizations.of(context)!;

    return InkWell(
      onTap: isClosed
          ? () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.cafeClosedNow)),
        );
      }
          : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: isClosed ? 0.78 : 1,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isClosed
                  ? Colors.grey.withOpacity(0.35)
                  : _primary.withOpacity(0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: 12,
                offset: const Offset(0, 6),
                color: Colors.black.withOpacity(0.08),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Image.asset(
                      cafe.logoAsset,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          width: 64,
                          height: 64,
                          color: Colors.black.withOpacity(0.06),
                          child: const Icon(Icons.local_cafe),
                        );
                      },
                    ),
                    if (isClosed)
                      Positioned.fill(
                        child: Container(
                          color: Colors.white.withOpacity(0.45),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cafe.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isClosed ? Colors.grey.shade700 : _primary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.black.withOpacity(0.55),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _distanceText(context),
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.55),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          _crowdedLabel(context),
                          style: TextStyle(
                            color: isClosed
                                ? Colors.grey.shade700
                                : _primary.withOpacity(0.85),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _CrowdBars(bars: _barsCount, color: _crowdColor),
                      ],
                    ),
                  ],
                ),
              ),
              if (isClosed)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    t.closed,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrowdBars extends StatelessWidget {
  final int bars;
  final Color color;

  const _CrowdBars({required this.bars, required this.color});

  @override
  Widget build(BuildContext context) {
    const total = 6;
    return Row(
      children: List.generate(total, (i) {
        final active = i < bars;
        return Container(
          margin: const EdgeInsets.only(right: 4),
          width: 10,
          height: 10 + (i * 3),
          decoration: BoxDecoration(
            color: active ? color : Colors.black.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 75,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                label: t.home,
                active: index == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.receipt_long_outlined,
                label: t.orders,
                active: index == 1,
                onTap: () => onTap(1),
              ),
              const SizedBox(width: 44),
              _NavItem(
                icon: Icons.notifications_none,
                label: t.notification,
                active: index == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: t.profile,
                active: index == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  static const _primary = Color(0xFF0E6F73);

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? _primary : Colors.black.withOpacity(0.35);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _StickyHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}