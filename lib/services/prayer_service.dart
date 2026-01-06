// import 'dart:async';
// import 'package:adhan/adhan.dart';
// import 'notification_service.dart';

// class PrayerService {
//   Timer? _timer;

//   void startPrayerNotifications() {
//     final coordinates = Coordinates(24.8607, 67.0011); // Karachi (change to your city)
//     final params = CalculationMethod.karachi.getParameters();
//     final prayerTimes = PrayerTimes.today(coordinates, params);

//     _schedulePrayerNotification('Fajr', prayerTimes.fajr);
//     _schedulePrayerNotification('Dhuhr', prayerTimes.dhuhr);
//     _schedulePrayerNotification('Asr', prayerTimes.asr);
//     _schedulePrayerNotification('Maghrib', prayerTimes.maghrib);
//     _schedulePrayerNotification('Isha', prayerTimes.isha);
//   }

//   void _schedulePrayerNotification(String name, DateTime time) {
//     final now = DateTime.now();
//     final diff = time.difference(now);

//     if (diff.inSeconds > 0) {
//       Timer(diff, () {
//         NotificationService.showNotification(
//           'Prayer Time',
//           'It s time for $name prayer (Azan)',
//         );
//       });
//     }
//   }

//   void stopPrayerNotifications() {
//     _timer?.cancel();
// }
// }
