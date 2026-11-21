import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class YouTubeVideoPlayerScreen extends StatefulWidget {
  const YouTubeVideoPlayerScreen({super.key, required this.videoId, required this.title});
  final String videoId;
  final String title;

  @override
  State<YouTubeVideoPlayerScreen> createState() => _YouTubeVideoPlayerScreenState();
}

class _YouTubeVideoPlayerScreenState extends State<YouTubeVideoPlayerScreen> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: ListView(
      children: [
        YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Playback is provided by the official YouTube player.'),
        ),
      ],
    ),
  );
}
