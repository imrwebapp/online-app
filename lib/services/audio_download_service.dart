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
  // • Already downloaded → AudioSource.file()  (instant, offline)
  // • Not downloaded     → LockCachingAudioSource with resolved CDN URL
  //   - Streams the full file while playing (true streaming via local proxy)
  //   - Caches automatically; next play is instant
  //   - Bypasses iOS AVPlayer redirect issue completely
  // ─────────────────────────────────────────────────────────────────────────

  Future<AudioSource> getAudioSource(Surah surah) async {
    final localPath = await _getLocalPath(surah.audioAsset);

    // 1️⃣ Permanently downloaded — play from disk instantly
    if (await _fileExists(localPath)) {
      debugPrint('🎵 Playing local (permanent): $localPath');
      return AudioSource.file(localPath);
    }

    // 2️⃣ Not downloaded — resolve GitHub redirects in Dart, then stream+cache
    //    LockCachingAudioSource proxies the request locally so AVPlayer on
    //    iOS never sees the GitHub redirect URL — it only sees localhost.
    final resolvedUrl = await _resolveGitHubRedirects(surah.audioAsset);
    debugPrint('🌐 Streaming + caching via LockCachingAudioSource: $resolvedUrl');

    return LockCachingAudioSource(Uri.parse(resolvedUrl));
  }

  /// Manually follows GitHub Releases' redirect chain and returns the
  /// final CDN URL. This is needed because LockCachingAudioSource uses
  /// the URL we provide as the origin for its local proxy — if we give
  /// it the GitHub redirect URL the proxy will get stuck on the 302.
  Future<String> _resolveGitHubRedirects(String audioAsset) async {
    final rawUrl = '$baseUrl/$audioAsset';
    String currentUrl = rawUrl;

    try {
      final client = http.Client();
      const maxRedirects = 10;

      for (int i = 0; i < maxRedirects; i++) {
        final request = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['Range'] = 'bytes=0-0'; // fetch only 1 byte — headers only

        final response = await client.send(request);
        await response.stream.drain();

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location == null || location.isEmpty) break;
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
          debugPrint('↪ Redirect $i → $currentUrl');
        } else {
          break;
        }
      }

      client.close();
      debugPrint('✅ Resolved CDN URL: $currentUrl');
      return currentUrl;
    } catch (e) {
      debugPrint('⚠️ Redirect resolve failed, using raw URL: $e');
      return rawUrl;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPLICIT DOWNLOAD (user taps download button — saves to permanent storage)
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> downloadSurah(Surah surah) async {
    try {
      debugPrint('📥 Starting download: ${surah.nameEn}');

      final localPath = await _getLocalPath(surah.audioAsset);
      if (await _fileExists(localPath)) {
        debugPrint('✅ Already exists: ${surah.audioAsset}');
        downloadedSurahs.add(surah.number);
        await _saveDownloadedList();
        notifyListeners();
        return true;
      }

      isDownloading[surah.number] = true;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();

      final url = '$baseUrl/${surah.audioAsset}';
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('Failed to download: ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      debugPrint('📦 Total size: ${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB');

      final file = File(localPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      int downloadedBytes = 0;

      await for (var chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          downloadProgress[surah.number] = downloadedBytes / totalBytes;
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
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ Deleted: ${surah.audioAsset}');
      }
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

    for (var surah in surahs) {
      if (!isDownloaded(surah.number)) {
        final success = await downloadSurah(surah);
        if (success) {
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
    for (var surahNum in downloadedSurahs) {
      final surah = surahs.firstWhere((s) => s.number == surahNum);
      final localPath = await _getLocalPath(surah.audioAsset);
      final file = File(localPath);
      if (await file.exists()) totalBytes += await file.length();
    }
    final mb = totalBytes / 1024 / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Future<void> clearAllDownloads() async {
    for (var surahNum in downloadedSurahs.toList()) {
      final surah = surahs.firstWhere((s) => s.number == surahNum);
      await deleteSurah(surah);
    }
  }
}