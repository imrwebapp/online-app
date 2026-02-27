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

  // NEW: Track ongoing operations to prevent concurrent calls
  bool _isOperationInProgress = false;
  
  // NEW: Release mode configuration
  static const Duration _operationTimeout = Duration(seconds: 5);

  AudioService({this.downloadService}) {
    // Configure player for better performance
    _configurePlayer();
    _setupListeners();
  }

  // NEW: Configure player settings
  void _configurePlayer() {
    // Set player mode to low latency for better responsiveness
    _player.setPlayerMode(PlayerMode.mediaPlayer);
    
    // Set release mode to stop (safer than release)
    _player.setReleaseMode(ReleaseMode.stop);
  }

  void _setupListeners() {
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

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      final wasPlaying = isPlaying;
      isPlaying = state == PlayerState.playing;
      
      if (wasPlaying != isPlaying) {
        notifyListeners();
      }
    });
  }

  // ------------------------------
  // Enhanced Surah Player with ANR Protection
  // ------------------------------
  Future<void> setSurahAndPlay(Surah s, {bool autoplay = true}) async {
    // Prevent concurrent operations
    if (_isOperationInProgress) {
      debugPrint('⏳ Operation in progress, queuing request');
      await Future.delayed(Duration(milliseconds: 100));
      if (_isOperationInProgress) {
        debugPrint('⚠️ Still busy, aborting request');
        return;
      }
    }

    _isOperationInProgress = true;

    try {
      if (currentSurah?.number != s.number) {
        // Use safe stop with timeout
        await _safeStop();
        
        currentSurah = s;
        position = Duration.zero;
        duration = Duration.zero;
        notifyListeners();
      }
      
      if (autoplay) {
        await play();
      }
    } catch (e) {
      debugPrint('❌ Error in setSurahAndPlay: $e');
      rethrow;
    } finally {
      _isOperationInProgress = false;
    }
  }

  // NEW: Safe stop with timeout
  Future<void> _safeStop() async {
    try {
      await _player.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⚠️ Stop operation timed out - forcing state reset');
          // Force state update even if stop hangs
          isPlaying = false;
          position = Duration.zero;
        },
      );
    } catch (e) {
      debugPrint('⚠️ Error stopping player: $e');
      // Continue anyway - don't let stop errors block playback
      isPlaying = false;
      position = Duration.zero;
    }
  }

  Future<void> play() async {
    // Prevent multiple simultaneous play calls
    if (isLoading || _isOperationInProgress) {
      debugPrint('⏳ Already loading/busy, ignoring play request');
      return;
    }

    if (currentSurah == null) {
      debugPrint('⚠️ No surah selected');
      return;
    }

    _isOperationInProgress = true;

    try {
      // Check current player state
      final currentState = _player.state;
      
      // If already playing, do nothing
      if (currentState == PlayerState.playing) {
        debugPrint('✅ Already playing');
        isPlaying = true;
        notifyListeners();
        return;
      }

      // If paused, just resume with timeout
      if (currentState == PlayerState.paused) {
        debugPrint('▶️ Resuming playback');
        await _player.resume().timeout(
          _operationTimeout,
          onTimeout: () {
            debugPrint('⚠️ Resume timed out');
            throw TimeoutException('Resume operation timed out');
          },
        );
        isPlaying = true;
        notifyListeners();
        return;
      }

      // Start new playback
      isLoading = true;
      notifyListeners();

      String audioPath;
      
      // Get audio source with timeout
      if (downloadService != null) {
        audioPath = await downloadService!.getAudioPath(currentSurah!).timeout(
          Duration(seconds: 3),
          onTimeout: () {
            debugPrint('⚠️ getAudioPath timed out');
            throw TimeoutException('Failed to get audio path');
          },
        );
        
        // Play with timeout protection
        if (audioPath.startsWith('http')) {
          debugPrint('🌐 Streaming: $audioPath');
          await _player.play(UrlSource(audioPath)).timeout(
            _operationTimeout,
            onTimeout: () {
              debugPrint('⚠️ Network play timed out');
              throw TimeoutException('Network playback initialization timed out');
            },
          );
        } else {
          debugPrint('📱 Playing local: $audioPath');
          await _player.play(DeviceFileSource(audioPath)).timeout(
            _operationTimeout,
            onTimeout: () {
              debugPrint('⚠️ Local play timed out');
              throw TimeoutException('Local playback initialization timed out');
            },
          );
        }
      } else {
        // Fallback to asset
        audioPath = 'audios/${currentSurah!.audioAsset}';
        debugPrint('📦 Playing asset: $audioPath');
        await _player.play(AssetSource(audioPath)).timeout(
          _operationTimeout,
          onTimeout: () {
            debugPrint('⚠️ Asset play timed out');
            throw TimeoutException('Asset playback initialization timed out');
          },
        );
      }

      isPlaying = true;
      isLoading = false;
      notifyListeners();
      debugPrint('✅ Playback started successfully');
      
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Play timeout: $e');
      isPlaying = false;
      isLoading = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      debugPrint('❌ Playback error: $e');
      isPlaying = false;
      isLoading = false;
      notifyListeners();
      rethrow;
    } finally {
      _isOperationInProgress = false;
    }
  }

  Future<void> pause() async {
    // Prevent concurrent operations
    if (_isOperationInProgress) {
      debugPrint('⏳ Operation in progress, ignoring pause');
      return;
    }

    // Check if already paused
    if (!isPlaying && _player.state != PlayerState.playing) {
      debugPrint('⏸️ Already paused');
      return;
    }

    _isOperationInProgress = true;

    try {
      // Pause with timeout protection
      await _player.pause().timeout(
        Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⚠️ Pause timed out - forcing state');
          // Force state update even if pause hangs
          isPlaying = false;
        },
      );
      
      isPlaying = false;
      notifyListeners();
      debugPrint('⏸️ Paused successfully');
      
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Pause timeout: $e');
      isPlaying = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      debugPrint('❌ Pause error: $e');
      isPlaying = false;
      notifyListeners();
      rethrow;
    } finally {
      _isOperationInProgress = false;
    }
  }

  Future<void> stop() async {
    // Use safe stop
    await _safeStop();
    isPlaying = false;
    position = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    // Prevent seeking during other operations
    if (_isOperationInProgress || isLoading) {
      debugPrint('⏳ Busy, ignoring seek');
      return;
    }

    try {
      // Seek with timeout
      await _player.seek(pos).timeout(
        Duration(seconds: 1),
        onTimeout: () {
          debugPrint('⚠️ Seek timed out');
          // Update position anyway for UI consistency
          position = pos;
        },
      );
      
      position = pos;
      notifyListeners();
      
    } catch (e) {
      debugPrint('⚠️ Seek error: $e');
      // Don't throw - seeking errors shouldn't break the app
      position = pos;
      notifyListeners();
    }
  }

  // NEW: Safe disposal method
  Future<void> disposePlayer() async {
    debugPrint('🔄 Disposing AudioService...');
    
    // Cancel subscriptions first (fast operation)
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _compSub?.cancel();
    await _stateSub?.cancel();

    // Don't await player disposal - let it happen in background
    // This prevents ANRs during app closure
    _player.dispose().then((_) {
      debugPrint('✅ Player disposed successfully');
    }).catchError((e) {
      debugPrint('⚠️ Player disposal error (non-blocking): $e');
    });
  }

  @override
  void dispose() {
    // Fire and forget - don't block disposal
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

  // NEW: Helper to check if player is in a good state
  bool get canPlay => !isLoading && !_isOperationInProgress;
  
  // NEW: Helper to get current player state
  PlayerState get playerState => _player.state;
}