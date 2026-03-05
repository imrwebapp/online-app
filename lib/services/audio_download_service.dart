import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/surah.dart';
import '../data/surah_list.dart';

class AudioDownloadService extends ChangeNotifier {
  // GitHub release URL
  static const String baseUrl =
      'https://github.com/aounrshah/audio-files/releases/download/v1.0';

  // Track download progress for each Surah
  Map<int, double> downloadProgress = {};
  Map<int, bool> isDownloading = {};
  Set<int> downloadedSurahs = {};

  // Batch download tracking
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

  bool isDownloaded(int surahNumber) {
    return downloadedSurahs.contains(surahNumber);
  }

  Future<String> _getLocalPath(String audioAsset) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$audioAsset';
  }

  Future<bool> _fileExists(String path) async {
    return File(path).exists();
  }

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
      debugPrint('🌐 Downloading from: $url');

      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('Failed to download: ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      debugPrint(
          '📦 Total size: ${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB');

      final file = File(localPath);
      // Ensure parent directory exists
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

      debugPrint('✅ Downloaded successfully: ${surah.nameEn}');
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

  /// Returns a playable path for [surah].
  ///
  /// Priority:
  ///   1. Local downloaded file → play from disk (always works on iOS).
  ///   2. No local file → resolve ALL GitHub redirect hops manually so that
  ///      AVPlayer on iOS receives the final CDN URL, not a redirect URL.
  ///
  /// The old HEAD-request trick does NOT work reliably on iOS because
  /// `response.request?.url` reflects the Dart HTTP client's last request,
  /// not what AVPlayer would end up following.  GitHub releases go through
  /// at least two redirects (302 → 302 → 200) and AVPlayer bails on the
  /// first one it cannot handle.
  Future<String> getAudioPath(Surah surah) async {
    final localPath = await _getLocalPath(surah.audioAsset);

    // 1️⃣ Already downloaded — play from disk, no network needed.
    if (await _fileExists(localPath)) {
      debugPrint('🎵 Playing local: $localPath');
      return localPath;
    }

    // 2️⃣ Not downloaded — resolve the full redirect chain manually.
    //    We keep following Location headers until we get a non-redirect
    //    response (or hit the safety limit). The final URL is a direct
    //    CDN link that AVPlayer can open without any further redirects.
    final rawUrl = '$baseUrl/${surah.audioAsset}';
    String currentUrl = rawUrl;

    try {
      const maxRedirects = 10;
      final client = http.Client();

      for (int i = 0; i < maxRedirects; i++) {
        final request = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false // ← we handle redirects ourselves
          ..headers['Range'] = 'bytes=0-0'; // tiny request, just for headers

        final response = await client.send(request);
        await response.stream.drain(); // discard body bytes

        debugPrint(
            '↪ Redirect step $i: ${response.statusCode} → $currentUrl');

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location == null || location.isEmpty) break;

          // Location can be relative or absolute
          currentUrl =
              Uri.parse(currentUrl).resolve(location).toString();
        } else {
          // Non-redirect response means we have the real URL
          break;
        }
      }

      client.close();
      debugPrint('🌐 Resolved stream URL: $currentUrl');
      return currentUrl;
    } catch (e) {
      debugPrint('⚠️ Redirect resolve failed, falling back to raw URL: $e');
      return rawUrl;
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

      if (await file.exists()) {
        totalBytes += await file.length();
      }
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