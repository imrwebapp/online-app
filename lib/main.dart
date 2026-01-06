import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

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
// 🏁 MAIN ENTRY POINT
// ===================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone & alarm manager
  tz.initializeTimeZones();
  await AndroidAlarmManager.initialize();

  // Initialize notifications
  await _initNotificationsWithoutPermission();

  // Initialize your services
  final favService = FavoriteService();
  await favService.loadFavorites();

  final settingsService = SettingsService();
  await settingsService.initAzanService();

  // Initialize download service
  final downloadService = AudioDownloadService();

  // Initialize audio service with download service
  final audioService = AudioService(downloadService: downloadService);

  // Run App
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<FavoriteService>.value(value: favService),
        ChangeNotifierProvider<AudioDownloadService>.value(value: downloadService),
        ChangeNotifierProvider<AudioService>.value(value: audioService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<AzanService>(create: (_) => AzanService()),
      ],
      child: MyApp(favService: favService),
    ),
  );

  // Ask for permissions post-frame
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await NotificationService.ensureAndroidPermissions();
  });
}

// ===================================================
// 🔧 Initialize Notifications (without permission request)
// ===================================================
Future<void> _initNotificationsWithoutPermission() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);
  await NotificationService.init();
}

// ===================================================
// 🎨 APP WIDGET
// ===================================================
class MyApp extends StatelessWidget {
  final FavoriteService favService;
  const MyApp({required this.favService, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
      return MaterialApp(
  debugShowCheckedModeBanner: false,
  title: 'Al Quran MP3',

  // 🌞 LIGHT THEME
  theme: ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.teal,
    fontFamily: 'NotoSans',

    // ✅ ADD THIS BLOCK
    appBarTheme: const AppBarTheme(
      backgroundColor: Color.fromARGB(255, 14, 76, 61),
      iconTheme: IconThemeData(
        color: Colors.white, // 🔙 back arrow
      ),
      titleTextStyle: TextStyle(
        color: Colors.white, // 📝 title
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),

  // 🌙 DARK THEME
  darkTheme: ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.teal,
    fontFamily: 'NotoSans',

    // ✅ ADD THIS BLOCK
    appBarTheme: const AppBarTheme(
      backgroundColor: Color.fromARGB(255, 14, 76, 61),
      iconTheme: IconThemeData(
        color: Colors.white,
      ),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),

  themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
  home: SplashScreen(),
);
      }
    );
  }
}