import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/features/library/services/my_library_service.dart';

class SpaceAudioPlayerScreen extends StatefulWidget {
  final Map<String, Object?> item;
  const SpaceAudioPlayerScreen({super.key, required this.item});

  @override
  State<SpaceAudioPlayerScreen> createState() => _SpaceAudioPlayerScreenState();
}

class _SpaceAudioPlayerScreenState extends State<SpaceAudioPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _loading = true;
  bool _seeking = false;
  int _lastSavedSecond = -1;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _position = Duration.zero;
        _completed = true;
      });
      _saveProgress(Duration.zero);
    });
    _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _player.onPositionChanged.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
      if (!_seeking && (value.inSeconds - _lastSavedSecond).abs() >= 5) {
        _lastSavedSecond = value.inSeconds;
        _saveProgress(value);
      }
    });
  }

  Future<void> _prepare() async {
    try {
      final path = widget.item['file_path'] as String;
      if (!await File(path).exists()) throw Exception('Audio file is missing.');
      final lowerPath = path.toLowerCase();
      if (lowerPath.endsWith('.aac') || lowerPath.endsWith('.ogg')) {
        throw const FormatException('AAC and OGG audio formats are no longer supported.');
      }
      await _player.setSourceDeviceFile(path);
      final savedMs = (widget.item['last_position_ms'] as int?) ?? 0;
      if (savedMs > 0) await _player.seek(Duration(milliseconds: savedMs));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to play audio: $e')));
      }
    }
  }

  Future<void> _saveProgress(Duration value) async {
    final id = widget.item['id'] as int?;
    if (id != null) {
      try {
        await MySpaceService.instance.saveAudioPosition(id, value);
      } catch (_) {
        // Playback continues even if progress cannot be persisted.
      }
    }
  }

  String _time(Duration value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    return hours > 0 ? '${two(hours)}:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
  }

  @override
  void dispose() {
    _saveProgress(_position);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item['title'] as String? ?? 'Audio';
    final colors = Theme.of(context).colorScheme;
    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    final currentMs = _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('Music Player')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [colors.primary, colors.tertiary]),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(Icons.graphic_eq_rounded, size: 96, color: colors.onPrimary),
            ),
            const SizedBox(height: 28),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(widget.item['file_name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant)),
            const SizedBox(height: 30),
            Slider(
              value: currentMs,
              max: maxMs,
              onChangeStart: (_) => _seeking = true,
              onChanged: (value) => setState(() => _position = Duration(milliseconds: value.round())),
              onChangeEnd: (value) async {
                await _player.seek(Duration(milliseconds: value.round()));
                _seeking = false;
                await _saveProgress(Duration(milliseconds: value.round()));
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(_time(_position)), Text(_time(_duration))],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const CircularProgressIndicator()
            else
              StreamBuilder<PlayerState>(
                stream: _player.onPlayerStateChanged,
                initialData: _player.state,
                builder: (context, snapshot) {
                  final playing = snapshot.data == PlayerState.playing;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        iconSize: 32,
                        onPressed: () => _player.seek(Duration(seconds: (_position.inSeconds - 10).clamp(0, _duration.inSeconds).toInt())),
                        icon: const Icon(Icons.replay_10_rounded),
                      ),
                      const SizedBox(width: 18),
                      IconButton.filled(
                        iconSize: 38,
                        onPressed: () async {
                          if (playing) {
                            await _player.pause();
                          } else {
                            if (_completed) {
                              await _player.seek(Duration.zero);
                              _completed = false;
                            }
                            await _player.resume();
                          }
                        },
                        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      ),
                      const SizedBox(width: 18),
                      IconButton.filledTonal(
                        iconSize: 32,
                        onPressed: () => _player.seek(Duration(seconds: (_position.inSeconds + 10).clamp(0, _duration.inSeconds).toInt())),
                        icon: const Icon(Icons.forward_10_rounded),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
