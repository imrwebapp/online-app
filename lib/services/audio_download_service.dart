import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/surah.dart';
import '../data/surah_list.dart';
import '../screens/debug_log_screen.dart';

class AudioDownloadService extends ChangeNotifier {
  static const String _baseUrl =
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

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _loadDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('downloaded_surahs') ?? [];
    downloadedSurahs = list.map(int.parse).toSet();
    _log('loaded ${downloadedSurahs.length} downloaded surahs');
    notifyListeners();
  }

  Future<void> _saveDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'downloaded_surahs', downloadedSurahs.map((e) => e.toString()).toList());
  }

  bool isDownloaded(int n) => downloadedSurahs.contains(n);

  Future<String> _permanentPath(String audioAsset) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$audioAsset';
  }

  // ── Core: getAudioSource ─────────────────────────────────────────────────
  //
  // KEY INSIGHT:
  //   LockCachingAudioSource and StreamAudioSource both route through
  //   just_audio's localhost HTTP proxy. On iOS in release/TestFlight builds
  //   that proxy breaks signed CDN URLs (query params get corrupted or the
  //   cleartext localhost connection is blocked) → -11828 "Cannot Open".
  //
  //   AudioSource.uri() gives the URL DIRECTLY to AVPlayer with NO proxy.
  //   AVPlayer natively handles HTTPS URLs with query parameters perfectly.
  //   This is the correct approach for streaming from a CDN on iOS.

  Future<AudioSource> getAudioSource(Surah surah) async {
    _log('getAudioSource: ${surah.nameEn}');

    // 1. If permanently downloaded, play from local file (best experience)
    final permPath = await _permanentPath(surah.audioAsset);
    if (await File(permPath).exists()) {
      _log('✅ permanent file → AudioSource.file');
      return AudioSource.file(permPath);
    }

    // 2. Resolve GitHub redirect to the real CDN URL, then give it directly
    //    to AVPlayer via AudioSource.uri() — no proxy, no broken query params.
    _log('streaming: resolving GitHub redirect...');
    final cdnUrl = await _resolveGitHubRedirect(surah.audioAsset);
    _log('✅ AudioSource.uri ready — handing to AVPlayer (no proxy)');
    _log('   URL starts with: ${cdnUrl.substring(0, 60)}...');
    return AudioSource.uri(Uri.parse(cdnUrl));
  }

  // ── Redirect resolver ─────────────────────────────────────────────────────

  Future<String> _resolveGitHubRedirect(String audioAsset) async {
    final rawUrl = '$_baseUrl/$audioAsset';
    _log('resolving: $rawUrl');
    String url = rawUrl;
    final client = http.Client();
    try {
      for (int i = 0; i < 10; i++) {
        final req = http.Request('GET', Uri.parse(url))
          ..followRedirects = false
          ..headers['Range'] = 'bytes=0-0';
        final res = await client.send(req);
        await res.stream.drain();
        _log('  [$i] HTTP ${res.statusCode}');
        if (res.statusCode >= 300 && res.statusCode < 400) {
          final loc = res.headers['location'];
          if (loc == null || loc.isEmpty) break;
          url = Uri.parse(url).resolve(loc).toString();
          _log('  → redirecting to CDN URL');
        } else {
          _log('  → final URL reached');
          break;
        }
      }
    } finally {
      client.close();
    }
    _log('✅ resolved CDN URL (length=${url.length})');
    return url;
  }

  // ── Explicit Download (Download button) ───────────────────────────────────

  Future<bool> downloadSurah(Surah surah) async {
    _log('downloadSurah: ${surah.nameEn}');
    final localPath = await _permanentPath(surah.audioAsset);

    if (await File(localPath).exists()) {
      _log('already downloaded');
      downloadedSurahs.add(surah.number);
      await _saveDownloadedList();
      notifyListeners();
      return true;
    }

    try {
      isDownloading[surah.number] = true;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();

      final cdnUrl = await _resolveGitHubRedirect(surah.audioAsset);
      final request = http.Request('GET', Uri.parse(cdnUrl));
      final response = await request.send();
      _log('download HTTP ${response.statusCode}');
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

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
      await sink.flush();
      await sink.close();

      _log('✅ saved ${(received / 1024 / 1024).toStringAsFixed(2)} MB');
      downloadedSurahs.add(surah.number);
      await _saveDownloadedList();
      isDownloading[surah.number] = false;
      downloadProgress[surah.number] = 1.0;
      notifyListeners();
      return true;
    } catch (e, st) {
      _log('❌ downloadSurah error: $e\n$st');
      isDownloading[surah.number] = false;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSurah(Surah surah) async {
    try {
      final file = File(await _permanentPath(surah.audioAsset));
      if (await file.exists()) await file.delete();
      downloadedSurahs.remove(surah.number);
      await _saveDownloadedList();
      notifyListeners();
      return true;
    } catch (e) {
      _log('❌ deleteSurah: $e');
      return false;
    }
  }

  Future<void> downloadAll(List<Surah> surahs) async {
    isBatchDownloading = true;
    batchCompleted = 0;
    batchTotal = surahs.where((s) => !isDownloaded(s.number)).length;
    batchProgress = 0.0;
    notifyListeners();
    for (final s in surahs) {
      if (!isDownloaded(s.number)) {
        if (await downloadSurah(s)) {
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
    int total = 0;
    for (final num in downloadedSurahs) {
      final s = surahs.firstWhere((s) => s.number == num);
      final f = File(await _permanentPath(s.audioAsset));
      if (await f.exists()) total += await f.length();
    }
    return '${(total / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  Future<void> clearAllDownloads() async {
    for (final num in downloadedSurahs.toList()) {
      await deleteSurah(surahs.firstWhere((s) => s.number == num));
    }
  }
}