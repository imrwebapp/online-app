import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:adhan/adhan.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

class AzanService extends ChangeNotifier {
  bool enabled = false;
  Map<String, DateTime> todaysTimes = {};
  Timer? _midnightTimer;
  Timer? _countdownTimer;
  String calculationMethod = 'karachi'; // Default method

  AzanService() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool('azanEnabled') ?? false;
    calculationMethod = prefs.getString('calculationMethod') ?? 'karachi';

    final keys = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final map = <String, DateTime>{};
    for (final k in keys) {
      final s = prefs.getString('azan_$k');
      if (s != null) {
        try {
          map[k] = DateTime.parse(s).toLocal();
        } catch (_) {}
      }
    }

    if (map.isNotEmpty) {
      todaysTimes = map;
      notifyListeners();
    }

    if (enabled) await start();
  }

  /// Get calculation parameters based on selected method
  CalculationParameters _getCalculationParameters() {
    switch (calculationMethod) {
      case 'muslim_world_league':
        return CalculationMethod.muslim_world_league.getParameters();
      case 'egyptian':
        return CalculationMethod.egyptian.getParameters();
      case 'karachi':
        return CalculationMethod.karachi.getParameters();
      case 'umm_al_qura':
        return CalculationMethod.umm_al_qura.getParameters();
      case 'dubai':
        return CalculationMethod.dubai.getParameters();
      case 'qatar':
        return CalculationMethod.qatar.getParameters();
      case 'kuwait':
        return CalculationMethod.kuwait.getParameters();
      case 'moonsighting_committee':
        return CalculationMethod.moon_sighting_committee.getParameters();
      case 'singapore':
        return CalculationMethod.singapore.getParameters();
      case 'north_america':
        return CalculationMethod.north_america.getParameters();
      case 'tehran':
        return CalculationMethod.tehran.getParameters();
      case 'turkey':
        return CalculationMethod.turkey.getParameters();
      default:
        return CalculationMethod.karachi.getParameters();
    }
  }

  /// Set calculation method and refresh prayer times
  Future<void> setCalculationMethod(String method) async {
    calculationMethod = method;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calculationMethod', method);
    
    if (enabled) {
      await start(); // Recalculate with new method
    } else {
      notifyListeners();
    }
  }

  /// Get list of available calculation methods
  static List<Map<String, String>> getAvailableMethods() {
    return [
      {'value': 'karachi', 'label': 'University of Islamic Sciences, Karachi'},
      {'value': 'muslim_world_league', 'label': 'Muslim World League'},
      {'value': 'egyptian', 'label': 'Egyptian General Authority of Survey'},
      {'value': 'umm_al_qura', 'label': 'Umm al-Qura University, Makkah'},
      {'value': 'dubai', 'label': 'Dubai'},
      {'value': 'qatar', 'label': 'Qatar'},
      {'value': 'kuwait', 'label': 'Kuwait'},
      {'value': 'moonsighting_committee', 'label': 'Moonsighting Committee'},
      {'value': 'singapore', 'label': 'Singapore'},
      {'value': 'north_america', 'label': 'Islamic Society of North America'},
      {'value': 'tehran', 'label': 'Institute of Geophysics, Tehran'},
      {'value': 'turkey', 'label': 'Turkey'},
    ];
  }

  Future<void> start() async {
    try {
      // Request exact alarm permission first (Android 12+)
      await _requestExactAlarmPermission();

      final pos = await _determinePosition();
      final coords = Coordinates(pos.latitude, pos.longitude);
      final params = _getCalculationParameters();
      final date = DateComponents.from(DateTime.now());
      final prayerTimes = PrayerTimes(coords, date, params);

      todaysTimes = {
        'Fajr': prayerTimes.fajr.toLocal(),
        'Dhuhr': prayerTimes.dhuhr.toLocal(),
        'Asr': prayerTimes.asr.toLocal(),
        'Maghrib': prayerTimes.maghrib.toLocal(),
        'Isha': prayerTimes.isha.toLocal(),
      };

      await _saveTimesToStorage();

      // Cancel all previous alarms
      await _cancelAllAlarms();

      // Schedule new alarms
      await _scheduleAllAzans(todaysTimes);

      _scheduleMidnightRefresh();
      _startCountdownTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ AzanService start error: $e');
    }
  }

  Future<void> stop() async {
    await _cancelAllAlarms();
    _midnightTimer?.cancel();
    _countdownTimer?.cancel();
    notifyListeners();
  }

  String formattedTime(String name) {
    final dt = todaysTimes[name];
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String timeUntilNextPrayer() {
    if (todaysTimes.isEmpty) return 'No data';
    final now = DateTime.now();
    DateTime? next;
    String? nextName;

    for (final entry in todaysTimes.entries) {
      if (entry.value.isAfter(now)) {
        next = entry.value;
        nextName = entry.key;
        break;
      }
    }

    if (next == null) {
      next = todaysTimes['Fajr']!.add(const Duration(days: 1));
      nextName = 'Fajr';
    }

    final diff = next.difference(now);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return '${h > 0 ? '$h h ' : ''}$m m left for $nextName';
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw ('Location services disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw ('Location permissions denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw ('Location permissions permanently denied');
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    );
  }

  Future<void> _saveTimesToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in todaysTimes.entries) {
      await prefs.setString('azan_${entry.key}', entry.value.toUtc().toIso8601String());
    }
  }

  /// Request exact alarm permission for Android 12+
  Future<void> _requestExactAlarmPermission() async {
    final status = await Permission.scheduleExactAlarm.status;
    if (!status.isGranted) {
      final result = await Permission.scheduleExactAlarm.request();
      if (!result.isGranted) {
        debugPrint('⚠️ Exact alarm permission denied');
      }
    }
  }

  /// Schedule alarms using NATIVE Android AlarmManager
  Future<void> _scheduleAllAzans(Map<String, DateTime> times) async {
    int id = 100; // Starting alarm ID
    final now = DateTime.now();

    const platform = MethodChannel('com.mrwebapp.al_quran_mp3/azan_service');

    for (final entry in times.entries) {
      var scheduled = entry.value;
      
      // If time has passed today, schedule for tomorrow
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      try {
        final timeMillis = scheduled.millisecondsSinceEpoch;
        
        // Use native alarm scheduling
        await platform.invokeMethod('scheduleAzanAlarm', {
          'prayerName': entry.key,
          'timeMillis': timeMillis,
          'alarmId': id,
        });

        debugPrint('✅ Native alarm scheduled for ${entry.key} at $scheduled (ID: $id)');
      } catch (e) {
        debugPrint('❌ Error scheduling native alarm for ${entry.key}: $e');
      }

      id++;
    }
  }

  /// Cancel all scheduled alarms
  Future<void> _cancelAllAlarms() async {
    debugPrint('🗑️ Cancelling all Azan alarms (IDs 100-104)');
    
    const platform = MethodChannel('com.mrwebapp.al_quran_mp3/azan_service');
    
    for (int i = 100; i <= 104; i++) {
      try {
        await platform.invokeMethod('cancelAzanAlarm', {'alarmId': i});
        debugPrint('✅ Cancelled alarm ID: $i');
      } catch (e) {
        debugPrint('⚠️ Error cancelling alarm $i: $e');
      }
    }
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 0, 5);
    final diff = tomorrow.difference(now);

    _midnightTimer = Timer(diff, () async {
      if (enabled) await start();
    });
    
    debugPrint('⏰ Midnight refresh scheduled for $tomorrow');
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners());
    notifyListeners();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}