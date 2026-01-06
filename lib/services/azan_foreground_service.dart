import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Simplified wrapper that ALWAYS uses native Android service
class AzanForegroundService {
  static const MethodChannel _channel =
      MethodChannel('com.mrwebapp.al_quran_mp3/azan_service');

  /// 🕌 Start native foreground service to play Azan
  static Future<void> startForegroundAzan({String prayerName = "Azan"}) async {
    if (!Platform.isAndroid) {
      debugPrint('⚠️ Azan service only supported on Android');
      return;
    }

    try {
      await _channel.invokeMethod('startAzanService', {
        'prayerName': prayerName,
      });
      debugPrint('✅ Native Azan service started for $prayerName');
    } catch (e, st) {
      debugPrint('❌ Failed to start native Azan service: $e\n$st');
      rethrow;
    }
  }

  /// 🛑 Stop native foreground service
  static Future<void> stopForegroundAzan() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('stopAzanService');
      debugPrint('✅ Native Azan service stopped');
    } catch (e, st) {
      debugPrint('❌ Failed to stop native Azan service: $e\n$st');
    }
  }
}
