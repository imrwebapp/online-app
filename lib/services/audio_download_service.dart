import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/surah.dart';
import '../data/surah_list.dart';

class AudioDownloadService extends ChangeNotifier {
  // GitHub release URL
  static const String baseUrl = 'https://github.com/aounrshah/audio-files/releases/download/v1.0';
  
  // Track download progress for each Surah
  Map<int, double> downloadProgress = {}; // surahNumber -> progress (0.0 to 1.0)
  Map<int, bool> isDownloading = {}; // surahNumber -> downloading status
  Set<int> downloadedSurahs = {}; // Track which surahs are downloaded
  
  // Batch download tracking
  bool isBatchDownloading = false;
  double batchProgress = 0.0;
  int batchCompleted = 0;
  int batchTotal = 0;
  
  AudioDownloadService() {
    _loadDownloadedList();
  }

  // Load list of downloaded surahs from SharedPreferences
  Future<void> _loadDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList('downloaded_surahs') ?? [];
    downloadedSurahs = downloaded.map((e) => int.parse(e)).toSet();
    notifyListeners();
  }

  // Save downloaded list to SharedPreferences
  Future<void> _saveDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'downloaded_surahs',
      downloadedSurahs.map((e) => e.toString()).toList(),
    );
  }

  // Check if a Surah is downloaded
  bool isDownloaded(int surahNumber) {
    return downloadedSurahs.contains(surahNumber);
  }

  // Get local file path for a Surah
  Future<String> _getLocalPath(String audioAsset) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$audioAsset';
  }

  // Check if file exists locally
  Future<bool> _fileExists(String path) async {
    return File(path).exists();
  }

  // Download a Surah
  Future<bool> downloadSurah(Surah surah) async {
    try {
      debugPrint('📥 Starting download: ${surah.nameEn}');
      
      // Check if already downloaded
      final localPath = await _getLocalPath(surah.audioAsset);
      if (await _fileExists(localPath)) {
        debugPrint('✅ Already exists: ${surah.audioAsset}');
        downloadedSurahs.add(surah.number);
        await _saveDownloadedList();
        notifyListeners();
        return true;
      }

      // Mark as downloading
      isDownloading[surah.number] = true;
      downloadProgress[surah.number] = 0.0;
      notifyListeners();

      // Download URL
      final url = '$baseUrl/${surah.audioAsset}';
      debugPrint('🌐 Downloading from: $url');

      // Make HTTP request
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('Failed to download: ${response.statusCode}');
      }

      // Get total size
      final totalBytes = response.contentLength ?? 0;
      debugPrint('📦 Total size: ${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB');

      // Download with progress
      final file = File(localPath);
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

      // Mark as downloaded
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

  // Delete a downloaded Surah
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

  // Get file path for AudioPlayer (local or online)
  Future<String> getAudioPath(Surah surah) async {
    final localPath = await _getLocalPath(surah.audioAsset);
    
    if (await _fileExists(localPath)) {
      debugPrint('🎵 Playing from local: $localPath');
      return localPath;
    } else {
      final url = '$baseUrl/${surah.audioAsset}';
      debugPrint('🌐 Streaming from: $url');
      return url;
    }
  }

  // Download all Surahs
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

  // Get total downloaded size
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

  // Clear all downloads
  Future<void> clearAllDownloads() async {
    for (var surahNum in downloadedSurahs.toList()) {
      final surah = surahs.firstWhere((s) => s.number == surahNum);
      await deleteSurah(surah);
    }
  }
}