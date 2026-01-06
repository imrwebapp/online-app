import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/surah.dart';
import 'azan_foreground_service.dart';
import 'audio_download_service.dart';

class AudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final AudioDownloadService? downloadService;
  
  Surah? currentSurah;
  bool isPlaying = false;
  bool isLoading = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _compSub;
  StreamSubscription<PlayerState>? _stateSub;

  AudioService({this.downloadService}) {
    _durSub = _player.onDurationChanged.listen((d) {
      duration = d;
      notifyListeners();
    });

    _posSub = _player.onPositionChanged.listen((p) {
      position = p;
      notifyListeners();
    });

    _compSub = _player.onPlayerComplete.listen((_) {
      isPlaying = false;
      position = duration;
      notifyListeners();
    });

    // Listen to player state changes for more accurate state tracking
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      final wasPlaying = isPlaying;
      isPlaying = state == PlayerState.playing;
      
      // Only notify if state actually changed
      if (wasPlaying != isPlaying) {
        notifyListeners();
      }
    });
  }

  // ------------------------------
  // Enhanced Surah Player (Online/Offline)
  // ------------------------------
  Future<void> setSurahAndPlay(Surah s, {bool autoplay = true}) async {
    if (currentSurah?.number != s.number) {
      await _player.stop();
      currentSurah = s;
      position = Duration.zero;
      duration = Duration.zero;
      notifyListeners();
    }
    if (autoplay) await play();
  }

  Future<void> play() async {
    // Prevent multiple simultaneous play calls
    if (isLoading) {
      debugPrint('⏳ Already loading, ignoring play request');
      return;
    }

    if (currentSurah == null) {
      debugPrint('⚠️ No surah selected');
      return;
    }

    try {
      // Check current player state
      final currentState = _player.state;
      
      // If already playing, just resume
      if (currentState == PlayerState.paused) {
        debugPrint('▶️ Resuming playback');
        await _player.resume();
        isPlaying = true;
        notifyListeners();
        return;
      }

      // If already playing, do nothing
      if (currentState == PlayerState.playing) {
        debugPrint('✅ Already playing');
        isPlaying = true;
        notifyListeners();
        return;
      }

      // Start new playback
      isLoading = true;
      notifyListeners();

      String audioPath;
      
      // Check if downloadService is available
      if (downloadService != null) {
        // Get audio path (local file or online URL)
        audioPath = await downloadService!.getAudioPath(currentSurah!);
        
        // Check if it's a local file or URL
        if (audioPath.startsWith('http')) {
          // Stream from online
          debugPrint('🌐 Streaming: $audioPath');
          await _player.play(UrlSource(audioPath));
        } else {
          // Play from local file
          debugPrint('📱 Playing local: $audioPath');
          await _player.play(DeviceFileSource(audioPath));
        }
      } else {
        // Fallback to asset (original behavior)
        audioPath = 'audios/${currentSurah!.audioAsset}';
        debugPrint('📦 Playing asset: $audioPath');
        await _player.play(AssetSource(audioPath));
      }

      isPlaying = true;
      isLoading = false;
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ Playback error: $e');
      isPlaying = false;
      isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> pause() async {
    // Prevent multiple pause calls
    if (!isPlaying && _player.state != PlayerState.playing) {
      debugPrint('⏸️ Already paused');
      return;
    }

    try {
      await _player.pause();
      isPlaying = false;
      notifyListeners();
      debugPrint('⏸️ Paused');
    } catch (e) {
      debugPrint('❌ Pause error: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    await _player.stop();
    isPlaying = false;
    position = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
    position = pos;
    notifyListeners();
  }

  Future<void> disposePlayer() async {
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _compSub?.cancel();
    await _stateSub?.cancel();
    await _player.dispose();
  }

  @override
  void dispose() {
    disposePlayer();
    super.dispose();
  }

  // ------------------------------
  // Foreground Azan Controls
  // ------------------------------
  static Future<void> playAzan({String prayerName = "Azan"}) async {
    try {
      debugPrint('🕌 Starting Foreground Azan...');
      await AzanForegroundService.startForegroundAzan(prayerName: prayerName);
    } catch (e, st) {
      debugPrint('❌ Error playing Azan: $e\n$st');
    }
  }

  static Future<void> stopAzan() async {
    try {
      debugPrint('🛑 Stopping Foreground Azan...');
      await AzanForegroundService.stopForegroundAzan();
    } catch (e, st) {
      debugPrint('⚠ Error stopping Azan: $e\n$st');
    }
  }
}