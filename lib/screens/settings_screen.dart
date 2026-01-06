import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/audio_download_service.dart';
import '../data/surah_list.dart';
import 'package:url_launcher/url_launcher.dart'; 
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Timer? _secondTimer;
  bool _isAboutExpanded = false;

  @override
  void initState() {
    super.initState();

    // Timer to refresh every second for live countdown
    _secondTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _secondTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsService, AudioDownloadService>(
      builder: (context, settings, downloadService, _) {
        final azanEnabled = settings.azanEnabled;
        // final fontSize = settings.fontSize;
        final azanService = settings.azanService;

        // Determine next Azan
        String? nextAzan;
        DateTime now = DateTime.now();
        DateTime? nextTime;

        azanService.todaysTimes.forEach((key, value) {
          if (value.isAfter(now) && (nextTime == null || value.isBefore(nextTime!))) {
            nextTime = value;
            nextAzan = key;
          }
        });

        if (nextAzan == null) {
          nextAzan = 'Fajr';
          nextTime = azanService.todaysTimes['Fajr']?.add(const Duration(days: 1));
        }

        Duration diff = nextTime != null ? nextTime!.difference(now) : Duration.zero;

        final countdownText =
            '${diff.inHours > 0 ? '${diff.inHours} h ' : ''}${diff.inMinutes % 60} m left for $nextAzan';

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: Padding(
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // SwitchListTile(
                  //   title: const Text('Dark Mode (UI only)'),
                  //   value: settings.darkMode,
                  //   onChanged: (v) => settings.toggleDarkMode(v),
                  // ),

                  SwitchListTile(
                    title: const Text('Enable Azan Notifications'),
                    subtitle: const Text('Receive Azan/alarm at prayer times'),
                    value: azanEnabled,
                    onChanged: (v) => settings.toggleAzan(v),
                  ),

                  const SizedBox(height: 12),

                  // Today's Azan Times
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Today\'s Azan Times',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),

                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: azanService.todaysTimes.entries.map((entry) {
                              final isNext = nextAzan == entry.key;
                              final dt = entry.value;
                              final formattedTime =
                                  '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

                              return _timeChip(entry.key, formattedTime, highlight: isNext);
                            }).toList(),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            countdownText,
                            style: const TextStyle(
                                color: Colors.teal,
                                fontWeight: FontWeight.w600,
                                fontSize: 15),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Times are local and stored locally after first sync.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Quran Downloads
                  Card(
                    color: Colors.green[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📥 Quran Downloads',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),

                          FutureBuilder<String>(
                            future: downloadService.getTotalDownloadedSize(),
                            builder: (context, snapshot) {
                              return Text(
                                'Downloaded: ${downloadService.downloadedSurahs.length}/${surahs.length} Surahs\n'
                                'Total Size: ${snapshot.data ?? "Calculating..."}',
                                style: const TextStyle(fontSize: 13),
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          if (downloadService.isBatchDownloading) ...[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Downloading: ${downloadService.batchCompleted}/${downloadService.batchTotal}',
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: downloadService.batchProgress,
                                  backgroundColor: Colors.grey[300],
                                  color: Colors.teal,
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ],

                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: downloadService.isBatchDownloading
                                      ? null
                                      : () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Download All Surahs'),
                                              content: const Text(
                                                'This will download all 114 Surahs.\n\n'
                                                'Total size: ~500-800 MB\n'
                                                'Make sure you have enough storage and stable internet.\n\n'
                                                'Continue?'
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text('Download'),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirm == true) {
                                            downloadService.downloadAll(surahs);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    '📥 Downloading all Surahs in background...'),
                                                duration: Duration(seconds: 3),
                                              ),
                                            );
                                          }
                                        },
                                  icon: downloadService.isBatchDownloading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.download),
                                  label: Text(downloadService.isBatchDownloading
                                      ? 'Downloading...'
                                      : 'Download All'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 8),

                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Clear All Downloads'),
                                        content: const Text(
                                            'Delete all downloaded Surahs?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true) {
                                      await downloadService.clearAllDownloads();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('🗑️ All downloads cleared')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.delete_sweep),
                                  label: const Text('Clear All'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // // Font size slider
                  // Row(
                  //   children: [
                  //     const Text('Arabic Font Size:'),
                  //     Expanded(
                  //       child: Slider(
                  //         min: 14,
                  //         max: 36,
                  //         value: fontSize,
                  //         onChanged: (v) => settings.updateFontSize(v),
                  //       ),
                  //     ),
                  //     Text(fontSize.toInt().toString()),
                  //   ],
                  // ),

                  // const SizedBox(height: 20),

                  // About Section with Expandable Text
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.info, color: Colors.teal),
                              SizedBox(width: 8),
                              Text(
                                'About',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isAboutExpanded
                                ? 'Qari Abdul Mateen Shaheen is a distinguished Qur\'an reciter and a graduate of Qira\'at Sab\'ah \'Asharah (Seventeen Qira\'ats). He is the founder and principal of Markaz Al-Aqsa Al-Islami, Faisalabad, dedicated to the teaching of the Holy Qur\'an, Tajweed, and Qira\'at.\n\nHe has represented Pakistan at national and international levels in the field of Qur\'anic recitation and has earned multiple Qur\'anic awards. For the benefit of the general public, he also introduced the initiative "Sahih Qur\'an, Aasan Tajweed" to promote correct and easy Qur\'an recitation.\n\nHe is the founder and owner of the "Al-Qur\'an MP3 Abdul Mateen Shaheen" app, through which beautiful and rule-based recitation of the Holy Qur\'an is being shared worldwide.'
                                : 'Qari Abdul Mateen Shaheen is a distinguished Qur\'an reciter and a graduate of Qira\'at Sab\'ah \'Asharah (Seventeen Qira\'ats). He is the founder and principal of Markaz Al-Aqsa Al-Islami...',
                            style: const TextStyle(fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _isAboutExpanded = !_isAboutExpanded;
                                });
                              },
                              child: Text(
                                _isAboutExpanded ? 'Read Less' : 'Read More',
                                style: const TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                        
                      ),
                    ),
                  ),
                       const SizedBox(height: 10),
                  const Divider(),

                  // ✅ PRIVACY POLICY (END – GOOGLE PLAY COMPLIANT)
                  ListTile(
                    leading: const Icon(Icons.privacy_tip),
                    title: const Text('Privacy Policy'),
                    subtitle: const Text('Read our privacy policy'),
                    onTap: () async {
                      final uri = Uri.parse(
                        'https://aounraza.mrwebapp.com/privacy-policy-al-quran-mp3/',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

              
    

  Widget _timeChip(String label, String time, {bool highlight = false}) {
    final displayTime = (time.isEmpty || time == 'null') ? '--:--' : time;

    return Chip(
      backgroundColor: highlight ? Colors.teal[200] : null,
      label: Text(
        '$label\n$displayTime',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}