import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import '../models/surah.dart';
import '../data/surah_list.dart';
import '../screens/debug_log_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _ProgressiveStream
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressiveStream {
  final String tempPath;
  final int totalBytes;
  int _writtenBytes = 0;
  bool _downloadComplete = false;
  bool _failed = false;

  final _dataController = StreamController<void>.broadcast();

  _ProgressiveStream({
    required this.tempPath,
    required this.totalBytes,
  });

  int get writtenBytes => _writtenBytes;
  bool get downloadComplete => _downloadComplete;
  bool get failed => _failed;
  double get progress =>
      totalBytes > 0 ? (_writtenBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  void onChunkWritten(int bytes) {
    _writtenBytes += bytes;
    if (!_dataController.isClosed) _dataController.add(null);
  }

  void onComplete() {
    _downloadComplete = true;
    if (!_dataController.isClosed) {
      _dataController.add(null);
      _dataController.close();
    }
  }

  void onError() {
    _failed = true;
    if (!_dataController.isClosed) _dataController.close();
  }

  Future<void> waitForBytes(int needed) async {
    if (_writtenBytes >= needed || _downloadComplete || _failed) return;
    await for (final _ in _dataController.stream) {
      if (_writtenBytes >= needed || _downloadComplete || _failed) return;
    }
  }

  Future<void> dispose() async {
    if (!_dataController.isClosed) await _dataController.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mp3DurationEstimator
//
// Reads the first valid MP3 frame header to detect bitrate, then:
//   duration = fileSizeBytes / (bitrateKbps * 1000 / 8)
//
// For VBR files, reads the Xing/Info header for an exact frame count.
// Accurate to ~1% for CBR (all standard Quran recitation audio is CBR).
// ─────────────────────────────────────────────────────────────────────────────
class Mp3DurationEstimator {
  static const _bitratesKbps = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0
  ];
  static const _sampleRates = [44100, 48000, 32000, 0];

  static Duration? estimate(List<int> headerBytes, int totalFileBytes) {
    if (totalFileBytes <= 0 || headerBytes.length < 10) return null;

    // Skip ID3v2 tag if present
    int offset = 0;
    if (headerBytes[0] == 0x49 && headerBytes[1] == 0x44 && headerBytes[2] == 0x33) {
      final id3Size = ((headerBytes[6] & 0x7F) << 21) |
          ((headerBytes[7] & 0x7F) << 14) |
          ((headerBytes[8] & 0x7F) << 7) |
          (headerBytes[9] & 0x7F);
      offset = 10 + id3Size;
    }

    // Scan for MP3 sync word
    for (int i = offset; i < headerBytes.length - 4; i++) {
      if (headerBytes[i] != 0xFF || (headerBytes[i + 1] & 0xE0) != 0xE0) continue;

      final h2 = headerBytes[i + 2];
      final bitrateIndex = (h2 >> 4) & 0x0F;
      final sampleRateIndex = (h2 >> 2) & 0x03;

      if (bitrateIndex == 0 || bitrateIndex == 15) continue;
      if (sampleRateIndex == 3) continue;

      final bitrateKbps = _bitratesKbps[bitrateIndex];
      final sampleRate = _sampleRates[sampleRateIndex];
      if (bitrateKbps <= 0 || sampleRate <= 0) continue;

      // Check for Xing/Info VBR header (stereo MPEG1 Layer3: side info = 32 bytes)
      final xingOffset = i + 4 + 32;
      if (xingOffset + 16 < headerBytes.length) {
        final tag = String.fromCharCodes(headerBytes.sublist(xingOffset, xingOffset + 4));
        if (tag == 'Xing' || tag == 'Info') {
          final flags = (headerBytes[xingOffset + 4] << 24) |
              (headerBytes[xingOffset + 5] << 16) |
              (headerBytes[xingOffset + 6] << 8) |
              headerBytes[xingOffset + 7];
          if (flags & 0x02 != 0 && xingOffset + 12 < headerBytes.length) {
            final totalFrames = (headerBytes[xingOffset + 8] << 24) |
                (headerBytes[xingOffset + 9] << 16) |
                (headerBytes[xingOffset + 10] << 8) |
                headerBytes[xingOffset + 11];
            if (totalFrames > 0) {
              final durationMs = (totalFrames * 1152 * 1000) ~/ sampleRate;
              return Duration(milliseconds: durationMs);
            }
          }
        }
      }

      // CBR: duration = fileSize / bytesPerSecond
      final bytesPerSecond = (bitrateKbps * 1000) ~/ 8;
      final durationMs = (totalFileBytes * 1000) ~/ bytesPerSecond;
      return Duration(milliseconds: durationMs);
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AudioDownloadService
// ─────────────────────────────────────────────────────────────────────────────
class AudioDownloadService extends ChangeNotifier {
  static const String _baseUrl =
      'https://github.com/aounrshah/audio-files/releases/download/v1.0';

  HttpServer? _proxyServer;
  int _proxyPort = 0;

  _ProgressiveStream? _activeStream;
  int? _activeStreamSurahNumber;

  /// Populated by getAudioSource() for streaming surahs.
  /// Your AudioService should read this immediately after getAudioSource()
  /// returns and use it as the display duration until AVPlayer reports its own.
  Duration? estimatedDuration;

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
    _startProxyServer();
  }

  // ── Proxy server ──────────────────────────────────────────────────────────

  Future<void> _startProxyServer() async {
    final handler = const shelf.Pipeline().addHandler(_handleProxyRequest);
    _proxyServer = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    _proxyPort = _proxyServer!.port;
    _log('✅ proxy server on port $_proxyPort');
  }

  Future<shelf.Response> _handleProxyRequest(shelf.Request request) async {
    final stream = _activeStream;
    if (stream == null) {
      return shelf.Response.internalServerError(body: 'No active stream');
    }

    int start = 0;
    int? end;
    final rangeHeader = request.headers['range'];
    if (rangeHeader != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (m != null) {
        start = int.parse(m.group(1)!);
        final e = m.group(2)!;
        if (e.isNotEmpty) end = int.parse(e);
      }
    }

    final total = stream.totalBytes;
    final effectiveEnd = end ?? (total > 0 ? total - 1 : null);
    final needed = effectiveEnd != null ? effectiveEnd + 1 : start + 1;

    await stream.waitForBytes(needed);
    if (stream.failed) {
      return shelf.Response.internalServerError(body: 'Download failed');
    }

    final available = stream.writtenBytes;
    final readEnd = effectiveEnd != null
        ? effectiveEnd.clamp(0, available - 1)
        : available - 1;
    final length = readEnd - start + 1;

    if (length <= 0) return shelf.Response(416, body: 'Range Not Satisfiable');

    final raf = await File(stream.tempPath).open();
    await raf.setPosition(start);
    final bytes = await raf.read(length);
    await raf.close();

    final headers = <String, String>{
      'Content-Type': 'audio/mpeg',
      'Accept-Ranges': 'bytes',
      'Content-Length': '$length',
      'Content-Range': total > 0
          ? 'bytes $start-$readEnd/$total'
          : 'bytes $start-$readEnd/*',
    };

    _log('proxy: bytes $start–$readEnd / ${total > 0 ? total : "?"}');
    return shelf.Response(206, body: bytes, headers: headers);
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
    await prefs.setStringList('downloaded_surahs',
        downloadedSurahs.map((e) => e.toString()).toList());
  }

  bool isDownloaded(int n) => downloadedSurahs.contains(n);

  Future<String> _permanentPath(String audioAsset) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$audioAsset';
  }

  Future<String> _tempPath(String audioAsset) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/stream_$audioAsset';
  }

  // ── Core: getAudioSource ─────────────────────────────────────────────────

  Future<AudioSource> getAudioSource(Surah surah) async {
    _log('getAudioSource: ${surah.nameEn}');
    estimatedDuration = null;

    // 1. Permanently downloaded
    final permPath = await _permanentPath(surah.audioAsset);
    if (await File(permPath).exists()) {
      _log('✅ permanent file → AudioSource.file');
      return AudioSource.file(permPath);
    }

    // 2. Fully cached temp from a previous session
    final tmpPath = await _tempPath(surah.audioAsset);
    final tmpFile = File(tmpPath);
    if (await tmpFile.exists() &&
        _activeStreamSurahNumber != surah.number &&
        (await tmpFile.length()) > 0) {
      _log('✅ cached temp file → AudioSource.file');
      return AudioSource.file(tmpPath);
    }

    // 3. Start progressive download
    if (_activeStreamSurahNumber != surah.number) {
      await _startProgressiveDownload(surah, tmpPath);
    }

    // Wait for 128 KB initial buffer
    const initialBuffer = 128 * 1024;
    _log('⏳ waiting for ${initialBuffer ~/ 1024} KB buffer...');
    await _activeStream!.waitForBytes(initialBuffer);

    if (_activeStream!.failed) {
      throw Exception('Progressive download failed during initial buffer');
    }

    // ── Estimate duration from buffered header bytes ──────────────────────
    try {
      final raf = await File(tmpPath).open();
      final headerBytes = await raf.read(65536); // read first 64 KB
      await raf.close();
      final dur = Mp3DurationEstimator.estimate(headerBytes, _activeStream!.totalBytes);
      if (dur != null) {
        estimatedDuration = dur;
        final mm = dur.inMinutes.toString().padLeft(2, '0');
        final ss = (dur.inSeconds % 60).toString().padLeft(2, '0');
        _log('✅ estimated duration: $mm:$ss');
      } else {
        _log('⚠️ could not estimate duration from MP3 header');
      }
    } catch (e) {
      _log('duration estimate error: $e');
    }

    _log('✅ buffer ready → localhost:$_proxyPort');
    return AudioSource.uri(
      Uri.parse('http://127.0.0.1:$_proxyPort/audio'),
      headers: {'Connection': 'keep-alive'},
    );
  }

  // ── Progressive background download ───────────────────────────────────────

  Future<void> _startProgressiveDownload(Surah surah, String tmpPath) async {
    _log('starting progressive download: ${surah.nameEn}');

    await _activeStream?.dispose();
    _activeStream = null;
    _activeStreamSurahNumber = null;

    final tmpFile = File(tmpPath);
    if (await tmpFile.exists()) await tmpFile.delete();
    await tmpFile.parent.create(recursive: true);

    final cdnUrl = await _resolveGitHubRedirect(surah.audioAsset);

    final request = http.Request('GET', Uri.parse(cdnUrl));
    request.headers['Accept'] = '*/*';
    request.headers['User-Agent'] = 'Mozilla/5.0';

    final response = await request.send();
    _log('progressive HTTP ${response.statusCode}');

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    _log('file size: ${totalBytes > 0 ? "${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB" : "unknown"}');

    final stream = _ProgressiveStream(tempPath: tmpPath, totalBytes: totalBytes);
    _activeStream = stream;
    _activeStreamSurahNumber = surah.number;

    _downloadInBackground(surah, stream, response, tmpPath, totalBytes);
  }

  void _downloadInBackground(
    Surah surah,
    _ProgressiveStream stream,
    http.StreamedResponse response,
    String tmpPath,
    int totalBytes,
  ) async {
    final sink = File(tmpPath).openWrite();
    int received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        stream.onChunkWritten(chunk.length);
        if (totalBytes > 0) {
          downloadProgress[surah.number] = received / totalBytes;
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      stream.onComplete();
      downloadProgress[surah.number] = 1.0;
      _log('✅ download complete: ${(received / 1024 / 1024).toStringAsFixed(2)} MB');
      notifyListeners();
    } catch (e, st) {
      await sink.close();
      stream.onError();
      _log('❌ background download error: $e\n$st');
    }
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

  // ── Explicit Download ─────────────────────────────────────────────────────

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

    // Piggyback on active progressive stream
    if (_activeStreamSurahNumber == surah.number && _activeStream != null) {
      _log('piggybacking on active stream...');
      final stream = _activeStream!;
      isDownloading[surah.number] = true;
      notifyListeners();

      if (stream.totalBytes > 0) {
        await stream.waitForBytes(stream.totalBytes);
      } else {
        while (!stream.downloadComplete && !stream.failed) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (!stream.failed && await File(stream.tempPath).exists()) {
        await File(stream.tempPath).copy(localPath);
        await File(stream.tempPath).delete();
        _log('✅ promoted temp → permanent');
        downloadedSurahs.add(surah.number);
        await _saveDownloadedList();
        isDownloading[surah.number] = false;
        downloadProgress[surah.number] = 1.0;
        notifyListeners();
        return true;
      }
    }

    try {
      isDownloading[surah.number] = true;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();

      final cdnUrl = await _resolveGitHubRedirect(surah.audioAsset);
      final request = http.Request('GET', Uri.parse(cdnUrl));
      request.headers['Accept'] = '*/*';
      request.headers['User-Agent'] = 'Mozilla/5.0';

      final response = await request.send();
      _log('download HTTP ${response.statusCode}');
      if (response.statusCode != 200 && response.statusCode != 206) {
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
      await sink.flush();
      await sink.close();

      final tmpFile = File(await _tempPath(surah.audioAsset));
      if (await tmpFile.exists()) await tmpFile.delete();

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
      final permFile = File(await _permanentPath(surah.audioAsset));
      if (await permFile.exists()) await permFile.delete();
      final tmpFile = File(await _tempPath(surah.audioAsset));
      if (await tmpFile.exists()) await tmpFile.delete();
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

  Future<void> clearTempFiles() async {
    final dir = await getTemporaryDirectory();
    try {
      final files = dir.listSync().whereType<File>()
          .where((f) => f.path.contains('stream_'));
      for (final f in files) await f.delete();
      _log('🧹 cleared temp stream files');
    } catch (e) {
      _log('clearTempFiles error: $e');
    }
  }

  @override
  void dispose() {
    _activeStream?.dispose();
    _proxyServer?.close();
    super.dispose();
  }
}