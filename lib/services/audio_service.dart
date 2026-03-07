import 'dart:async';
import 'package:audio_session/audio_session.dart';
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

  // Guards against concurrent load calls only — NOT against play/pause
  bool _isLoadingSource = false;

  AudioService({this.downloadService}) {
    _initAudioSession();
    _setupListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUDIO SESSION
  // Required on iOS so AVAudioSession is set to .playback category.
  // Without this, audio silently fails when the device ring/silent switch
  // is set to silent, or when the screen is locked.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
      debugPrint('✅ AudioSession configured');
    } catch (e) {
      debugPrint('⚠️ AudioSession config failed (non-critical): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LISTENERS
  // ─────────────────────────────────────────────────────────────────────────
  void _setupListeners() {
    _posSub = _player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });

    _durSub = _player.durationStream.listen((d) {
      if (d != null && d > Duration.zero) {
        duration = d;
        notifyListeners();
      }
    });

    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        isPlaying = false;
        position = duration;
        notifyListeners();
        return;
      }
      final playing = state.playing;
      if (playing != isPlaying) {
        isPlaying = playing;
        notifyListeners();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Load a new surah and optionally start playing.
  /// Safe to call from UI — will not deadlock.
  Future<void> setSurahAndPlay(Surah s, {bool autoplay = true}) async {
    final isSameSurah = currentSurah?.number == s.number;

    if (isSameSurah) {
      // Same surah — just resume/play if autoplay requested
      if (autoplay && !_player.playing) {
        await play();
      }
      return;
    }

    // Different surah — stop current, load new one
    await _safeStop();
    currentSurah = s;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();

    if (autoplay) {
      await _loadAndPlay();
    }
  }

  /// Resume or start playback of the current surah.
  Future<void> play() async {
    if (currentSurah == null) return;

    // Already playing — nothing to do
    if (_player.playing) return;

    // Source is loaded and ready — just resume
    if (_player.processingState == ProcessingState.ready) {
      await _player.play();
      return;
    }

    // Source not loaded yet — load then play
    await _loadAndPlay();
  }

  /// Load the audio source for [currentSurah] and start playback.
  /// Uses a simple boolean guard to prevent duplicate concurrent loads.
  Future<void> _loadAndPlay() async {
    if (_isLoadingSource) {
      debugPrint('⏳ Already loading source, ignoring duplicate request');
      return;
    }
    if (currentSurah == null) return;

    _isLoadingSource = true;
    isLoading = true;
    notifyListeners();

    try {
      AudioSource source;

      if (downloadService != null) {
        source = await downloadService!.getAudioSource(currentSurah!);
      } else {
        source = AudioSource.asset('assets/audios/${currentSurah!.audioAsset}');
      }

      debugPrint('🎵 setAudioSource: ${currentSurah!.nameEn}');

      // setAudioSource resolves the duration and prepares the decoder.
      // For LockCachingAudioSource this also starts the local proxy.
      final loadedDuration = await _player.setAudioSource(
        source,
        preload: true,  // preload=true so duration is known before play()
      );

      if (loadedDuration != null && loadedDuration > Duration.zero) {
        duration = loadedDuration;
        debugPrint('⏱ Duration: $duration');
      }

      isLoading = false;
      notifyListeners();

      await _player.play();
      debugPrint('▶️ Playback started: ${currentSurah!.nameEn}');
    } catch (e) {
      debugPrint('❌ _loadAndPlay error: $e');
      isLoading = false;
      isPlaying = false;
      notifyListeners();
    } finally {
      _isLoadingSource = false;
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('⚠️ Pause error: $e');
      isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _safeStop();
  }

  Future<void> seek(Duration pos) async {
    if (isLoading) return;
    try {
      await _player.seek(pos);
    } catch (e) {
      debugPrint('⚠️ Seek error: $e');
    }
  }

  Future<void> _safeStop() async {
    try {
      await _player.stop();
      isPlaying = false;
      position = Duration.zero;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Stop error: $e');
      isPlaying = false;
      position = Duration.zero;
    }
  }

  bool get canPlay => !isLoading && !_isLoadingSource;

  // ─────────────────────────────────────────────────────────────────────────
  // AZAN (unchanged)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> playAzan({String prayerName = 'Azan'}) async {
    try {
      await AzanForegroundService.startForegroundAzan(prayerName: prayerName);
    } catch (e, st) {
      debugPrint('❌ playAzan error: $e\n$st');
    }
  }

  static Future<void> stopAzan() async {
    try {
      await AzanForegroundService.stopForegroundAzan();
    } catch (e, st) {
      debugPrint('⚠️ stopAzan error: $e\n$st');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}