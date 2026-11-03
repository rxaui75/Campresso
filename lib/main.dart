import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'splash_page.dart';
import 'features/user/delivery/delivery_controller.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'features/admin/push_notifications.dart';

import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  PushNotifications.registerBackgroundHandler();

  await DeliveryController.instance.start();

  await PushNotifications.init();

  final platform = ImagePickerPlatform.instance;
  if (platform is ImagePickerAndroid) {
    platform.useAndroidPhotoPicker = false;
  }

  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seenOnboarding') ?? false;

  runApp(MyApp(seenOnboarding: seenOnboarding));
}

class MyApp extends StatefulWidget {
  final bool seenOnboarding;

  const MyApp({
    super.key,
    required this.seenOnboarding,
  });

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale _locale = const Locale('en');

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('app_lang') ?? 'en';
    setState(() => _locale = Locale(lang));
  }

  Future<void> setLocale(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang', lang);
    setState(() => _locale = Locale(lang));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      locale: _locale,
      home: SplashPage(seenOnboarding: widget.seenOnboarding),
    );
  }
}