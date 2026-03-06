import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
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
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<ProcessingState>? _processingStateSub;

  bool _isOperationInProgress = false;

  AudioService({this.downloadService}) {
    _setupListeners();
  }

  void _setupListeners() {
    // Position updates
    _posSub = _player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });

    // Duration updates
    _durSub = _player.durationStream.listen((d) {
      duration = d ?? Duration.zero;
      notifyListeners();
    });

    // Playing state updates
    _stateSub = _player.playerStateStream.listen((state) {
      final wasPlaying = isPlaying;

      // completed → reset position
      if (state.processingState == ProcessingState.completed) {
        isPlaying = false;
        position = duration;
        notifyListeners();
        return;
      }

      isPlaying = state.playing;
      if (wasPlaying != isPlaying) notifyListeners();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> setSurahAndPlay(Surah s, {bool autoplay = true}) async {
    if (_isOperationInProgress) {
      debugPrint('⏳ Operation in progress, ignoring request');
      return;
    }
    _isOperationInProgress = true;

    try {
      if (currentSurah?.number != s.number) {
        await _safeStop();
        currentSurah = s;
        position = Duration.zero;
        duration = Duration.zero;
        notifyListeners();
      }

      if (autoplay) await play();
    } catch (e) {
      debugPrint('❌ setSurahAndPlay error: $e');
    } finally {
      _isOperationInProgress = false;
    }
  }

  Future<void> _safeStop() async {
    try {
      await _player.stop().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⚠️ Stop timed out');
          isPlaying = false;
          position = Duration.zero;
        },
      );
    } catch (e) {
      debugPrint('⚠️ Stop error (non-blocking): $e');
      isPlaying = false;
      position = Duration.zero;
    }
  }

  Future<void> play() async {
    if (isLoading || _isOperationInProgress) {
      debugPrint('⏳ Busy, ignoring play');
      return;
    }
    if (currentSurah == null) {
      debugPrint('⚠️ No surah selected');
      return;
    }

    _isOperationInProgress = true;

    try {
      // Already playing
      if (_player.playing) {
        isPlaying = true;
        notifyListeners();
        return;
      }

      // Paused → resume without re-loading source
      if (_player.processingState == ProcessingState.ready &&
          !_player.playing) {
        debugPrint('▶️ Resuming');
        await _player.play();
        isPlaying = true;
        notifyListeners();
        return;
      }

      // New playback — load source
      isLoading = true;
      notifyListeners();

      if (downloadService != null) {
        final source = await downloadService!
            .getAudioSource(currentSurah!)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('getAudioSource timed out'),
            );

        debugPrint('🎵 Setting audio source...');
        await _player.setAudioSource(source);
        await _player.play();
      } else {
        // Fallback: bundled asset
        final assetPath = 'assets/audios/${currentSurah!.audioAsset}';
        debugPrint('📦 Playing asset: $assetPath');
        await _player.setAudioSource(AudioSource.asset(assetPath));
        await _player.play();
      }

      isPlaying = true;
      isLoading = false;
      notifyListeners();
      debugPrint('✅ Playback started: ${currentSurah!.nameEn}');
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Play timeout: $e');
      isPlaying = false;
      isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Play error: $e');
      isPlaying = false;
      isLoading = false;
      notifyListeners();
    } finally {
      _isOperationInProgress = false;
    }
  }

  Future<void> pause() async {
    if (_isOperationInProgress) return;
    _isOperationInProgress = true;

    try {
      await _player.pause().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          isPlaying = false;
        },
      );
      isPlaying = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Pause error: $e');
      isPlaying = false;
      notifyListeners();
    } finally {
      _isOperationInProgress = false;
    }
  }

  Future<void> stop() async {
    await _safeStop();
    isPlaying = false;
    position = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    if (isLoading) return;
    try {
      await _player.seek(pos);
      position = pos;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Seek error: $e');
      position = pos;
      notifyListeners();
    }
  }

  bool get canPlay => !isLoading && !_isOperationInProgress;

  // ─────────────────────────────────────────────────────────────────────────
  // Foreground Azan Controls (unchanged)
  // ─────────────────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _processingStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}