import 'dart:ui';
import 'package:flutter/material.dart';
// import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/surah.dart';
import '../services/audio_service.dart';

class PlayerScreen extends StatefulWidget {
  final Surah surah;
  const PlayerScreen({required this.surah, super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late AudioService audio;
  late AnimationController _anim;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    audio = Provider.of<AudioService>(context, listen: false);
    audio.setSurahAndPlay(widget.surah);

    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  Future<void> _handlePlayPause(AudioService audioService, bool isPlaying) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      if (isPlaying) {
        await audioService.pause();
      } else {
        await audioService.play();
      }
      await Future.delayed(const Duration(milliseconds: 200));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioService>(
      builder: (context, a, _) {
        final maxSec =
            a.duration.inSeconds > 0 ? a.duration.inSeconds.toDouble() : 1.0;
        final posSec =
            a.position.inSeconds.toDouble().clamp(0.0, maxSec);

        final playing =
            a.isPlaying && a.currentSurah?.number == widget.surah.number;

        // Show buffering indicator when just_audio is loading/buffering
        final isBuffering = a.isLoading;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: const Color.fromARGB(255, 14, 76, 61),
            foregroundColor: const Color.fromARGB(255, 14, 76, 61),
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
            ),
            title: Text(
              widget.surah.nameEn,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          body: Stack(
            children: [
              // Background image
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(top: kToolbarHeight + 30),
                  child: Image.asset(
                    'assets/images/player_bg.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),

              // UI Content
              Column(
                children: [
                  const Spacer(),

                  // Arabic name
                  Text(
                    widget.surah.nameAr,
                    style: TextStyle(
                      fontSize: 34,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.7),
                          blurRadius: 6,
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // English name
                  Text(
                    widget.surah.nameEn,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 4,
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Buffering indicator (shows while loading/streaming)
                  if (isBuffering)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Buffering...',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                  // Seek slider
                  Slider(
                    min: 0,
                    max: maxSec,
                    value: posSec,
                    activeColor: const Color.fromARGB(255, 14, 76, 61),
                    inactiveColor: Colors.white54,
                    onChanged: (v) => a.seek(Duration(seconds: v.toInt())),
                  ),

                  // Time labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_format(a.position),
                            style: const TextStyle(color: Colors.white)),
                        Text(_format(a.duration),
                            style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 36,
                        color: Colors.white,
                        icon: const Icon(Icons.replay_10),
                        onPressed: () {
                          final sec = (a.position.inSeconds - 10)
                              .clamp(0, a.duration.inSeconds);
                          a.seek(Duration(seconds: sec));
                        },
                      ),
                      const SizedBox(width: 22),

                      // Play/Pause FAB
                      FloatingActionButton(
                        backgroundColor: (_isProcessing || isBuffering)
                            ? Colors.teal.shade700.withValues(alpha: 0.7)
                            : Colors.teal.shade700,
                        onPressed: (_isProcessing || isBuffering)
                            ? null
                            : () => _handlePlayPause(a, playing),
                        child: (_isProcessing || isBuffering)
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                                size: 36,
                                color: Colors.white,
                              ),
                      ),

                      const SizedBox(width: 22),
                      IconButton(
                        iconSize: 36,
                        color: Colors.white,
                        icon: const Icon(Icons.forward_10),
                        onPressed: () {
                          final sec = (a.position.inSeconds + 10)
                              .clamp(0, a.duration.inSeconds);
                          a.seek(Duration(seconds: sec));
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'Al Quran MP3 App',
                    style: TextStyle(
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}