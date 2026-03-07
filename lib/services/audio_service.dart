import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/surah.dart';
import 'azan_foreground_service.dart';
import 'audio_download_service.dart';
import '../screens/debug_log_screen.dart';

class AudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final AudioDownloadService? downloadService;

  Surah? currentSurah;
  bool isPlaying = false;
  bool isLoading = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;

  // True while we're using an estimated duration (not yet confirmed by AVPlayer)
  bool isDurationEstimated = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _isLoadingSource = false;

  static void _log(String msg) => AppLogger.log('[AudioService] $msg');

  AudioService({this.downloadService}) {
    _log('created');
    _initAudioSession();
    _setupListeners();
  }

  Future<void> _initAudioSession() async {
    try {
      _log('configuring AVAudioSession...');
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
      _log('✅ AVAudioSession configured: playback category');
    } catch (e) {
      _log('⚠️ AVAudioSession failed (non-critical): $e');
    }
  }

  void _setupListeners() {
    _posSub = _player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });

    _durSub = _player.durationStream.listen((d) {
      _log('durationStream: $d');
      if (d != null && d > Duration.zero) {
        // AVPlayer now knows the real duration — replace our estimate
        if (isDurationEstimated) {
          _log('✅ replacing estimated duration ($duration) with real duration ($d)');
          isDurationEstimated = false;
        }
        duration = d;
        notifyListeners();
      }
    });

    _stateSub = _player.playerStateStream.listen((state) {
      final ps = state.processingState;
      _log('playerState → playing=${state.playing}  ps=${ps.name}');

      final loading =
          ps == ProcessingState.loading || ps == ProcessingState.buffering;
      final nowPlaying = state.playing && ps != ProcessingState.completed;
      final completed = ps == ProcessingState.completed;

      bool changed = false;
      if (isLoading != loading) { isLoading = loading; changed = true; }
      if (isPlaying != nowPlaying) { isPlaying = nowPlaying; changed = true; }
      if (completed) { position = duration; changed = true; }
      if (changed) notifyListeners();
    });

    _log('✅ listeners set up');
  }

  Future<void> setSurahAndPlay(Surah s, {bool autoplay = true}) async {
    _log('setSurahAndPlay: ${s.nameEn}  autoplay=$autoplay');

    if (currentSurah?.number == s.number) {
      _log('same surah already loaded');
      if (autoplay && !_player.playing) await play();
      return;
    }

    try { await _player.stop(); } catch (e) { _log('stop error (ignored): $e'); }

    currentSurah = s;
    position = Duration.zero;
    duration = Duration.zero;
    isDurationEstimated = false;
    notifyListeners();

    if (autoplay) await _loadAndPlay();
  }

  Future<void> play() async {
    _log('play() — surah=${currentSurah?.nameEn}  ps=${_player.processingState.name}');
    if (currentSurah == null) { _log('⚠️ no surah'); return; }
    if (_player.playing) { _log('already playing'); return; }
    if (_player.processingState == ProcessingState.ready) {
      _log('resuming from ready state');
      await _player.play();
      return;
    }
    await _loadAndPlay();
  }

  Future<void> pause() async {
    _log('pause()');
    try { await _player.pause(); } catch (e) { _log('❌ pause error: $e'); }
  }

  Future<void> stop() async {
    _log('stop()');
    try {
      await _player.stop();
      position = Duration.zero;
      notifyListeners();
    } catch (e) { _log('⚠️ stop error: $e'); }
  }

  Future<void> seek(Duration pos) async {
    try {
      await _player.seek(pos);
      position = pos;
      notifyListeners();
    } catch (e) { _log('⚠️ seek error: $e'); }
  }

  Future<void> _loadAndPlay() async {
    if (_isLoadingSource) { _log('already loading — skip'); return; }
    if (currentSurah == null) return;

    _isLoadingSource = true;
    _log('_loadAndPlay START: ${currentSurah!.nameEn}');

    try {
      AudioSource source;

      if (downloadService != null) {
        _log('calling getAudioSource...');
        source = await downloadService!.getAudioSource(currentSurah!);
        _log('✅ getAudioSource → ${source.runtimeType}');

        // ── Seed estimated duration immediately ──────────────────────────
        // For progressive streams, AVPlayer won't know duration until the
        // full file is downloaded. We computed it from the MP3 header, so
        // show it right away so the UI displays "45:23" instead of "0:00".
        final estimated = downloadService!.estimatedDuration;
        if (estimated != null && estimated > Duration.zero) {
          duration = estimated;
          isDurationEstimated = true;
          final mm = estimated.inMinutes.toString().padLeft(2, '0');
          final ss = (estimated.inSeconds % 60).toString().padLeft(2, '0');
          _log('⏱ seeding estimated duration: $mm:$ss');
          notifyListeners();
        }
        // ────────────────────────────────────────────────────────────────
      } else {
        final p = 'assets/audios/${currentSurah!.audioAsset}';
        _log('asset fallback: $p');
        source = AudioSource.asset(p);
      }

      _log('calling setAudioSource...');
      await _player.setAudioSource(source);
      _log('✅ setAudioSource done — ps=${_player.processingState.name}  dur=${_player.duration}');

      // If AVPlayer already reported a real duration, use it and clear estimate
      if (_player.duration != null && _player.duration! > Duration.zero) {
        duration = _player.duration!;
        isDurationEstimated = false;
        _log('✅ AVPlayer duration available immediately: $duration');
        notifyListeners();
      }

      _log('calling _player.play()...');
      await _player.play();
      _log('✅ _player.play() returned — playing=${_player.playing}');
    } catch (e, st) {
      _log('❌ _loadAndPlay ERROR: $e');
      _log('   $st');
      isLoading = false;
      isPlaying = false;
      isDurationEstimated = false;
      notifyListeners();
    } finally {
      _isLoadingSource = false;
    }
  }

  bool get canPlay => !_isLoadingSource;

  static Future<void> playAzan({String prayerName = 'Azan'}) async {
    try {
      await AzanForegroundService.startForegroundAzan(prayerName: prayerName);
    } catch (e, st) { _log('❌ playAzan: $e\n$st'); }
  }

  static Future<void> stopAzan() async {
    try {
      await AzanForegroundService.stopForegroundAzan();
    } catch (e, st) { _log('⚠️ stopAzan: $e\n$st'); }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}