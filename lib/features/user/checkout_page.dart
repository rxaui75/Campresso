// checkout_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pay/pay.dart';
import 'package:http/http.dart' as http;
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import 'cart_controller.dart';
import 'order_service.dart';
import 'order_success_page.dart';
import 'package:campresso/features/user/delivery/delivery_waiting_page.dart';

enum TransportMode { walking, metro, delivery }
enum PaymentMethod { cashOnDelivery, onlinePay, wallet }

class CheckoutPage extends StatefulWidget {
  final String cafeId;
  final double distanceKm;
  final String crowdLevel; // Low / Medium / High

  const CheckoutPage({
    super.key,
    required this.cafeId,
    required this.distanceKm,
    required this.crowdLevel,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  bool pickupNow = true;
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();

  TransportMode mode = TransportMode.walking;
  PaymentMethod paymentMethod = PaymentMethod.cashOnDelivery;

  bool _placing = false;

  double _deliveryTip = 0.0;

  bool _deliveryAvailable = false;
  bool _checkingDeliveryAvailability = false;
  int _availableDeliveryGirlsCount = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _deliveryAvailabilitySub;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _walletBalanceSub;
  double _walletBalanceSar = 0.0;
  bool _loadingWalletBalance = true;

  bool _loadingDeliveryLocation = false;
  String _deliveryLocationText = '';
  GeoPoint? _deliveryLocationPoint;
  bool _isDefaultDeliveryLocation = true;

  late final Future<PaymentConfiguration> _applePayConfigFuture =
  PaymentConfiguration.fromAsset('pay/apple_pay.json');

  late final Future<PaymentConfiguration> _googlePayConfigFuture =
  PaymentConfiguration.fromAsset('pay/google_pay.json');

  final Map<String, String> _imageUrlCache = {};

  // Google Maps Distance Matrix API key.
  // Run the app with:
  // flutter run --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY
  static const String _googleMapsApiKey =
  String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');

  GeoPoint? _cafeLocationPoint;
  int? _googleJourneyMinutes;
  bool _loadingGoogleJourneyMinutes = false;
  String? _lastGoogleJourneyKey;

  String _selectedMetroStation = 'A1';

  static const List<String> _stationOptions = <String>[
    'A1',
    'A2',
    'A3',
    'A4',
    'A5',
    'A6',
    'A7',
    'A8',
    'A9',
    'A10',
  ];

  static const List<String> _floorOptions = <String>[
    '0',
    '1',
    '2',
  ];

  static const List<String> _collegeOptions = <String>[
    'College of Engineering',
    'College of Computer and Information Sciences',
    'College of Science',
    'College of Sport Sciences and Physical Activity',
    'College of Business Administration',
    'College of Health and Rehabilitation Sciences',
    'College of Medicine',
    'College of Nursing',
    'College of Pharmacy',
    'College of Dentistry',
    'Foundation Year for Health Colleges',
    'Applied College',
    'College of Education and Human Development',
    'College of Languages',
    'College of Art and Design',
    'College of Law',
    'College of Humanities and Social Sciences',
    'Arabic Teaching Institute for Non-Arabic Speakers',
    'English Language Institute',
  ];

  @override
  void initState() {
    super.initState();

    rootBundle.loadString('pay/google_pay.json').then((_) {
      debugPrint('✅ google_pay.json loaded OK');
    }).catchError((e) {
      debugPrint('❌ google_pay.json failed: $e');
    });

    _ensurePaymentForMode();
    _startDeliveryAvailabilityListener();
    _startWalletBalanceListener();
    _loadCafeLocation();
    _loadDefaultDeliveryLocation();
  }

  @override
  void dispose() {
    _deliveryAvailabilitySub?.cancel();
    _walletBalanceSub?.cancel();
    super.dispose();
  }

  GeoPoint? _extractGeoPointFromMap(Map<String, dynamic> data) {
    final location = data['location'];
    if (location is GeoPoint) return location;

    final geoPoint = data['geoPoint'];
    if (geoPoint is GeoPoint) return geoPoint;

    final coordinates = data['coordinates'];
    if (coordinates is GeoPoint) return coordinates;

    final lat = data['lat'] ?? data['latitude'];
    final lng = data['lng'] ?? data['longitude'];
    if (lat is num && lng is num) {
      return GeoPoint(lat.toDouble(), lng.toDouble());
    }

    return null;
  }

  Future<void> _loadCafeLocation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('cafes')
          .doc(widget.cafeId)
          .get();

      final data = doc.data() ?? {};
      final point = _extractGeoPointFromMap(data);

      if (!mounted) return;
      setState(() => _cafeLocationPoint = point);
      _refreshGoogleJourneyMinutes(force: true);
    } catch (e) {
      debugPrint('❌ Failed to load cafe location: $e');
    }
  }

  GeoPoint? get _currentCustomerPoint => _deliveryLocationPoint;

  bool get _canRequestGoogleJourneyMinutes =>
      mode == TransportMode.walking &&
          _googleMapsApiKey.trim().isNotEmpty &&
          _cafeLocationPoint != null &&
          _currentCustomerPoint != null;

  String _googleTravelModeForMode(TransportMode selectedMode) {
    return 'walking';
  }

  static const Map<String, String> _cafeStationById = {
    // Update these values if a cafe is closer to a different station.
    'dunkin': 'A4',
    'window': 'A3',
    'selu': 'A4',
    'default': 'A3',
  };

  String _cafeStationForCurrentCafe() {
    final rawId = widget.cafeId.toLowerCase().trim();

    for (final entry in _cafeStationById.entries) {
      if (entry.key == 'default') continue;
      if (rawId == entry.key || rawId.contains(entry.key)) {
        return entry.value;
      }
    }

    return _cafeStationById['default'] ?? 'A3';
  }

  MetroRouteInfo _metroRouteInfo() {
    final from = _selectedMetroStation;
    final to = _cafeStationForCurrentCafe();
    final fromIndex = _stationOptions.indexOf(from);
    final toIndex = _stationOptions.indexOf(to);

    if (fromIndex == -1 || toIndex == -1) {
      return MetroRouteInfo(
        fromStation: from,
        toStation: to,
        stops: 0,
        lineName: 'Blue Line',
        lineColor: const Color(0xFF1976D2),
        directionLabel: 'Direct route',
      );
    }

    final stationCount = _stationOptions.length;
    final ascendingStops = (toIndex - fromIndex + stationCount) % stationCount;
    final descendingStops = (fromIndex - toIndex + stationCount) % stationCount;

    final useAscending = ascendingStops <= descendingStops;
    return MetroRouteInfo(
      fromStation: from,
      toStation: to,
      stops: useAscending ? ascendingStops : descendingStops,
      lineName: useAscending ? 'Blue Line' : 'Purple Line',
      lineColor: useAscending ? const Color(0xFF1976D2) : const Color(0xFF7B1FA2),
      directionLabel: useAscending
          ? 'A1 → A10 direction'
          : 'A10 → A1 direction',
    );
  }

  int _metroJourneyMinutes() {
    final route = _metroRouteInfo();

    const walkToStation = 3;
    const averageWaitingTime = 3;
    const minutesPerStop = 2;
    const walkFromStationToCafe = 3;

    return (walkToStation +
        averageWaitingTime +
        (route.stops * minutesPerStop) +
        walkFromStationToCafe)
        .clamp(1, 9999);
  }

  int _manualJourneyMinutesFallback() {
    final d = widget.distanceKm;
    switch (mode) {
      case TransportMode.walking:
        return (d / 5.0 * 60).round().clamp(1, 9999);
      case TransportMode.metro:
        return _metroJourneyMinutes();
      case TransportMode.delivery:
        return 0;
    }
  }

  Future<int?> _fetchGoogleJourneyMinutes({
    required GeoPoint origin,
    required GeoPoint destination,
    required TransportMode selectedMode,
  }) async {
    if (_googleMapsApiKey.trim().isEmpty) {
      throw Exception('GOOGLE_MAPS_API_KEY is empty. Run with --dart-define.');
    }

    final travelMode = _googleTravelModeForMode(selectedMode);
    final params = <String, String>{
      'origins': '${origin.latitude},${origin.longitude}',
      'destinations': '${destination.latitude},${destination.longitude}',
      'mode': travelMode,
      'units': 'metric',
      'key': _googleMapsApiKey,
    };

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/distancematrix/json',
      params,
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Google Maps API HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['status'] != 'OK') {
      throw Exception(
        'Google Maps API status: ${json['status']} ${json['error_message'] ?? ''}',
      );
    }

    final rows = json['rows'];
    if (rows is! List || rows.isEmpty) {
      throw Exception('Google Maps API returned no rows');
    }

    final elements = rows.first['elements'];
    if (elements is! List || elements.isEmpty) {
      throw Exception('Google Maps API returned no elements');
    }

    final element = elements.first as Map<String, dynamic>;
    if (element['status'] != 'OK') {
      throw Exception('Google Maps route status: ${element['status']}');
    }

    final durationSource =
        element['duration_in_traffic'] ?? element['duration'];
    if (durationSource is! Map<String, dynamic>) {
      throw Exception('Google Maps API returned no duration');
    }

    final rawSeconds = durationSource['value'];
    if (rawSeconds is! num) {
      throw Exception('Google Maps API duration value is invalid');
    }

    final routeMinutes = ((rawSeconds.toInt() + 59) ~/ 60).clamp(1, 9999);

    return routeMinutes;
  }

  Future<void> _refreshGoogleJourneyMinutes({bool force = false}) async {
    if (mode != TransportMode.walking) {
      if (!mounted) return;
      setState(() {
        _googleJourneyMinutes = null;
        _loadingGoogleJourneyMinutes = false;
      });
      return;
    }

    if (_googleMapsApiKey.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _googleJourneyMinutes = null;
        _loadingGoogleJourneyMinutes = false;
      });
      return;
    }

    final cafePoint = _cafeLocationPoint;
    final customerPoint = _currentCustomerPoint;

    if (cafePoint == null || customerPoint == null) {
      if (!mounted) return;
      setState(() {
        _googleJourneyMinutes = null;
        _loadingGoogleJourneyMinutes = false;
      });
      return;
    }

    final selectedMode = mode;
    final origin = customerPoint;
    final destination = cafePoint;

    final requestKey = [
      selectedMode.name,
      origin.latitude.toStringAsFixed(6),
      origin.longitude.toStringAsFixed(6),
      destination.latitude.toStringAsFixed(6),
      destination.longitude.toStringAsFixed(6),
    ].join('|');

    if (!force && requestKey == _lastGoogleJourneyKey) return;
    _lastGoogleJourneyKey = requestKey;

    if (mounted) {
      setState(() => _loadingGoogleJourneyMinutes = true);
    }

    try {
      final minutes = await _fetchGoogleJourneyMinutes(
        origin: origin,
        destination: destination,
        selectedMode: selectedMode,
      );

      if (!mounted) return;
      setState(() {
        _googleJourneyMinutes = minutes;
        _loadingGoogleJourneyMinutes = false;
      });
    } catch (e) {
      debugPrint('❌ Google walking duration failed: $e');
      if (!mounted) return;
      setState(() {
        _googleJourneyMinutes = null;
        _loadingGoogleJourneyMinutes = false;
      });
    }
  }

  void _startWalletBalanceListener() {
    _walletBalanceSub?.cancel();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _walletBalanceSar = 0.0;
          _loadingWalletBalance = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loadingWalletBalance = true);
    }

    _walletBalanceSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      final data = doc.data() ?? {};
      final raw = data['walletBalanceSar'];
      double balance = 0.0;

      if (raw is num) {
        balance = raw.toDouble();
      }

      if (!mounted) return;

      setState(() {
        _walletBalanceSar = balance;
        _loadingWalletBalance = false;
      });

      if (!_walletCanCoverCurrentTotal &&
          paymentMethod == PaymentMethod.wallet &&
          mode != TransportMode.delivery) {
        setState(() {
          paymentMethod = PaymentMethod.cashOnDelivery;
        });
      }
    }, onError: (e) {
      debugPrint('❌ Wallet balance listener failed: $e');
      if (!mounted) return;
      setState(() {
        _walletBalanceSar = 0.0;
        _loadingWalletBalance = false;
      });
    });
  }

  bool get _walletCanCoverCurrentTotal {
    final total = _grandTotal(CartController.instance.totalPrice);
    return _walletBalanceSar + 0.0001 >= total;
  }

  Future<void> _loadDefaultDeliveryLocation() async {
    if (_loadingDeliveryLocation) return;

    setState(() => _loadingDeliveryLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _deliveryLocationText = '';
          _deliveryLocationPoint = null;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _deliveryLocationText = '';
          _deliveryLocationPoint = null;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final point = GeoPoint(pos.latitude, pos.longitude);
      final text = await _reverseGeocode(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() {
        _deliveryLocationPoint = point;
        _deliveryLocationText = text;
        _isDefaultDeliveryLocation = true;
        _lastGoogleJourneyKey = null;
      });
      _refreshGoogleJourneyMinutes(force: true);
    } catch (e) {
      debugPrint('❌ Failed to load default delivery location: $e');
      if (!mounted) return;
      setState(() {
        _deliveryLocationText = '';
        _deliveryLocationPoint = null;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingDeliveryLocation = false);
      }
    }
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      if (places.isNotEmpty) {
        final p = places.first;
        final parts = [
          p.name,
          p.street,
          p.subLocality,
          p.locality,
        ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();

        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (e) {
      debugPrint('❌ reverse geocode failed: $e');
    }

    return "${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}";
  }

  String _formatManualDeliveryLocation({
    required String station,
    required String college,
    required String floor,
    required String room,
    required AppLocalizations t,
  }) {
    final parts = <String>[
      '${t.deliveryStationLabel}: $station',
      college,
      '${t.deliveryFloorLabel}: $floor',
    ];

    final trimmedRoom = room.trim();
    if (trimmedRoom.isNotEmpty) {
      parts.add('${t.deliveryRoomLabel}: $trimmedRoom');
    }

    return parts.join(' • ');
  }

  Future<void> _changeDeliveryLocationManually() async {
    final t = AppLocalizations.of(context)!;

    String selectedStation = _stationOptions.first;
    String selectedCollege = _collegeOptions.first;
    String selectedFloor = _floorOptions.first;
    final roomController = TextEditingController();

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 18,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t.changeDeliveryLocation,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _pickerField(
                        label: t.deliveryStationLabel,
                        child: DropdownButtonFormField<String>(
                          value: selectedStation,
                          items: _stationOptions
                              .map(
                                (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setModalState(() => selectedStation = v);
                          },
                          decoration: _pickerDecoration(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pickerField(
                        label: t.deliveryCollegeLabel,
                        child: DropdownButtonFormField<String>(
                          value: selectedCollege,
                          items: _collegeOptions
                              .map(
                                (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(
                                e,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setModalState(() => selectedCollege = v);
                          },
                          decoration: _pickerDecoration(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pickerField(
                        label: t.deliveryFloorLabel,
                        child: DropdownButtonFormField<String>(
                          value: selectedFloor,
                          items: _floorOptions
                              .map(
                                (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setModalState(() => selectedFloor = v);
                          },
                          decoration: _pickerDecoration(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pickerField(
                        label: t.deliveryRoomLabel,
                        child: TextField(
                          controller: roomController,
                          decoration: _pickerDecoration(
                            hintText: t.deliveryRoomHint,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(t.cancel),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx, {
                                  'station': selectedStation,
                                  'college': selectedCollege,
                                  'floor': selectedFloor,
                                  'room': roomController.text.trim(),
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0E6F73),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                t.save,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
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
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    final station = result['station'] ?? _stationOptions.first;
    final college = result['college'] ?? _collegeOptions.first;
    final floor = result['floor'] ?? _floorOptions.first;
    final room = result['room'] ?? '';

    setState(() {
      _deliveryLocationText = _formatManualDeliveryLocation(
        station: station,
        college: college,
        floor: floor,
        room: room,
        t: t,
      );
      _deliveryLocationPoint = null;
      _isDefaultDeliveryLocation = false;
      _googleJourneyMinutes = null;
      _lastGoogleJourneyKey = null;
    });
    _refreshGoogleJourneyMinutes(force: true);
  }

  InputDecoration _pickerDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: Colors.black.withOpacity(0.03),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Color(0xFF0E6F73), width: 1.4),
      ),
    );
  }

  Widget _pickerField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.black.withOpacity(0.6),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Future<void> _saveDeliveryLocationToOrder(String orderId) async {
    if (_deliveryLocationText.trim().isEmpty) return;

    await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
      'deliveryLocationText': _deliveryLocationText.trim(),
      'isDefaultDeliveryLocation': _isDefaultDeliveryLocation,
      'deliveryTravelMode': 'pending',
      'deliveryEstimatedMinutes': null,
      if (_deliveryLocationPoint != null)
        'deliveryLocation': _deliveryLocationPoint,
    }, SetOptions(merge: true));
  }

  bool _isHttpUrl(String s) =>
      s.startsWith('http://') || s.startsWith('https://');
  bool _isGsUrl(String s) => s.startsWith('gs://');

  Future<String?> _resolveAnyImageToUrl(String raw) async {
    final src = raw.trim();
    if (src.isEmpty) return null;

    final cached = _imageUrlCache[src];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      if (_isHttpUrl(src)) {
        _imageUrlCache[src] = src;
        return src;
      }

      if (_isGsUrl(src)) {
        final ref = FirebaseStorage.instance.refFromURL(src);
        final url = await ref.getDownloadURL();
        _imageUrlCache[src] = url;
        return url;
      }

      if (src.contains('/')) {
        final ref = FirebaseStorage.instance.ref(src);
        final url = await ref.getDownloadURL();
        _imageUrlCache[src] = url;
        return url;
      }

      return null;
    } catch (e) {
      debugPrint("❌ resolve image failed for '$src': $e");
      return null;
    }
  }

  void _startDeliveryAvailabilityListener() {
    _deliveryAvailabilitySub?.cancel();

    if (mounted) {
      setState(() => _checkingDeliveryAvailability = true);
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;

    _deliveryAvailabilitySub = FirebaseFirestore.instance
        .collection('users')
        .where('availableForDelivery', isEqualTo: true)
        .limit(30)
        .snapshots()
        .listen((qs) {
      final activeAfter = DateTime.now().subtract(const Duration(minutes: 10));

      int availableCount = 0;

      for (final doc in qs.docs) {
        if (myUid != null && doc.id == myUid) continue;

        final data = doc.data();
        final ts = data['deliveryLastActiveAt'];
        if (ts is! Timestamp) continue;

        final lastActive = ts.toDate();
        if (lastActive.isAfter(activeAfter)) {
          availableCount++;
        }
      }

      if (!mounted) return;

      final available = availableCount > 0;
      final wasDeliverySelected = mode == TransportMode.delivery;

      setState(() {
        _availableDeliveryGirlsCount = availableCount;
        _deliveryAvailable = available;
        _checkingDeliveryAvailability = false;
      });

      if (!available && wasDeliverySelected && mounted) {
        final t = AppLocalizations.of(context)!;
        setState(() {
          mode = TransportMode.walking;
          _ensurePaymentForMode();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.deliveryNotAvailableNow)),
        );
      }
    }, onError: (e) {
      debugPrint("❌ Delivery availability listener failed: $e");
      if (!mounted) return;
      setState(() {
        _deliveryAvailable = false;
        _availableDeliveryGirlsCount = 0;
        _checkingDeliveryAvailability = false;
      });
    });
  }

  Future<void> _refreshDeliveryAvailability() async {
    _startDeliveryAvailabilityListener();
  }
  double _suggestedTip(double distanceKm) {
    if (distanceKm <= 1.0) return 5.0;
    if (distanceKm <= 3.0) return 10.0;
    return 15.0;
  }

  void _ensurePaymentForMode() {
    final isDelivery = mode == TransportMode.delivery;

    if (isDelivery) {
      final suggested = _suggestedTip(widget.distanceKm);
      if ((_deliveryTip - suggested).abs() > 0.01) {
        _deliveryTip = suggested;
      }

      if (paymentMethod == PaymentMethod.wallet) {
        paymentMethod = PaymentMethod.cashOnDelivery;
      }
    } else {
      if (_deliveryTip != 0.0) _deliveryTip = 0.0;
    }
  }

  int _crowdDelayMinutes() {
    final c = widget.crowdLevel.toLowerCase().trim();
    if (c == 'high') return 6;
    if (c == 'medium') return 3;
    return 0;
  }

  int _journeyMinutes() {
    if (mode == TransportMode.delivery) return 0;
    return (_googleJourneyMinutes ?? _manualJourneyMinutesFallback()).clamp(1, 9999);
  }

  String _journeyMinutesLabel(AppLocalizations t, int journey) {
    if (mode == TransportMode.walking &&
        _loadingGoogleJourneyMinutes &&
        _googleJourneyMinutes == null) {
      return '...';
    }

    return '+${t.minutesCount(journey)}';
  }

  int _prepMinutes() => CartController.instance.prepTimeMinutes;
  int _totalMinutes() {
    if (mode == TransportMode.delivery) {
      return _prepMinutes() + _crowdDelayMinutes();
    }
    return _prepMinutes() + _journeyMinutes() + _crowdDelayMinutes();
  }

  DateTime _pickupStartDateTime() {
    if (pickupNow) return DateTime.now();
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: selectedDate.isBefore(now) ? now : selectedDate,
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );
    if (picked != null) setState(() => selectedTime = picked);
  }

  List<PaymentItem> _paymentItems(double total, AppLocalizations t) => [
    PaymentItem(
      label: t.checkoutTotalLabel,
      amount: total.toStringAsFixed(2),
      status: PaymentItemStatus.final_price,
    ),
  ];

  double _grandTotal(double cartTotal) {
    if (mode == TransportMode.delivery) {
      return (cartTotal + _deliveryTip).clamp(0, 999999);
    }
    return cartTotal;
  }

  Future<void> _placeOrder({required String paymentMethodValue}) async {
    final t = AppLocalizations.of(context)!;
    if (_placing) return;

    final cart = CartController.instance;
    if (cart.items.isEmpty) return;

    _ensurePaymentForMode();

    final isDelivery = mode == TransportMode.delivery;

    if (isDelivery) {
      if (_deliveryLocationText.trim().isEmpty) {
        await _loadDefaultDeliveryLocation();
      }

      if (_deliveryLocationText.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.deliveryLocationRequired)),
        );
        return;
      }
    }

    setState(() => _placing = true);

    if (_canRequestGoogleJourneyMinutes && _googleJourneyMinutes == null) {
      await _refreshGoogleJourneyMinutes(force: true);
    }

    final pickupAt = _pickupStartDateTime();
    final estimated = isDelivery ? (_prepMinutes() + _crowdDelayMinutes()) : _totalMinutes();

    final cartAmount = cart.totalPrice;
    final tip = isDelivery ? _suggestedTip(widget.distanceKm) : 0.0;
    final grandTotal = isDelivery ? (cartAmount + tip) : cartAmount;

    final cafeName = widget.cafeId;
    final now = DateTime.now();
    final expireAt = now.add(const Duration(minutes: 5));

    try {
      final orderId = await OrderService.instance.createOrder(
        cafeId: widget.cafeId,
        cafeName: cafeName,
        pickupAt: pickupAt,
        transportMode: mode.name,
        paymentMethod: isDelivery ? "pending" : paymentMethodValue,
        estimatedMinutes: estimated,
        amountPaid: cartAmount,
        itemsCount: cart.itemsCount,
        items: cart.items,
        fulfillment: isDelivery ? 'delivery' : 'pickup',
        deliveryStatus: isDelivery ? 'waiting' : null,
        deliveryExpireAt: isDelivery ? expireAt : null,
        statusOverride: 'placed',
        deliveryTip: tip,
        grandTotal: grandTotal,
      );
      if (isDelivery) {
        await _saveDeliveryLocationToOrder(orderId);
      }
      final orderNumber = orderId.hashCode.abs() % 100000;
      cart.clear();
      if (!mounted) return;

      if (isDelivery) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DeliveryWaitingPage(
              orderId: orderId,
              orderNumber: orderNumber,
            ),
          ),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderSuccessPage(
            orderId: orderId,
            orderNumber: orderNumber,
            estimatedMinutes: estimated,
            amountPaid: cartAmount,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _placeOrderCash() async =>
      _placeOrder(paymentMethodValue: "cash");

  Future<void> _placeOrderDeliveryNoPay() async =>
      _placeOrder(paymentMethodValue: "pending");

  Future<void> _placeOrderWallet() async {
    final t = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    final cart = CartController.instance;

    if (user == null || cart.items.isEmpty || _placing) return;

    final isDelivery = mode == TransportMode.delivery;
    if (isDelivery) return;

    final total = _grandTotal(cart.totalPrice);

    if (_walletBalanceSar + 0.0001 < total) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.checkoutWalletInsufficientBalance)),
      );
      return;
    }

    setState(() => _placing = true);

    try {
      final orderResult = await _createWalletOrderTransaction();

      final orderId = orderResult.$1;
      final orderNumber = orderResult.$2;
      final estimated = orderResult.$3;
      final cartAmount = orderResult.$4;

      cart.clear();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderSuccessPage(
            orderId: orderId,
            orderNumber: orderNumber,
            estimatedMinutes: estimated,
            amountPaid: cartAmount,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t.error}: $e")),
      );
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<(String, int, int, double)> _createWalletOrderTransaction() async {
    final t = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    final cart = CartController.instance;

    if (user == null) {
      throw Exception("User not logged in");
    }

    if (cart.items.isEmpty) {
      throw Exception("Cart is empty");
    }

    if (_canRequestGoogleJourneyMinutes && _googleJourneyMinutes == null) {
      await _refreshGoogleJourneyMinutes(force: true);
    }

    final pickupAt = _pickupStartDateTime();
    final estimated = _totalMinutes();
    final cartAmount = cart.totalPrice;
    final grandTotal = _grandTotal(cartAmount);

    final orders = FirebaseFirestore.instance.collection('orders');
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final orderDoc = orders.doc();

    final myProfile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final profile = myProfile.data() ?? {};

    String pickBestNameFromProfile(Map<String, dynamic> p) {
      final full = (p['fullName'] ?? '').toString().trim();
      if (full.isNotEmpty) return full;

      final first = (p['firstName'] ?? '').toString().trim();
      final last = (p['lastName'] ?? '').toString().trim();
      final combined = [first, last].where((x) => x.isNotEmpty).join(' ').trim();
      if (combined.isNotEmpty) return combined;

      final dn = (user.displayName ?? '').trim();
      if (dn.isNotEmpty) return dn;

      final email = (p['email'] ?? '').toString().trim();
      if (email.isNotEmpty) return email;

      return "Customer";
    }

    final customerName = pickBestNameFromProfile(profile);
    final customerPhone = (profile['phoneNumber'] ?? '').toString().trim();
    final orderNumber =
        10000 + (DateTime.now().millisecondsSinceEpoch % 90000);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? {};

      final raw = userData['walletBalanceSar'];
      double balance = 0.0;
      if (raw is num) balance = raw.toDouble();

      if (balance + 0.0001 < grandTotal) {
        throw Exception(t.checkoutWalletInsufficientBalance);
      }

      final orderData = <String, dynamic>{
        "userId": user.uid,
        "customerId": user.uid,
        "orderNumber": orderNumber,

        "customerName": customerName,
        if (customerPhone.isNotEmpty) "customerPhone": customerPhone,

        "cafeId": widget.cafeId,
        "cafeName": widget.cafeId,

        "status": "placed",
        "createdAt": FieldValue.serverTimestamp(),
        "pickupAt": Timestamp.fromDate(pickupAt),

        "transportMode": mode.name,

        "paymentMethod": "wallet",
        "paymentStatus": "paid",

        "estimatedMinutes": estimated,
        "itemsCount": cart.itemsCount,

        "amountPaid": cartAmount,
        "deliveryTip": 0.0,
        "grandTotal": grandTotal,
        "paidAmount": cartAmount,

        "cafeAmount": cartAmount,
        "tipAmount": 0.0,
        "tipStatus": "none",

        "fulfillment": "pickup",

        "walletAmountUsed": grandTotal,

        "items": cart.items.map((it) {
          return {
            "productId": it.productId,
            "name": it.name,
            "imageAsset": it.imageAsset,
            "qty": it.qty,
            "unitPrice": it.unitPrice,
            "lineTotal": it.lineTotal,
            "prepMinutes": it.prepMinutes,
            "calories": it.calories,
            "selectedOptions": it.selectedOptions.map((o) {
              return {
                "groupId": o.groupId,
                "groupTitle": o.groupTitle,
                "optionId": o.optionId,
                "optionName": o.optionName,
                "qty": o.qty,
                "priceDelta": o.priceDelta,
              };
            }).toList(),
          };
        }).toList(),
      };

      tx.set(orderDoc, orderData);
      tx.set(
        userRef,
        {
          'walletBalanceSar': balance - grandTotal,
        },
        SetOptions(merge: true),
      );
    });

    return (orderDoc.id, orderNumber, estimated, cartAmount);
  }

  Future<void> _onOnlinePaySuccess(dynamic result) async {
    debugPrint("✅ ONLINE PAY RESULT: $result");
    await _placeOrder(paymentMethodValue: "online");
  }

  Widget _platformPayButton(double totalPrice, AppLocalizations t) {
    final items = _paymentItems(totalPrice, t);

    if (Platform.isIOS) {
      return FutureBuilder<PaymentConfiguration>(
        future: _applePayConfigFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text("Apple Pay config error: ${snapshot.error}");
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ApplePayButton(
            paymentConfiguration: snapshot.data!,
            paymentItems: items,
            style: ApplePayButtonStyle.black,
            type: ApplePayButtonType.buy,
            onPaymentResult: (result) async {
              debugPrint("✅ APPLE PAY RESULT: $result");
              await _placeOrder(paymentMethodValue: "online");
            },
            onError: (error) {
              debugPrint("❌ APPLE PAY ERROR: $error");
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("${t.applePayError}: $error")),
              );
            },
            loadingIndicator: const Center(child: CircularProgressIndicator()),
          );
        },
      );
    }

    return FutureBuilder<PaymentConfiguration>(
      future: _googlePayConfigFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text("Google Pay config error: ${snapshot.error}");
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return GooglePayButton(
          paymentConfiguration: snapshot.data!,
          paymentItems: items,
          type: GooglePayButtonType.pay,
          onPaymentResult: _onOnlinePaySuccess,
          onError: (error) {
            debugPrint("❌ GOOGLE PAY ERROR: $error");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${t.googlePayError}: $error")),
            );
          },
          loadingIndicator: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const teal = Color(0xFF0E6F73);
    final cart = CartController.instance;

    return AnimatedBuilder(
      animation: cart,
      builder: (_, __) {
        _ensurePaymentForMode();
        if (mode == TransportMode.walking) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refreshGoogleJourneyMinutes();
          });
        }

        if (!_walletCanCoverCurrentTotal &&
            paymentMethod == PaymentMethod.wallet &&
            mode != TransportMode.delivery) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              paymentMethod = PaymentMethod.cashOnDelivery;
            });
          });
        }

        if (cart.items.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0.6,
              centerTitle: true,
              title: Text(
                t.checkoutTitle,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Center(
              child: Text(
                t.checkoutCartEmpty,
                style: TextStyle(color: Colors.black.withOpacity(0.6)),
              ),
            ),
          );
        }

        final prep = _prepMinutes();
        final journey = _journeyMinutes();
        final crowd = _crowdDelayMinutes();
        final totalMin = _totalMinutes();

        final start = _pickupStartDateTime();
        final readyAt = start.add(Duration(minutes: prep + crowd));
        final arriveAt = start.add(Duration(minutes: totalMin));

        String fmt2(int v) => v.toString().padLeft(2, '0');

        String mon(int m) => const [
          "Jan",
          "Feb",
          "Mar",
          "Apr",
          "May",
          "Jun",
          "Jul",
          "Aug",
          "Sep",
          "Oct",
          "Nov",
          "Dec"
        ][(m - 1).clamp(0, 11)];

        String dateLabel(DateTime d) => "${mon(d.month)} ${d.day}, ${d.year}";
        String timeLabel(DateTime d) {
          final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
          final ampm = d.hour >= 12 ? "PM" : "AM";
          return "$h:${fmt2(d.minute)} $ampm";
        }

        final scheduleDt = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          selectedTime.hour,
          selectedTime.minute,
        );

        final cartTotal = cart.totalPrice;
        final grandTotal = _grandTotal(cartTotal);

        final isDelivery = mode == TransportMode.delivery;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.6,
            centerTitle: true,
            title: Text(
              t.checkoutTitle,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                tooltip: t.checkoutRefresh,
                onPressed: _checkingDeliveryAvailability
                    ? null
                    : _refreshDeliveryAvailability,
                icon: _checkingDeliveryAvailability
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.refresh, color: Colors.black87),
              ),
            ],
          ),
          body: AbsorbPointer(
            absorbing: _placing,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
              children: [
                _sectionTitle(t.checkoutSelectPickupTime),
                const SizedBox(height: 10),
                _segmentedPickup(t),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _chipButton(
                        label: pickupNow
                            ? dateLabel(DateTime.now())
                            : dateLabel(scheduleDt),
                        onTap: pickupNow ? null : _pickDate,
                        disabled: pickupNow,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _chipButton(
                        label: pickupNow
                            ? timeLabel(DateTime.now())
                            : timeLabel(scheduleDt),
                        onTap: pickupNow ? null : _pickTime,
                        disabled: pickupNow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _sectionTitle(t.checkoutSelectTransportMode),
                const SizedBox(height: 10),
                _transportModeCard(t),
                if (mode == TransportMode.metro) ...[
                  const SizedBox(height: 10),
                  _metroStationSelectorCard(),
                ],
                if (!_deliveryAvailable) ...[
                  const SizedBox(height: 8),
                  Text(
                    t.deliveryNotAvailableNow,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (isDelivery) ...[
                  _sectionTitle(t.deliveryLocationTitle),
                  const SizedBox(height: 10),
                  _deliveryLocationCard(t),
                  const SizedBox(height: 16),
                ],
                if (isDelivery) ...[
                  _sectionTitle(t.deliveryTipTitle),
                  const SizedBox(height: 10),
                  _tipCardAutoSimplified(t),
                  const SizedBox(height: 16),
                ],
                _sectionTitle(t.checkoutYourEstimatedPickup),
                const SizedBox(height: 10),
                if (mode == TransportMode.delivery) ...[
                  _estimateRow(t.checkoutPreparationTime, t.minutesCount(prep)),
                  _estimateRow(
                      t.checkoutPeakHourDelay, "+${t.minutesCount(crowd)}"),
                  const SizedBox(height: 10),
                  _deliveryPendingEstimateCard(),
                ] else ...[
                  if (mode == TransportMode.metro) ...[
                    _metroRouteCard(),
                    const SizedBox(height: 10),
                  ],
                  _estimateRow(t.checkoutPreparationTime, t.minutesCount(prep)),
                  _estimateRow(
                    t.checkoutJourneyTime,
                    _journeyMinutesLabel(t, journey),
                  ),
                  _estimateRow(
                      t.checkoutPeakHourDelay, "+${t.minutesCount(crowd)}"),
                  const SizedBox(height: 10),
                  Divider(color: Colors.black.withOpacity(0.08)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t.checkoutTotalEstimatedTime,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        t.minutesCount(totalMin),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "${t.checkoutReadyAround}: ${timeLabel(readyAt)}",
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${t.checkoutArriveReceiveAround}: ${timeLabel(arriveAt)}",
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (!isDelivery) ...[
                  _sectionTitle(t.checkoutPaymentMethod),
                  const SizedBox(height: 10),
                  _paymentMethodTile(teal, grandTotal, t, isDelivery: false),
                ] else ...[
                  _sectionTitle(t.checkoutPaymentMethod),
                  const SizedBox(height: 8),
                  Text(
                    t.deliveryOnlineOnlyNote,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _sectionTitle(t.checkoutYourCart),
                const SizedBox(height: 10),
                for (final item in cart.items)
                  _CartItemTile(
                    itemKey: item.key,
                    resolveAnyImageToUrl: _resolveAnyImageToUrl,
                  ),
                const SizedBox(height: 12),
                _SummaryBox(total: grandTotal, itemsCount: cart.itemsCount),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
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
              child: SizedBox(
                height: 52,
                child: (mode == TransportMode.delivery)
                    ? ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _placing ? null : _placeOrderDeliveryNoPay,
                  child: _placing
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(
                    t.checkoutPlaceOrder,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                )
                    : (paymentMethod == PaymentMethod.cashOnDelivery
                    ? ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _placing ? null : _placeOrderCash,
                  child: _placing
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(
                    t.checkoutPlaceOrder,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                )
                    : paymentMethod == PaymentMethod.wallet
                    ? ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: (_placing || !_walletCanCoverCurrentTotal)
                      ? null
                      : _placeOrderWallet,
                  child: _placing
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(
                    t.checkoutPlaceOrder,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                )
                    : _platformPayButton(grandTotal, t)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metroStationSelectorCard() {
    const teal = Color(0xFF0E6F73);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.train_outlined, color: teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select your nearest metro station',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedMetroStation,
            items: _stationOptions
                .map(
                  (station) => DropdownMenuItem<String>(
                value: station,
                child: Text(station),
              ),
            )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedMetroStation = value);
            },
            decoration: _pickerDecoration(),
          ),
        ],
      ),
    );
  }

  Widget _metroRouteCard() {
    final route = _metroRouteInfo();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: route.lineColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: route.lineColor.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 48,
            decoration: BoxDecoration(
              color: route.lineColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggested ${route.lineName}',
                  style: TextStyle(
                    color: route.lineColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${route.fromStation} → ${route.toStation} • ${route.stops} stops',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  route.directionLabel,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryPendingEstimateCard() {
    const teal = Color(0xFF0E6F73);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: teal.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: teal.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The final delivery time will be shown after the delivery partner accepts the order and selects Walking or Metro.',
              style: TextStyle(
                color: Colors.black.withOpacity(0.65),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryLocationCard(AppLocalizations t) {
    const teal = Color(0xFF0E6F73);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.deliveryLocationTitle,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (_loadingDeliveryLocation)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _deliveryLocationText.trim().isEmpty
                ? t.deliveryLocationNotSet
                : _deliveryLocationText,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _loadingDeliveryLocation
                      ? null
                      : _loadDefaultDeliveryLocation,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: teal,
                    side: const BorderSide(color: teal, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    t.currentLocationShort,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _changeDeliveryLocationManually,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    t.changeDeliveryLocation,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tipCardAutoSimplified(AppLocalizations t) {
    const teal = Color(0xFF0E6F73);

    final suggested = _suggestedTip(widget.distanceKm);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t.deliveryTipValueLabel,
              style: TextStyle(
                color: Colors.black.withOpacity(0.65),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            t.amountSar(suggested.toStringAsFixed(0)),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: teal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.brown.shade600,
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
    );
  }

  Widget _segmentedPickup(AppLocalizations t) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segBtn(
              label: t.checkoutPickupNow,
              active: pickupNow,
              onTap: () => setState(() => pickupNow = true),
            ),
          ),
          Expanded(
            child: _segBtn(
              label: t.checkoutScheduleOrder,
              active: !pickupNow,
              onTap: () => setState(() => pickupNow = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segBtn({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: active ? Colors.black87 : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _chipButton({
    required String label,
    VoidCallback? onTap,
    bool disabled = false,
  }) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: disabled ? Colors.black.withOpacity(0.35) : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _transportModeCard(AppLocalizations t) {
    const teal = Color(0xFF0E6F73);

    Widget item(
        TransportMode m,
        IconData icon,
        String label, {
          bool enabled = true,
        }) {
      final active = mode == m;

      return Expanded(
        child: InkWell(
          onTap: !enabled
              ? null
              : () async {
            setState(() {
              mode = m;
              _googleJourneyMinutes = null;
              _lastGoogleJourneyKey = null;
              _ensurePaymentForMode();
            });
            if (m == TransportMode.walking) {
              _refreshGoogleJourneyMinutes(force: true);
            }

            if (m == TransportMode.delivery &&
                _deliveryLocationText.trim().isEmpty) {
              await _loadDefaultDeliveryLocation();
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Opacity(
            opacity: enabled ? 1.0 : 0.45,
            child: Container(
              height: 90,
              decoration: BoxDecoration(
                color: active
                    ? teal.withOpacity(0.10)
                    : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active
                      ? teal.withOpacity(0.6)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 34, color: active ? teal : Colors.black54),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: active ? teal : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final deliveryLabel =
        "${t.checkoutDelivery} (${_availableDeliveryGirlsCount})";
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          item(TransportMode.walking, Icons.directions_walk, t.checkoutWalking),
          const SizedBox(width: 10),
          item(TransportMode.metro, Icons.directions_transit, t.checkoutMetro),
          const SizedBox(width: 10),
          item(
            TransportMode.delivery,
            Icons.delivery_dining,
            deliveryLabel,
            enabled: _deliveryAvailable,
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodTile(
      Color teal,
      double total,
      AppLocalizations t, {
        required bool isDelivery,
      }) {
    final isOnline = paymentMethod == PaymentMethod.onlinePay;
    final isWallet = paymentMethod == PaymentMethod.wallet;

    final onlineLabel =
    Platform.isIOS ? t.checkoutApplePay : t.checkoutGooglePay;

    String label;
    IconData icon;

    if (isOnline) {
      label = onlineLabel;
      icon = Platform.isIOS ? Icons.phone_iphone : Icons.payment;
    } else if (isWallet) {
      label = t.checkoutWallet;
      icon = Icons.account_balance_wallet_outlined;
    } else {
      label = t.checkoutCashOnDelivery;
      icon = Icons.payments_outlined;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final picked = await showModalBottomSheet<PaymentMethod>(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          builder: (_) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      t.checkoutChoosePaymentMethod,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading:
                      Icon(Platform.isIOS ? Icons.phone_iphone : Icons.payment),
                      title: Text(
                        Platform.isIOS ? t.checkoutApplePay : t.checkoutGooglePay,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        t.checkoutPaySar(total.toStringAsFixed(2)),
                        style: TextStyle(color: Colors.black.withOpacity(0.6)),
                      ),
                      onTap: () => Navigator.pop(context, PaymentMethod.onlinePay),
                    ),
                    ListTile(
                      enabled: _walletCanCoverCurrentTotal,
                      leading: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: _walletCanCoverCurrentTotal
                            ? null
                            : Colors.black.withOpacity(0.28),
                      ),
                      title: Text(
                        t.checkoutWallet,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _walletCanCoverCurrentTotal
                              ? Colors.black
                              : Colors.black.withOpacity(0.4),
                        ),
                      ),
                      subtitle: Text(
                        _loadingWalletBalance
                            ? t.loading
                            : _walletCanCoverCurrentTotal
                            ? t.checkoutWalletBalanceSar(
                          _walletBalanceSar.toStringAsFixed(2),
                        )
                            : t.checkoutWalletInsufficientBalance,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.6),
                        ),
                      ),
                      onTap: _walletCanCoverCurrentTotal
                          ? () => Navigator.pop(context, PaymentMethod.wallet)
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(
                        t.checkoutCashOnDelivery,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        t.checkoutPayWhenReceive,
                        style: TextStyle(color: Colors.black.withOpacity(0.6)),
                      ),
                      onTap: () =>
                          Navigator.pop(context, PaymentMethod.cashOnDelivery),
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (picked != null) setState(() => paymentMethod = picked);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, color: teal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (isWallet && !_loadingWalletBalance) ...[
                    const SizedBox(height: 4),
                    Text(
                      t.checkoutWalletBalanceSar(
                        _walletBalanceSar.toStringAsFixed(2),
                      ),
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.55),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              t.checkoutChange,
              style: TextStyle(color: teal, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _estimateRow(String left, String right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            left,
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(right, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class MetroRouteInfo {
  final String fromStation;
  final String toStation;
  final int stops;
  final String lineName;
  final Color lineColor;
  final String directionLabel;

  const MetroRouteInfo({
    required this.fromStation,
    required this.toStation,
    required this.stops,
    required this.lineName,
    required this.lineColor,
    required this.directionLabel,
  });
}

class _CartItemTile extends StatelessWidget {
  final String itemKey;
  final Future<String?> Function(String src) resolveAnyImageToUrl;

  const _CartItemTile({
    required this.itemKey,
    required this.resolveAnyImageToUrl,
  });

  Widget _placeholder() {
    return Icon(Icons.local_cafe, color: Colors.black.withOpacity(0.25));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cart = CartController.instance;
    final item = cart.items.firstWhere((e) => e.key == itemKey);

    final src = item.imageAsset.trim();

    Widget imageWidget() {
      if (src.isEmpty) return _placeholder();

      if (src.startsWith('assets/')) {
        return Image.asset(
          src,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      }

      return FutureBuilder<String?>(
        future: resolveAnyImageToUrl(src),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final url = snap.data;

          if (url == null || url.isEmpty) {
            return Image.asset(
              src,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _placeholder(),
            );
          }

          return Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _placeholder(),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          );
        },
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 68,
              height: 68,
              color: Colors.black.withOpacity(0.04),
              child: imageWidget(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                if (item.selectedOptions.isNotEmpty)
                  ...item.selectedOptions.map((o) {
                    final qtyTxt = o.qty > 1 ? " x${o.qty}" : "";
                    final priceTxt = o.priceDelta > 0
                        ? " (+${o.priceDelta.toStringAsFixed(2)})"
                        : "";
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        "• ${o.optionName}$qtyTxt$priceTxt",
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.6),
                          fontSize: 12.5,
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Text(
                  t.checkoutLineSar(item.lineTotal.toStringAsFixed(2)),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final double total;
  final int itemsCount;

  const _SummaryBox({required this.total, required this.itemsCount});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t.checkoutItemsCount(itemsCount),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            t.checkoutTotalSar(total.toStringAsFixed(2)),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ],
      ),
    );
  }
}