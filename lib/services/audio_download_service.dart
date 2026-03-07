import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/surah.dart';
import '../data/surah_list.dart';

class AudioDownloadService extends ChangeNotifier {
  static const String baseUrl =
      'https://github.com/aounrshah/audio-files/releases/download/v1.0';

  Map<int, double> downloadProgress = {};
  Map<int, bool> isDownloading = {};
  Set<int> downloadedSurahs = {};

  bool isBatchDownloading = false;
  double batchProgress = 0.0;
  int batchCompleted = 0;
  int batchTotal = 0;

  AudioDownloadService() {
    _loadDownloadedList();
  }

  Future<void> _loadDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList('downloaded_surahs') ?? [];
    downloadedSurahs = downloaded.map((e) => int.parse(e)).toSet();
    notifyListeners();
  }

  Future<void> _saveDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'downloaded_surahs',
      downloadedSurahs.map((e) => e.toString()).toList(),
    );
  }

  bool isDownloaded(int surahNumber) => downloadedSurahs.contains(surahNumber);

  Future<String> _getLocalPath(String audioAsset) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$audioAsset';
  }

  Future<bool> _fileExists(String path) async => File(path).exists();

  // ─────────────────────────────────────────────────────────────────────────
  // AUDIO SOURCE
  //
  // • Permanently downloaded  → AudioSource.file()   — instant, offline
  // • Not downloaded          → LockCachingAudioSource with resolved CDN URL
  //     - just_audio proxies it through localhost, so AVPlayer on iOS never
  //       sees the GitHub redirect URL
  //     - Streams and caches simultaneously — full surah plays without waiting
  //     - Cached copy is reused on next play
  // ─────────────────────────────────────────────────────────────────────────

  Future<AudioSource> getAudioSource(Surah surah) async {
    final localPath = await _getLocalPath(surah.audioAsset);

    if (await _fileExists(localPath)) {
      debugPrint('🎵 Local file: $localPath');
      return AudioSource.file(localPath);
    }

    // Resolve GitHub redirect chain so LockCachingAudioSource
    // receives the final CDN URL, not the GitHub 302 redirect URL
    final cdnUrl = await _resolveGitHubRedirects(surah.audioAsset);
    debugPrint('🌐 LockCachingAudioSource → $cdnUrl');
    return LockCachingAudioSource(Uri.parse(cdnUrl));
  }

  /// Follows GitHub Releases redirects manually using Dart's HTTP client
  /// (which handles them correctly) and returns the final CDN URL.
  Future<String> _resolveGitHubRedirects(String audioAsset) async {
    final rawUrl = '$baseUrl/$audioAsset';
    String currentUrl = rawUrl;

    try {
      final client = http.Client();

      for (int i = 0; i < 10; i++) {
        final req = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['Range'] = 'bytes=0-0'; // minimal — just need the headers

        final res = await client.send(req);
        await res.stream.drain();

        if (res.statusCode >= 300 && res.statusCode < 400) {
          final location = res.headers['location'];
          if (location == null || location.isEmpty) break;
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
          debugPrint('↪ Redirect $i → $currentUrl');
        } else {
          break; // reached final CDN URL
        }
      }

      client.close();
      debugPrint('✅ CDN URL resolved: $currentUrl');
      return currentUrl;
    } catch (e) {
      debugPrint('⚠️ Redirect resolve failed, using raw URL: $e');
      return rawUrl;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPLICIT DOWNLOAD — user taps download button
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> downloadSurah(Surah surah) async {
    try {
      debugPrint('📥 Downloading: ${surah.nameEn}');

      final localPath = await _getLocalPath(surah.audioAsset);
      if (await _fileExists(localPath)) {
        downloadedSurahs.add(surah.number);
        await _saveDownloadedList();
        notifyListeners();
        return true;
      }

      isDownloading[surah.number] = true;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();

      final request = http.Request('GET', Uri.parse('$baseUrl/${surah.audioAsset}'));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      final file = File(localPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          downloadProgress[surah.number] = received / totalBytes;
          notifyListeners();
        }
      }

      await sink.close();
      downloadedSurahs.add(surah.number);
      await _saveDownloadedList();
      isDownloading[surah.number] = false;
      downloadProgress[surah.number] = 1.0;
      notifyListeners();

      debugPrint('✅ Downloaded: ${surah.nameEn}');
      return true;
    } catch (e, st) {
      debugPrint('❌ Download failed: $e\n$st');
      isDownloading[surah.number] = false;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSurah(Surah surah) async {
    try {
      final localPath = await _getLocalPath(surah.audioAsset);
      final file = File(localPath);
      if (await file.exists()) await file.delete();
      downloadedSurahs.remove(surah.number);
      await _saveDownloadedList();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Delete failed: $e');
      return false;
    }
  }

  Future<void> downloadAll(List<Surah> surahs) async {
    isBatchDownloading = true;
    batchCompleted = 0;
    batchTotal = surahs.where((s) => !isDownloaded(s.number)).length;
    batchProgress = 0.0;
    notifyListeners();

    for (final surah in surahs) {
      if (!isDownloaded(surah.number)) {
        if (await downloadSurah(surah)) {
          batchCompleted++;
          batchProgress = batchCompleted / batchTotal;
          notifyListeners();
        }
      }
    }

    isBatchDownloading = false;
    notifyListeners();
  }

  Future<String> getTotalDownloadedSize() async {
    int totalBytes = 0;
    for (final num in downloadedSurahs) {
      final surah = surahs.firstWhere((s) => s.number == num);
      final file = File(await _getLocalPath(surah.audioAsset));
      if (await file.exists()) totalBytes += await file.length();
    }
    return '${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  Future<void> clearAllDownloads() async {
    for (final num in downloadedSurahs.toList()) {
      await deleteSurah(surahs.firstWhere((s) => s.number == num));
    }
  }
}