import 'dart:async';
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

  // ─────────────────────────────────────────────────────────────────────────
  // STREAMING / PLAYBACK PATH
  // iOS AVPlayer cannot follow GitHub Releases' multi-hop redirects at all.
  // Solution: always resolve to a local file path before handing to the player.
  //   • Already downloaded  → instant play from documents dir.
  //   • Temp cache exists   → play immediately, promote to permanent in bg.
  //   • Nothing cached      → progressive download: buffer 256 KB first,
  //                           return temp path so playback starts quickly,
  //                           finish downloading the rest in the background,
  //                           then promote to permanent storage automatically.
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a local file path that AudioPlayer can always play on iOS & Android.
  Future<String> getAudioPath(Surah surah) async {
    // 1️⃣ Fully downloaded — instant play, no network needed
    final localPath = await _getLocalPath(surah.audioAsset);
    if (await _fileExists(localPath)) {
      debugPrint('🎵 Playing local (permanent): $localPath');
      return localPath;
    }

    // 2️⃣ Temp cache from a previous stream session — play immediately
    final tempPath = await _getTempPath(surah.audioAsset);
    if (await _fileExists(tempPath)) {
      debugPrint('🎵 Playing from temp cache: $tempPath');
      // Promote to permanent in background so next time is instant
      _promoteToPermament(surah, tempPath, localPath);
      return tempPath;
    }

    // 3️⃣ Nothing cached — progressive download then play
    //    Waits only until minBufferBytes are on disk, then returns so the
    //    player can start. The rest of the file downloads in the background.
    debugPrint('⚡ Progressive download starting: ${surah.nameEn}');
    await _startProgressiveDownload(surah, tempPath, localPath);
    return tempPath;
  }

  /// Path inside the system temp/cache directory — separate from permanent downloads.
  Future<String> _getTempPath(String audioAsset) async {
    final dir = await getTemporaryDirectory();
    final safeName = audioAsset.replaceAll('/', '_');
    return '${dir.path}/stream_$safeName';
  }

  /// Starts downloading [surah] to [tempPath].
  /// Returns as soon as [minBufferBytes] are flushed to disk so the caller
  /// can hand the path to AudioPlayer without noticeable delay.
  /// The remainder of the file continues downloading in the background.
  Future<void> _startProgressiveDownload(
    Surah surah,
    String tempPath,
    String localPath, {
    int minBufferBytes = 256 * 1024, // 256 KB ≈ 5-8 seconds of Quran audio
  }) async {
    final completer = Completer<void>();
    bool bufferReached = false;

    // Fire-and-forget async closure — keeps downloading after we return
    () async {
      try {
        final url = '$baseUrl/${surah.audioAsset}';
        final request = http.Request('GET', Uri.parse(url))
          ..followRedirects = true
          ..maxRedirects = 10;

        final response = await request.send();

        if (response.statusCode != 200) {
          if (!completer.isCompleted) {
            completer.completeError(
              Exception('HTTP ${response.statusCode}'),
            );
          }
          return;
        }

        final file = File(tempPath);
        await file.parent.create(recursive: true);
        final sink = file.openWrite();
        int bytesWritten = 0;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          bytesWritten += chunk.length;

          // ✅ Enough buffered — unblock the caller so playback starts now
          if (!bufferReached && bytesWritten >= minBufferBytes) {
            bufferReached = true;
            await sink.flush(); // ensure bytes are physically on disk
            debugPrint(
              '▶️ Buffer ready (${(bytesWritten / 1024).toStringAsFixed(0)} KB)'
              ' — returning path for playback',
            );
            if (!completer.isCompleted) completer.complete();
          }
        }

        await sink.flush();
        await sink.close();
        debugPrint('✅ Background download complete: ${surah.nameEn}');

        // If the file was very small and we never hit the buffer threshold,
        // complete here so the caller is not left waiting forever.
        if (!completer.isCompleted) completer.complete();

        // Move finished temp file to permanent storage
        await _promoteToPermament(surah, tempPath, localPath);
      } catch (e) {
        debugPrint('❌ Progressive download error: $e');
        if (!completer.isCompleted) completer.completeError(e);
      }
    }();

    // Wait only until the initial buffer is ready, then return
    await completer.future;
  }

  /// Copies the completed temp file to the permanent downloads directory,
  /// then removes the temp file and marks the surah as downloaded.
  Future<void> _promoteToPermament(
    Surah surah,
    String tempPath,
    String localPath,
  ) async {
    try {
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) return;

      final destFile = File(localPath);
      await destFile.parent.create(recursive: true);
      await tempFile.copy(localPath);
      await tempFile.delete();

      downloadedSurahs.add(surah.number);
      await _saveDownloadedList();
      notifyListeners();

      debugPrint('📁 Promoted to permanent: ${surah.nameEn}');
    } catch (e) {
      debugPrint('⚠️ Promotion failed (non-critical): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

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