import 'dart:io';
import 'dart:developer' as dev;
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
    _log('🔧 AudioDownloadService created');
    _loadDownloadedList();
  }

  void _log(String msg) {
    dev.log(msg, name: 'AudioDownloadService');
    debugPrint('[AudioDownloadService] $msg');
  }

  Future<void> _loadDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList('downloaded_surahs') ?? [];
    downloadedSurahs = downloaded.map((e) => int.parse(e)).toSet();
    _log('📋 Loaded ${downloadedSurahs.length} downloaded surahs from prefs');
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

  // ── Audio Source ──────────────────────────────────────────────────────────

  Future<AudioSource> getAudioSource(Surah surah) async {
    _log('🎵 getAudioSource: ${surah.nameEn} (#${surah.number})');

    final localPath = await _getLocalPath(surah.audioAsset);
    _log('   localPath = $localPath');

    final exists = await _fileExists(localPath);
    _log('   localFile exists = $exists');

    // 1️⃣ Permanently downloaded — instant local playback
    if (exists) {
      _log('✅ Using permanent local file');
      return AudioSource.file(localPath);
    }

    // 2️⃣ Stream via LockCachingAudioSource
    _log('🌐 File not local — resolving GitHub redirects...');
    final cdnUrl = await _resolveGitHubRedirects(surah.audioAsset);

    // cacheFile MUST have a .mp3 extension on iOS.
    // GitHub CDN URLs have no file extension — without an explicit cacheFile,
    // LockCachingAudioSource creates a cache file with no extension, and
    // AVFoundation on iOS cannot determine the codec → silent failure / stuck loading.
    final cacheFile = await _getCacheFile(surah.audioAsset);
    _log('💾 cacheFile = ${cacheFile.path}');
    _log('🔗 cdnUrl = $cdnUrl');

    final cacheExists = await cacheFile.exists();
    if (cacheExists) {
      final size = await cacheFile.length();
      _log('ℹ️ Existing cache file found: ${(size / 1024).toStringAsFixed(0)} KB');
    }

    _log('🚀 Returning LockCachingAudioSource');
    return LockCachingAudioSource(
      Uri.parse(cdnUrl),
      cacheFile: cacheFile,
    );
  }

  /// Returns a temp File with a guaranteed .mp3 extension for iOS codec detection.
  Future<File> _getCacheFile(String audioAsset) async {
    final dir = await getTemporaryDirectory();
    final baseName = audioAsset
        .replaceAll('/', '_')
        .replaceAll(RegExp(r'\.[^.]+$'), '');
    final path = '${dir.path}/${baseName}.mp3';
    _log('📁 getCacheFile → $path');
    return File(path);
  }

  /// Follows GitHub Releases redirect chain manually and returns the final CDN URL.
  /// LockCachingAudioSource's internal proxy cannot follow redirects itself —
  /// it needs the final direct URL.
  Future<String> _resolveGitHubRedirects(String audioAsset) async {
    final rawUrl = '$baseUrl/$audioAsset';
    _log('🔀 Resolving redirects for: $rawUrl');

    String currentUrl = rawUrl;

    try {
      final client = http.Client();

      for (int i = 0; i < 10; i++) {
        _log('   Step $i: GET (Range: bytes=0-0) $currentUrl');

        final req = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['Range'] = 'bytes=0-0';

        final res = await client.send(req);
        await res.stream.drain();

        _log('   Step $i: HTTP ${res.statusCode}');

        if (res.statusCode >= 300 && res.statusCode < 400) {
          final location = res.headers['location'];
          _log('   Step $i: Location header = $location');
          if (location == null || location.isEmpty) {
            _log('   Step $i: No Location header — stopping');
            break;
          }
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
        } else {
          _log('   Step $i: Non-redirect (${res.statusCode}) — final URL reached');
          break;
        }
      }

      client.close();
      _log('✅ Final CDN URL: $currentUrl');
      return currentUrl;
    } catch (e) {
      _log('❌ Redirect resolution failed: $e');
      _log('⚠️ Falling back to raw URL: $rawUrl');
      return rawUrl;
    }
  }

  // ── Explicit Download ─────────────────────────────────────────────────────

  Future<bool> downloadSurah(Surah surah) async {
    _log('📥 downloadSurah: ${surah.nameEn}');

    try {
      final localPath = await _getLocalPath(surah.audioAsset);

      if (await _fileExists(localPath)) {
        _log('✅ Already downloaded: $localPath');
        downloadedSurahs.add(surah.number);
        await _saveDownloadedList();
        notifyListeners();
        return true;
      }

      isDownloading[surah.number] = true;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();

      final url = '$baseUrl/${surah.audioAsset}';
      _log('🌐 Downloading from: $url');

      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();

      _log('   HTTP response: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      _log('   Total size: ${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB');

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

      final finalSize = await file.length();
      _log('✅ Download complete: ${(finalSize / 1024 / 1024).toStringAsFixed(2)} MB saved to $localPath');

      downloadedSurahs.add(surah.number);
      await _saveDownloadedList();
      isDownloading[surah.number] = false;
      downloadProgress[surah.number] = 1.0;
      notifyListeners();
      return true;
    } catch (e, st) {
      _log('❌ Download failed: $e\n$st');
      isDownloading[surah.number] = false;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSurah(Surah surah) async {
    _log('🗑 deleteSurah: ${surah.nameEn}');
    try {
      final file = File(await _getLocalPath(surah.audioAsset));
      if (await file.exists()) {
        await file.delete();
        _log('   Deleted permanent file');
      }

      final cacheFile = await _getCacheFile(surah.audioAsset);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
        _log('   Deleted cache file');
      }

      downloadedSurahs.remove(surah.number);
      await _saveDownloadedList();
      notifyListeners();
      return true;
    } catch (e) {
      _log('❌ Delete failed: $e');
      return false;
    }
  }

  Future<void> downloadAll(List<Surah> surahs) async {
    _log('📦 downloadAll: ${surahs.length} surahs');
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
    _log('✅ downloadAll complete: $batchCompleted downloaded');
    notifyListeners();
  }

  Future<String> getTotalDownloadedSize() async {
    int totalBytes = 0;
    for (final num in downloadedSurahs) {
      final surah = surahs.firstWhere((s) => s.number == num);
      final file = File(await _getLocalPath(surah.audioAsset));
      if (await file.exists()) totalBytes += await file.length();
    }
    final result = '${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB';
    _log('💾 Total downloaded: $result');
    return result;
  }

  Future<void> clearAllDownloads() async {
    _log('🧹 clearAllDownloads');
    for (final num in downloadedSurahs.toList()) {
      await deleteSurah(surahs.firstWhere((s) => s.number == num));
    }
  }
}