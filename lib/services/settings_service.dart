import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'azan_service.dart';
import 'notification_service.dart';

class SettingsService extends ChangeNotifier {
  bool _darkMode = false;
  bool _azanEnabled = false;
  double _fontSize = 20;
  final AzanService _azanService = AzanService();

  bool get darkMode => _darkMode;
  bool get azanEnabled => _azanEnabled;
  double get fontSize => _fontSize;
  AzanService get azanService => _azanService;

  SettingsService() {
    _loadSettings();
  }

  Future<void> initAzanService() async {
    if (_azanEnabled) {
      try {
        await _azanService.start();
      } catch (e) {
        debugPrint('AzanService init error: $e');
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _darkMode = prefs.getBool('darkMode') ?? false;
    _azanEnabled = prefs.getBool('azanEnabled') ?? false;
    _fontSize = prefs.getDouble('fontSize') ?? 20;
    notifyListeners();
  }

  void toggleDarkMode(bool value) async {
    _darkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', value);
    notifyListeners();
  }

  void toggleAzan(bool value) async {
    _azanEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('azanEnabled', value);

    if (value) {
      await NotificationService.ensureAndroidPermissions();
      await _azanService.start();
    } else {
      await _azanService.stop();
    }
    notifyListeners();
  }

  void updateFontSize(double value) async {
    _fontSize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', value);
    notifyListeners();
  }

  String azanTime(String name) => _azanService.formattedTime(name);
  String nextAzanCountdown() => _azanService.timeUntilNextPrayer();
}
