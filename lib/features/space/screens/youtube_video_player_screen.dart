import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class YouTubeVideoPlayerScreen extends StatefulWidget {
  const YouTubeVideoPlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
  });

  final String videoId;
  final String title;

  @override
  State<YouTubeVideoPlayerScreen> createState() =>
      _YouTubeVideoPlayerScreenState();
}

class _YouTubeVideoPlayerScreenState
    extends State<YouTubeVideoPlayerScreen> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        origin: 'https://www.youtube-nocookie.com',
        showControls: true,
        showFullscreenButton: true,
        // YouTube only supports limiting end-screen suggestions to the
        // same channel; its own player UI and attribution remain visible.
        strictRelatedVideos: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YoutubePlayerScaffold(
        controller: _controller,
        aspectRatio: 16 / 9,
        builder: (context, player) => Scaffold(
          backgroundColor: const Color(0xFF090909),
          appBar: AppBar(
            backgroundColor: const Color(0xFF090909),
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text(
              'Now Playing',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Official YouTube IFrame player. Its required YouTube
              // branding, attribution and playback controls are retained.
              player,
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
                child: Text(
                  widget.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Icon(
                      Icons.smart_display_rounded,
                      color: Color(0xFFFF0033),
                      size: 18,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Playing from YouTube',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
