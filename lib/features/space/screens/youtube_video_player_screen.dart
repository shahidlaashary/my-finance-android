import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_finance/features/space/services/my_space_service.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

const String _youtubeApiKey = String.fromEnvironment('YOUTUBE_API_KEY');

// Keep recommendations available when users move between videos in one app session.
final Map<String, List<Map<String, dynamic>>> _relatedVideoCache = {};

class YouTubeVideoPlayerScreen extends StatefulWidget {
  const YouTubeVideoPlayerScreen({super.key, required this.videoId, required this.title});
  final String videoId;
  final String title;

  @override
  State<YouTubeVideoPlayerScreen> createState() => _YouTubeVideoPlayerScreenState();
}

class _YouTubeVideoPlayerScreenState extends State<YouTubeVideoPlayerScreen> {
  late final YoutubePlayerController _controller;
  bool _loadingRelated = true;
  String? _relatedError;
  List<Map<String, dynamic>> _relatedVideos = [];

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        origin: 'https://www.youtube-nocookie.com',
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
      ),
    );
    _loadRelatedVideos();
  }

  Future<void> _loadRelatedVideos() async {
    final cacheKey = widget.title.trim().toLowerCase();
    final cached = _relatedVideoCache[cacheKey];
    if (cached != null) {
      if (mounted) setState(() { _relatedVideos = cached; _loadingRelated = false; _relatedError = null; });
      return;
    }
    if (_youtubeApiKey.isEmpty) {
      if (mounted) setState(() {
        _loadingRelated = false;
        _relatedError = 'YouTube API key is missing in this APK build.';
      });
      return;
    }

    final client = HttpClient();
    try {
      final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
        'part': 'snippet',
        'q': widget.title.trim().split(RegExp(r'\\s+')).take(7).join(' '),
        'type': 'video',
        'order': 'relevance',
        'maxResults': '6',
        'fields': 'items(id/videoId,snippet(title,channelTitle,thumbnails(default,medium)))',
        'regionCode': 'PK',
        'key': _youtubeApiKey,
      });
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['error']?['message'] ?? 'Could not load related videos');
      }
      final items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      final filtered = items.where((item) {
        final id = (item['id'] as Map<String, dynamic>?)?['videoId']?.toString();
        return id != null && id != widget.videoId;
      }).toList();
      _relatedVideoCache[cacheKey] = filtered;
      if (mounted) setState(() {
        _relatedVideos = filtered;
        _loadingRelated = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _relatedError = error is SocketException || error is HttpException || error is TimeoutException
            ? 'Connection is taking too long. Tap to retry.'
            : error.toString().replaceFirst('Exception: ', '');
        _loadingRelated = false;
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openRelatedVideo(Map<String, dynamic> item) async {
    final id = (item['id'] as Map<String, dynamic>?)?['videoId']?.toString();
    if (id == null) return;
    final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
    await MySpaceService.instance.markYouTubeVideoWatched(id);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => YouTubeVideoPlayerScreen(
        videoId: id,
        title: snippet['title']?.toString() ?? 'YouTube video',
      ),
    ));
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  Widget _relatedSection() {
    if (_loadingRelated) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_relatedError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_relatedError!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: () { setState(() { _loadingRelated = true; _relatedError = null; }); _loadRelatedVideos(); }, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      );
    }
    if (_relatedVideos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No related videos found.'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _relatedVideos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _relatedVideos[index];
        final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
        final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
        final thumbnail = (thumbnails['medium']?['url'] ?? thumbnails['default']?['url'])?.toString();
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumbnail == null
                  ? const SizedBox(width: 104, height: 64, child: Icon(Icons.play_circle_outline))
                  : Image.network(
                      thumbnail,
                      width: 104,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 104, height: 64, child: Icon(Icons.play_circle_outline)),
                    ),
            ),
            title: Text(snippet['title']?.toString() ?? 'YouTube video', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(snippet['channelTitle']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () => _openRelatedVideo(item),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => YoutubePlayerScaffold(
    controller: _controller,
    aspectRatio: 16 / 9,
    builder: (context, player) => Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        children: [
          player,
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Related videos', style: Theme.of(context).textTheme.titleMedium),
          ),
          _relatedSection(),
        ],
      ),
    ),
  );
}
