import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';

class PushNotifications {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
  FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'campresso_high_importance',
    'Campresso Notifications',
    description: 'Order updates and ads notifications',
    importance: Importance.high,
  );

  /// ✅ تمنع تكرار init والـ listeners
  static bool _initialized = false;

  /// ✅ تمنع معالجة نفس الرسالة أكثر من مرة داخل نفس تشغيل التطبيق
  static final Set<String> _handledMessageIds = <String>{};

  /// ✅ نستخدمها في main قبل runApp
  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  /// ✅ Background handler must be top-level / entry-point
  @pragma('vm:entry-point')
  static Future<void> _firebaseMessagingBackgroundHandler(
      RemoteMessage message,
      ) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      // already initialized
    }

    if (kDebugMode) {
      print("🔔 BG message: ${message.messageId} data=${message.data}");
    }
  }

  static Future<void> init() async {
    /// ✅ مهم جدًا: لا تعملي init أكثر من مرة
    if (_initialized) {
      if (kDebugMode) {
        print('🔁 PushNotifications.init skipped: already initialized');
      }
      return;
    }
    _initialized = true;

    await _initLocalNotifications();
    await _requestPermission();

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _saveTokenIfLoggedIn();
    _fcm.onTokenRefresh.listen((token) async {
      await _saveTokenIfLoggedIn(tokenOverride: token);
    });

    /// ✅ Foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (!_markMessageHandled(message, source: 'onMessage')) return;

      // ✅ خلي إشعار التلفون يظهر أثناء فتح التطبيق
      await _showLocalFromMessage(message);

      // ✅ لكن لا تحفظي order notifications مرة ثانية في Firestore
      await _saveNotificationToFirestoreIfLoggedIn(message);
    });

    /// ✅ App opened from background by tapping notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      if (!_markMessageHandled(message, source: 'onMessageOpenedApp')) return;

      await _saveNotificationToFirestoreIfLoggedIn(message);
    });

    /// ✅ App opened from terminated state
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      if (_markMessageHandled(initial, source: 'getInitialMessage')) {
        await _saveNotificationToFirestoreIfLoggedIn(initial);
      }
    }

    if (kDebugMode) {
      print('✅ PushNotifications initialized once');
    }
  }

  static bool _markMessageHandled(RemoteMessage message, {required String source}) {
    final rawId = message.messageId?.trim();
    final fallbackId = _buildFallbackMessageId(message);
    final id = (rawId != null && rawId.isNotEmpty) ? rawId : fallbackId;

    if (_handledMessageIds.contains(id)) {
      if (kDebugMode) {
        print('⛔ Duplicate message ignored from $source -> $id');
      }
      return false;
    }

    _handledMessageIds.add(id);

    if (kDebugMode) {
      print('✅ Message handled from $source -> $id');
    }
    return true;
  }

  static String _buildFallbackMessageId(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString();
    final title =
        message.notification?.title ?? (message.data['title']?.toString() ?? '');
    final body =
        message.notification?.body ?? (message.data['body']?.toString() ?? '');
    final sentTime = message.sentTime?.millisecondsSinceEpoch.toString() ?? '';
    return '${type}_${title}_${body}_$sentTime';
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(initSettings);

    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
    }
  }

  static Future<void> _requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (kDebugMode) {
      print("🔐 Notification permission: ${settings.authorizationStatus}");
    }
  }

  static Future<void> _saveTokenIfLoggedIn({String? tokenOverride}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = tokenOverride ?? await _fcm.getToken();
    if (token == null || token.isEmpty) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

    await ref.set({
      'fcmToken': token,
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));

    if (kDebugMode) {
      print("✅ Saved FCM token for ${user.uid}: $token");
    }
  }

  static Future<void> _saveNotificationToFirestoreIfLoggedIn(
      RemoteMessage message,
      ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final dataType = (message.data['type'] ?? '').toString().toLowerCase().trim();

    String type;
    if (dataType == 'ad' || dataType == 'order' || dataType == 'delivery_request') {
      type = dataType;
    } else {
      type = 'order';
    }

// ✅ إشعارات الطلبات والإعلانات العادية already تنكتب من dashboard / backend
// لكن delivery_request نريد حفظها هنا أيضًا
    if (type == 'order' || type == 'ad') return;

    final title =
        message.notification?.title ?? (message.data['title']?.toString() ?? '');
    final body =
        message.notification?.body ?? (message.data['body']?.toString() ?? '');

    if (title.trim().isEmpty && body.trim().isEmpty) return;

    // ✅ NEW: stable ad identity
    final adId = (message.data['adId'] ?? '').toString().trim();
    final cafeId = (message.data['cafeId'] ?? '').toString().trim();

    final rawId = message.messageId?.trim();
    final fallbackId = _buildFallbackMessageId(message);

    // ✅ For ads, keep one stable doc per ad instead of one doc per FCM message
    final docId = (type == 'ad' && adId.isNotEmpty)
        ? 'ad_$adId'
        : ((rawId != null && rawId.isNotEmpty) ? rawId : fallbackId);

    final notifRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc(docId);

    await notifRef.set({
      'type': type,
      'title': title,
      'body': body,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'data': message.data,
      'messageId': docId,

      // ✅ NEW: store ad linkage explicitly so NotificationsPage can validate visibility/deletion
      if (type == 'ad' && adId.isNotEmpty) 'adId': adId,
      if (type == 'ad' && cafeId.isNotEmpty) 'cafeId': cafeId,
    }, SetOptions(merge: true));
  }

  static Future<void> _showLocalFromMessage(RemoteMessage message) async {
    final title = message.notification?.title ??
        (message.data['title']?.toString() ?? 'Campresso');
    final body =
        message.notification?.body ?? (message.data['body']?.toString() ?? '');

    if (body.trim().isEmpty && title.trim().isEmpty) return;

    const androidDetails = AndroidNotificationDetails(
      'campresso_high_importance',
      'Campresso Notifications',
      channelDescription: 'Order updates and ads notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    /// ✅ نفس الرسالة = نفس notification id تقريبًا
    final rawId = message.messageId?.trim();
    final fallbackId = _buildFallbackMessageId(message);
    final stableIdSource =
    (rawId != null && rawId.isNotEmpty) ? rawId : fallbackId;
    final id = stableIdSource.hashCode & 0x7fffffff;

    await _local.show(id, title, body, details);
  }
}