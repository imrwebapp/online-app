import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/surah_list.dart';
import '../models/surah.dart';
import '../services/favorite_service.dart';
import '../services/audio_service.dart';
import '../services/audio_download_service.dart';
import 'player_screen.dart';
import 'favorites_screen.dart'; // ⭐ Added import

class AudioQuranScreen extends StatefulWidget {
  const AudioQuranScreen({super.key});

  @override
  State<AudioQuranScreen> createState() => _AudioQuranScreenState();
}

class _AudioQuranScreenState extends State<AudioQuranScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final favService = Provider.of<FavoriteService>(context);
    final audioService = Provider.of<AudioService>(context);
    final downloadService = Provider.of<AudioDownloadService>(context);

    final filtered = _query.isEmpty
        ? surahs
        : surahs
            .where((s) =>
                s.nameEn.toLowerCase().contains(_query.toLowerCase()) ||
                s.nameAr.contains(_query))
            .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 🌿 Header with gradient
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color.fromARGB(255, 14, 76, 61),
                    const Color.fromARGB(255, 14, 76, 61)
                  ],
                ),
              ),
              child: Row(
                children: [
                     // 🔙 Back Arrow (ADDED)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Al Quran MP3',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${downloadService.downloadedSurahs.length} of ${surahs.length} downloaded',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                  // ⭐ Favorite button added
                  IconButton(
                    icon: const Icon(Icons.star, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FavoritesScreen(),
                        ),
                      );
                    },
                  ),

                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: () {
                      showSearch(context: context, delegate: SurahSearch());
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: () => _showDownloadManager(context),
                  ),
                ],
              ),
            ),

            // 🔍 Search Bar
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 4,
                      color: Colors.black12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration.collapsed(
                          hintText: 'Search Surah (English or Arabic)',
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _query = ''),
                        child: const Icon(Icons.clear, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ),

            // 📖 List of Surahs
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final s = filtered[i];
                  final isFav = favService.isFav(s.number);
                  final isPlaying = audioService.currentSurah?.number == s.number &&
                      audioService.isPlaying;
                  final isDownloaded = downloadService.isDownloaded(s.number);
                  final isDownloading =
                      downloadService.isDownloading[s.number] ?? false;
                  final progress =
                      downloadService.downloadProgress[s.number] ?? 0.0;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      leading: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.teal.shade700,
                            child: Text('${s.number}',
                                style: const TextStyle(color: Colors.white)),
                          ),
                          if (isDownloading)
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 3,
                                backgroundColor: Colors.grey[300],
                                color: Colors.teal,
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.nameEn,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (isDownloaded)
                            Icon(Icons.offline_pin,
                                color: Colors.green, size: 18),
                          if (!isDownloaded && !isDownloading)
                            Icon(Icons.cloud_outlined,
                                color: Colors.grey, size: 18),
                        ],
                      ),
                      subtitle: Text(
                        s.nameAr,
                        style: const TextStyle(
                            fontSize: 18, color: Colors.deepPurple),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          // Download button
                          if (!isDownloaded && !isDownloading)
                            IconButton(
                              icon: const Icon(Icons.download_outlined),
                              color: Colors.blue,
                              onPressed: () async {
                                final success =
                                    await downloadService.downloadSurah(s);
                                if (success && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            '✅ ${s.nameEn} downloaded!')),
                                  );
                                }
                              },
                            ),

                          // Delete button
                          if (isDownloaded)
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red,
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Download'),
                                    content: Text('Delete ${s.nameEn}?'),
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
                                  await downloadService.deleteSurah(s);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              '🗑️ ${s.nameEn} deleted')),
                                    );
                                  }
                                }
                              },
                            ),

                          // Play button
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.equalizer : Icons.play_arrow,
                              color: isPlaying ? Colors.teal : Colors.grey,
                            ),
                            onPressed: isDownloading
                                ? null
                                : () {
                                    audioService.setSurahAndPlay(s);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            PlayerScreen(surah: s),
                                      ),
                                    );
                                  },
                          ),

                          // Favorite button
                          IconButton(
                            icon: Icon(
                              isFav ? Icons.star : Icons.star_border,
                              color: isFav ? Colors.orange : Colors.grey,
                            ),
                            onPressed: () => favService.toggle(s.number),
                          ),
                        ],
                      ),
                      onTap: isDownloading
                          ? null
                          : () {
                              audioService.setSurahAndPlay(s, autoplay: false);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PlayerScreen(surah: s)),
                              );
                            },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloadManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => DownloadManagerSheet(),
    );
  }
}

// --------------------------------------------------------------
// Download Manager Bottom Sheet
// --------------------------------------------------------------

class DownloadManagerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AudioDownloadService>(
      builder: (context, downloadService, _) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Download Manager',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              FutureBuilder<String>(
                future: downloadService.getTotalDownloadedSize(),
                builder: (context, snapshot) {
                  return Text(
                    'Downloaded: ${downloadService.downloadedSurahs.length}/${surahs.length} Surahs\n'
                    'Total Size: ${snapshot.data ?? "Calculating..."}',
                    style: const TextStyle(fontSize: 14),
                  );
                },
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: downloadService.isBatchDownloading
                          ? null
                          : () {
                              downloadService.downloadAll(surahs);
                              Navigator.pop(context);
                            },
                      icon: const Icon(Icons.download),
                      label: const Text('Download All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear All Downloads'),
                            content: const Text(
                                'This will delete all downloaded Surahs. Continue?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, true),
                                child: const Text('Delete All'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await downloadService.clearAllDownloads();
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text('Clear All'),
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// --------------------------------------------------------------
// Search Delegate
// --------------------------------------------------------------

class SurahSearch extends SearchDelegate<Surah?> {
  @override
  List<Widget>? buildActions(BuildContext context) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) {
    final res = surahs
        .where((s) =>
            s.nameEn.toLowerCase().contains(query.toLowerCase()) ||
            s.nameAr.contains(query))
        .toList();
    return ListView.builder(
      itemCount: res.length,
      itemBuilder: (_, i) {
        final s = res[i];
        return ListTile(
          title: Text(s.nameEn),
          subtitle: Text(s.nameAr),
          onTap: () => close(context, s),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final sug = surahs
        .where((s) =>
            s.nameEn.toLowerCase().contains(query.toLowerCase()) ||
            s.nameAr.contains(query))
        .toList();
    return ListView.builder(
      itemCount: sug.length,
      itemBuilder: (_, i) {
        final s = sug[i];
        return ListTile(
          title: Text(s.nameEn),
          subtitle: Text(s.nameAr),
          onTap: () => close(context, s),
        );
      },
    );
  }
}
