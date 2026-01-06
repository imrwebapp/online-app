import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'azan_foreground_service.dart';

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse resp) async {
  WidgetsFlutterBinding.ensureInitialized();
  ui.DartPluginRegistrant.ensureInitialized();
  await NotificationService._processNotificationAction(resp);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Initialize notifications
  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Karachi'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    _initialized = true;
  }

  static Future<void> _handleNotificationTap(NotificationResponse resp) async {
    await _processNotificationAction(resp);
  }

  static Future<void> _processNotificationAction(
      NotificationResponse resp) async {
    if (resp.actionId == 'STOP_AZAN') {
      debugPrint("🛑 Stop Azan pressed from notification");
      await AzanForegroundService.stopForegroundAzan();
      await _notifications.cancel(1000);
    }
  }

  static Future<void> ensureAndroidPermissions() async {
    await _ensureInitialized();
    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  }

  static Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }

  /// Play Azan immediately using native foreground service
  static Future<void> playAzanSoundNow({String prayerName = "Azan"}) async {
    try {
      await _ensureInitialized();
      
      // Start native foreground service which handles its own notification
      await AzanForegroundService.startForegroundAzan(prayerName: prayerName);
      
      debugPrint('✅ Azan playback started via native service for $prayerName');
    } catch (e, st) {
      debugPrint("❌ playAzanSoundNow error: $e\n$st");
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _ensureInitialized();
    await _notifications.cancelAll();
  }
}