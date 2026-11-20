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
        if (mounted) setState(() => _error = 'Unable to play this video.');
      });
  }

  void _videoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_videoChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item['title'] as String)),
      backgroundColor: Colors.black,
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white))
            : !_ready
                ? const CircularProgressIndicator()
                : AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_controller),
                        VideoProgressIndicator(_controller, allowScrubbing: true),
                        Positioned(
                          bottom: 20,
                          child: IconButton.filled(
                            onPressed: () => setState(() {
                              _controller.value.isPlaying ? _controller.pause() : _controller.play();
                            }),
                            icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
