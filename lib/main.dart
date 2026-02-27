import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'dart:io';
import 'dart:async';
import 'dart:developer';

import 'services/favorite_service.dart';
import 'services/audio_service.dart';
import 'services/settings_service.dart';
import 'services/azan_service.dart';
import 'services/notification_service.dart';
import 'services/audio_download_service.dart';
import 'screens/splash_screen.dart';

// ===================================================
// 🔔 Global Notification Instance
// ===================================================
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ===================================================
// 🏁 MAIN ENTRY POINT (SAFE VERSION)
// ===================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    log("FLUTTER ERROR: ${details.exception}");
    log(details.stack.toString());
  };

  runZonedGuarded(() async {
    tz.initializeTimeZones();

    if (Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
    }

    await _initNotificationsWithoutPermission();

    if (Platform.isIOS) {
      final iosImpl = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();

      await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final favService = FavoriteService();
    await favService.loadFavorites();

    final settingsService = SettingsService();

    final downloadService = AudioDownloadService();
    final audioService = AudioService(downloadService: downloadService);

    // ✅ RUN UI FIRST
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: favService),
          ChangeNotifierProvider.value(value: downloadService),
          ChangeNotifierProvider.value(value: audioService),
          ChangeNotifierProvider.value(value: settingsService),
          ChangeNotifierProvider(create: (_) => AzanService()),
        ],
        child: const MyApp(),
      ),
    );

    // ✅ Initialize Azan AFTER UI loads (safe)
    Future.microtask(() async {
      try {
        await settingsService.initAzanService();
      } catch (e, s) {
        log("AZAN INIT ERROR: $e");
        log(s.toString());
      }
    });

    // Android permission post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await NotificationService.ensureAndroidPermissions();
      } catch (e) {
        log("ANDROID PERMISSION ERROR: $e");
      }
    });

  }, (error, stack) {
    log("ZONED ERROR: $error");
    log(stack.toString());

    // 🔴 Show error on screen instead of white screen
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.red,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                error.toString(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  });
}

// ===================================================
// 🔧 Initialize Notifications
// ===================================================
Future<void> _initNotificationsWithoutPermission() async {
  const androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const initSettings =
      InitializationSettings(android: androidInit);

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  await NotificationService.init();
}

// ===================================================
// 🎨 APP WIDGET
// ===================================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Al Quran MP3',

          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.teal,
            fontFamily: 'NotoSans',
            appBarTheme: const AppBarTheme(
              backgroundColor: Color.fromARGB(255, 14, 76, 61),
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.teal,
            fontFamily: 'NotoSans',
            appBarTheme: const AppBarTheme(
              backgroundColor: Color.fromARGB(255, 14, 76, 61),
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          themeMode:
              settings.darkMode ? ThemeMode.dark : ThemeMode.light,

          home: const SplashScreen(),
        );
      },
    );
  }
}