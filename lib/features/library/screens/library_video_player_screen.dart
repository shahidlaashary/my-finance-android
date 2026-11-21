import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LibraryVideoPlayerScreen extends StatefulWidget {
  const LibraryVideoPlayerScreen({super.key, required this.item});
  final Map<String, Object?> item;

  @override
  State<LibraryVideoPlayerScreen> createState() => _LibraryVideoPlayerScreenState();
}

class _LibraryVideoPlayerScreenState extends State<LibraryVideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _showControls = true;
  bool _muted = false;
  bool _fullscreen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.item['file_path'] as String))
      ..addListener(_videoChanged)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
      }).catchError((Object error) {
        if (mounted) setState(() => _error = 'Unable to play this video. This format or codec may not be supported on this device.');
      });
  }

  void _videoChanged() {
    if (mounted) setState(() {});
  }

  Duration _clampSeek(Duration target) {
    final duration = _controller.value.duration;
    if (target < Duration.zero) return Duration.zero;
    if (duration != Duration.zero && target > duration) return duration;
    return target;
  }

  Future<void> _seekBy(int seconds) async {
    if (!_ready) return;
    await _controller.seekTo(_clampSeek(_controller.value.position + Duration(seconds: seconds)));
  }

  String _time(Duration duration) {
    final seconds = duration.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    if (hours > 0) {
      return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}";
    }
    return "${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}";
  }

  Future<void> _toggleFullscreen() async {
    setState(() {
      _fullscreen = !_fullscreen;
      _showControls = true;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_videoChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _ready ? _controller.value : null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen ? null : AppBar(title: Text(widget.item['title'] as String)),
      body: Center(
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)))
            : !_ready
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () => setState(() => _showControls = !_showControls),
                    child: AspectRatio(
                      aspectRatio: value!.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(_controller),
                          if (_showControls)
                            Container(
                              color: Colors.black38,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (_fullscreen)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: IconButton(
                                        color: Colors.white,
                                        icon: const Icon(Icons.fullscreen_exit),
                                        onPressed: _toggleFullscreen,
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        iconSize: 40,
                                        color: Colors.white,
                                        onPressed: () => _seekBy(-10),
                                        icon: const Icon(Icons.replay_10),
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        iconSize: 42,
                                        color: Colors.white,
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                          overlayColor: Colors.white24,
                                        ),
                                        onPressed: () => _controller.value.isPlaying ? _controller.pause() : _controller.play(),
                                        icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        iconSize: 40,
                                        color: Colors.white,
                                        onPressed: () => _seekBy(10),
                                        icon: const Icon(Icons.forward_10),
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        Text(_time(value.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                        Expanded(
                                          child: VideoProgressIndicator(
                                            _controller,
                                            allowScrubbing: true,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                            colors: const VideoProgressColors(playedColor: Colors.redAccent, bufferedColor: Colors.white38, backgroundColor: Colors.white24),
                                          ),
                                        ),
                                        Text(_time(value.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                        IconButton(
                                          color: Colors.white,
                                          tooltip: _muted ? 'Unmute' : 'Mute',
                                          icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
                                          onPressed: () {
                                            setState(() => _muted = !_muted);
                                            _controller.setVolume(_muted ? 0 : 1);
                                          },
                                        ),
                                        PopupMenuButton<double>(
                                          initialValue: 1,
                                          tooltip: 'Playback speed',
                                          color: Colors.white,
                                          icon: const Icon(Icons.speed, color: Colors.white),
                                          onSelected: (speed) => _controller.setPlaybackSpeed(speed),
                                          itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) => PopupMenuItem(value: speed, child: Text('${speed}x'))).toList(),
                                        ),
                                        IconButton(
                                          color: Colors.white,
                                          tooltip: _fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                                          icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                                          onPressed: _toggleFullscreen,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
