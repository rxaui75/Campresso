import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeliveryController extends ChangeNotifier {
  DeliveryController._();
  static final DeliveryController instance = DeliveryController._();

  static const _kDelivery = 'delivery_available';

  // ✅ Firestore field names (unified with Checkout)
  static const String _fsAvailable = 'availableForDelivery';
  static const String _fsLastActive = 'deliveryLastActiveAt';

  bool _available = false;
  bool _loaded = false;

  bool get available => _available;
  bool get loaded => _loaded;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _heartbeatTimer;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _userRef {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Call once after login
  Future<void> start() async {
    // 1️⃣ load cached value (fast)
    final sp = await SharedPreferences.getInstance();
    _available = sp.getBool(_kDelivery) ?? false;
    _loaded = true;
    notifyListeners();

    // 2️⃣ listen to Firestore (source of truth)
    final ref = _userRef;
    if (ref == null) return;

    await _sub?.cancel();
    _sub = ref.snapshots().listen((snap) async {
      final data = snap.data() ?? {};
      final v = (data[_fsAvailable] == true);

      if (v != _available) {
        _available = v;
        notifyListeners();

        // sync to local cache
        final sp = await SharedPreferences.getInstance();
        await sp.setBool(_kDelivery, v);
      }

      // ✅ heartbeat management based on Firestore state
      if (_available) {
        _startHeartbeat();
      } else {
        _stopHeartbeat();
      }
    });
  }

  Future<void> setAvailable(bool v) async {
    _available = v;
    _loaded = true;
    notifyListeners();

    // save local
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kDelivery, v);

    final ref = _userRef;
    if (ref == null) return;

    // save Firestore (unified fields)
    await ref.set({
      _fsAvailable: v,
      _fsLastActive: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // heartbeat
    if (v) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  void _startHeartbeat() {
    // prevent duplicates
    if (_heartbeatTimer != null) return;

    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final ref = _userRef;
      if (ref == null) return;

      try {
        await ref.update({
          _fsLastActive: FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // ignore transient errors (offline/permissions)
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Optional: call on logout
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _stopHeartbeat();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopHeartbeat();
    super.dispose();
  }
}
