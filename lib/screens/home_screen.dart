import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/azan_service.dart';
import 'audio_quran_screen.dart';
import 'tasbih_screen.dart';
import 'azkar_screen.dart';
import 'qibla_screen.dart';
import 'settings_screen.dart';
// import 'favorites_screen.dart';
import 'post_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color darkGreen = Color(0xFF0E4C3D);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🌄 Header with background
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 380,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage("assets/images/mosque_bg.jpg"),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            // 🌿 Main section
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [

                  // 🟩 Feature Grid (FULL IMAGE COVER)
                  GridView.count(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.9,
                    children: [
                      _gridItem(context, "Audio Quran", "assets/icon/quran.png", const AudioQuranScreen()),
                      _gridItem(context, "Tasbih", "assets/icon/tasbih.png", const TasbihScreen()),
                      _gridItem(context, "Azkar", "assets/icon/azkar.png", AzkarScreen()),
                      _gridItem(context, "Qibla", "assets/icon/qibla.png", const QiblaScreen()),
                      _gridItem(context, "Course", "assets/icon/favorite.png", PostScreen()),
                      _gridItem(context, "Settings", "assets/icon/settings.png", const SettingsScreen()),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // 🕌 Prayer Times Section
                  Consumer<AzanService>(
                    builder: (context, azan, _) {
                      final times = azan.todaysTimes;
                      final countdown = azan.timeUntilNextPrayer();

                      if (times.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            " Get Azan Timing by Enabeling Azan Notifications in setting then reopen the app...",
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: darkGreen,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.shade200,
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Today's Prayer Times",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 10),

                            _prayerRow("Fajr", azan.formattedTime("Fajr")),
                            _prayerRow("Dhuhr", azan.formattedTime("Dhuhr")),
                            _prayerRow("Asr", azan.formattedTime("Asr")),
                            _prayerRow("Maghrib", azan.formattedTime("Maghrib")),
                            _prayerRow("Isha", azan.formattedTime("Isha")),

                            const SizedBox(height: 10),
                            Center(
                              child: Text(
                                countdown,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 25),

                  // 🌿 Footer
                  Container(
                    height: 45,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: darkGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "Al Quran MP3 © 2026 — Presented by AB Media",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔸 Grid Item (FULL IMAGE TILE)
  Widget _gridItem(BuildContext context, String title, String image, Widget screen) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => screen),
      ),
      child: Container(
        decoration: BoxDecoration(
          // FULL TILE IMAGE
          image: DecorationImage(
            image: AssetImage(image),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  // 🔹 Single Prayer Row
  static Widget _prayerRow(String name, String time) {
    IconData getIcon() {
      switch (name) {
        case "Fajr": return Icons.wb_twilight;
        case "Dhuhr": return Icons.wb_sunny;
        case "Asr": return Icons.cloud;
        case "Maghrib": return Icons.nights_stay;
        case "Isha": return Icons.bedtime;
        default: return Icons.access_time;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(getIcon(), color: Colors.white70, size: 20),
              const SizedBox(width: 10),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          Text(
            time,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
     ),
);
}
}
