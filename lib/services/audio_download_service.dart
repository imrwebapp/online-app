import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/surah.dart';
import '../data/surah_list.dart';
import '../screens/debug_log_screen.dart'; // ← AppLogger

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

  static void _log(String msg) => AppLogger.log('[DownloadService] $msg');

  AudioDownloadService() {
    _log('created');
    _loadDownloadedList();
  }

  Future<void> _loadDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList('downloaded_surahs') ?? [];
    downloadedSurahs = downloaded.map((e) => int.parse(e)).toSet();
    _log('loaded ${downloadedSurahs.length} downloaded surahs');
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
    _log('getAudioSource: ${surah.nameEn}');

    final localPath = await _getLocalPath(surah.audioAsset);
    final exists = await _fileExists(localPath);
    _log('  localPath=$localPath  exists=$exists');

    if (exists) {
      _log('✅ using permanent local file');
      return AudioSource.file(localPath);
    }

    _log('resolving GitHub redirects...');
    final cdnUrl = await _resolveGitHubRedirects(surah.audioAsset);

    final cacheFile = await _getCacheFile(surah.audioAsset);
    final cacheExists = await cacheFile.exists();
    final cacheSize = cacheExists ? await cacheFile.length() : 0;
    _log('  cacheFile=${cacheFile.path}');
    _log('  cacheExists=$cacheExists  cacheSize=${(cacheSize/1024).toStringAsFixed(0)}KB');

    _log('✅ returning LockCachingAudioSource → $cdnUrl');
    return LockCachingAudioSource(
      Uri.parse(cdnUrl),
      cacheFile: cacheFile,
    );
  }

  Future<File> _getCacheFile(String audioAsset) async {
    final dir = await getTemporaryDirectory();
    final baseName = audioAsset
        .replaceAll('/', '_')
        .replaceAll(RegExp(r'\.[^.]+$'), '');
    return File('${dir.path}/${baseName}.mp3');
  }

  Future<String> _resolveGitHubRedirects(String audioAsset) async {
    final rawUrl = '$baseUrl/$audioAsset';
    _log('resolving: $rawUrl');
    String currentUrl = rawUrl;

    try {
      final client = http.Client();

      for (int i = 0; i < 10; i++) {
        final req = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['Range'] = 'bytes=0-0';

        final res = await client.send(req);
        await res.stream.drain();
        _log('  redirect[$i] HTTP ${res.statusCode} → $currentUrl');

        if (res.statusCode >= 300 && res.statusCode < 400) {
          final location = res.headers['location'];
          _log('  Location: $location');
          if (location == null || location.isEmpty) break;
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
        } else {
          _log('  final URL reached at step $i');
          break;
        }
      }

      client.close();
      _log('✅ CDN URL: $currentUrl');
      return currentUrl;
    } catch (e) {
      _log('❌ redirect resolve failed: $e  — using raw URL');
      return rawUrl;
    }
  }

  // ── Explicit Download ─────────────────────────────────────────────────────

  Future<bool> downloadSurah(Surah surah) async {
    _log('downloadSurah: ${surah.nameEn}');
    try {
      final localPath = await _getLocalPath(surah.audioAsset);
      if (await _fileExists(localPath)) {
        _log('already downloaded');
        downloadedSurahs.add(surah.number);
        await _saveDownloadedList();
        notifyListeners();
        return true;
      }

      isDownloading[surah.number] = true;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();

      final request =
          http.Request('GET', Uri.parse('$baseUrl/${surah.audioAsset}'));
      final response = await request.send();
      _log('download HTTP ${response.statusCode}');

      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final totalBytes = response.contentLength ?? 0;
      _log('total: ${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB');

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
      _log('✅ saved ${(received/1024/1024).toStringAsFixed(2)} MB → $localPath');

      downloadedSurahs.add(surah.number);
      await _saveDownloadedList();
      isDownloading[surah.number] = false;
      downloadProgress[surah.number] = 1.0;
      notifyListeners();
      return true;
    } catch (e, st) {
      _log('❌ download failed: $e\n$st');
      isDownloading[surah.number] = false;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSurah(Surah surah) async {
    try {
      final file = File(await _getLocalPath(surah.audioAsset));
      if (await file.exists()) await file.delete();
      final cacheFile = await _getCacheFile(surah.audioAsset);
      if (await cacheFile.exists()) await cacheFile.delete();
      downloadedSurahs.remove(surah.number);
      await _saveDownloadedList();
      notifyListeners();
      return true;
    } catch (e) {
      _log('❌ delete failed: $e');
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