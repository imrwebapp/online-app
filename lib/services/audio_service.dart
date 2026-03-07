import 'dart:async';
import 'dart:developer' as dev;
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

  // ALL state derived from just_audio streams — never toggled manually
  bool isPlaying = false;
  bool isLoading = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _isLoadingSource = false;

  AudioService({this.downloadService}) {
    _log('🔧 AudioService created');
    _initAudioSession();
    _setupListeners();
  }

  // ── Logging helper ────────────────────────────────────────────────────────
  void _log(String msg) {
    dev.log(msg, name: 'AudioService');
    debugPrint('[AudioService] $msg');
  }

  // ── Audio Session ─────────────────────────────────────────────────────────
  Future<void> _initAudioSession() async {
    try {
      _log('🎧 Configuring AVAudioSession...');
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
      _log('✅ AVAudioSession configured: category=playback');
    } catch (e) {
      _log('⚠️ AVAudioSession config failed (non-critical): $e');
    }
  }

  // ── Listeners ─────────────────────────────────────────────────────────────
  void _setupListeners() {
    _log('👂 Setting up just_audio stream listeners...');

    _posSub = _player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });

    _durSub = _player.durationStream.listen((d) {
      _log('⏱ durationStream fired: $d');
      if (d != null && d > Duration.zero) {
        duration = d;
        notifyListeners();
      }
    });

    _stateSub = _player.playerStateStream.listen((state) {
      final ps = state.processingState;
      final playing = state.playing;

      _log('📡 playerStateStream → playing=$playing  processingState=${ps.name}');

      final loading =
          ps == ProcessingState.loading || ps == ProcessingState.buffering;
      final nowPlaying = playing && ps != ProcessingState.completed;
      final completed = ps == ProcessingState.completed;

      bool changed = false;

      if (isLoading != loading) {
        isLoading = loading;
        _log(isLoading ? '⏳ isLoading = TRUE' : '✅ isLoading = FALSE');
        changed = true;
      }

      if (isPlaying != nowPlaying) {
        isPlaying = nowPlaying;
        _log(isPlaying ? '▶️ isPlaying = TRUE' : '⏸ isPlaying = FALSE');
        changed = true;
      }

      if (completed) {
        _log('🏁 Playback completed');
        position = duration;
        changed = true;
      }

      if (changed) notifyListeners();
    });

    _log('✅ Listeners ready');
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> setSurahAndPlay(Surah s, {bool autoplay = true}) async {
    _log('📖 setSurahAndPlay: ${s.nameEn}  autoplay=$autoplay');

    final isSame = currentSurah?.number == s.number;

    if (isSame) {
      _log('ℹ️ Same surah already loaded');
      if (autoplay && !_player.playing) await play();
      return;
    }

    _log('🔄 New surah — stopping current player...');
    try {
      await _player.stop();
    } catch (e) {
      _log('⚠️ Stop error (ignored): $e');
    }

    currentSurah = s;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();

    if (autoplay) await _loadAndPlay();
  }

  Future<void> play() async {
    _log('▶️ play() called  currentSurah=${currentSurah?.nameEn}');

    if (currentSurah == null) {
      _log('⚠️ play() — no surah selected, returning');
      return;
    }

    if (_player.playing) {
      _log('ℹ️ Already playing, ignoring play()');
      return;
    }

    if (_player.processingState == ProcessingState.ready) {
      _log('▶️ Source ready — resuming');
      await _player.play();
      return;
    }

    _log('📥 Source not ready (state=${_player.processingState.name}) — loading...');
    await _loadAndPlay();
  }

  Future<void> pause() async {
    _log('⏸ pause() called');
    try {
      await _player.pause();
      _log('✅ Paused');
    } catch (e) {
      _log('❌ Pause error: $e');
    }
  }

  Future<void> stop() async {
    _log('⏹ stop() called');
    try {
      await _player.stop();
      position = Duration.zero;
      notifyListeners();
    } catch (e) {
      _log('⚠️ Stop error: $e');
    }
  }

  Future<void> seek(Duration pos) async {
    _log('🔍 seek → $pos');
    try {
      await _player.seek(pos);
      position = pos;
      notifyListeners();
    } catch (e) {
      _log('⚠️ Seek error: $e');
    }
  }

  // ── Core load + play ──────────────────────────────────────────────────────

  Future<void> _loadAndPlay() async {
    if (_isLoadingSource) {
      _log('⏳ _loadAndPlay already in progress — ignoring duplicate call');
      return;
    }
    if (currentSurah == null) {
      _log('⚠️ _loadAndPlay — no currentSurah');
      return;
    }

    _isLoadingSource = true;
    _log('🔃 _loadAndPlay starting for: ${currentSurah!.nameEn}');

    try {
      AudioSource source;

      if (downloadService != null) {
        _log('📡 Calling getAudioSource...');
        source = await downloadService!.getAudioSource(currentSurah!);
        _log('✅ getAudioSource returned: ${source.runtimeType}');
      } else {
        final assetPath = 'assets/audios/${currentSurah!.audioAsset}';
        _log('📦 Using asset fallback: $assetPath');
        source = AudioSource.asset(assetPath);
      }

      _log('⚙️ Calling _player.setAudioSource...');
      await _player.setAudioSource(source);
      _log('✅ setAudioSource complete — processingState=${_player.processingState.name}  duration=${_player.duration}');

      _log('▶️ Calling _player.play()...');
      await _player.play();
      _log('✅ _player.play() returned — playing=${_player.playing}');
    } catch (e, st) {
      _log('❌ _loadAndPlay ERROR: $e');
      _log('   StackTrace: $st');
      isLoading = false;
      isPlaying = false;
      notifyListeners();
    } finally {
      _isLoadingSource = false;
      _log('🔓 _isLoadingSource released');
    }
  }

  bool get canPlay => !_isLoadingSource;

  // ── Azan ──────────────────────────────────────────────────────────────────

  static Future<void> playAzan({String prayerName = 'Azan'}) async {
    try {
      await AzanForegroundService.startForegroundAzan(prayerName: prayerName);
    } catch (e, st) {
      debugPrint('[AudioService] ❌ playAzan: $e\n$st');
    }
  }

  static Future<void> stopAzan() async {
    try {
      await AzanForegroundService.stopForegroundAzan();
    } catch (e, st) {
      debugPrint('[AudioService] ⚠️ stopAzan: $e\n$st');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _log('🗑 AudioService disposing...');
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}