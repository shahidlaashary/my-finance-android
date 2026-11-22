import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_finance/features/space/screens/youtube_video_player_screen.dart';
import 'package:my_finance/features/space/services/my_space_service.dart';
import 'package:url_launcher/url_launcher.dart';

const String _youtubeApiKey = String.fromEnvironment('YOUTUBE_API_KEY');

class YouTubeExploreScreen extends StatefulWidget {
  const YouTubeExploreScreen({super.key});

  @override
  State<YouTubeExploreScreen> createState() => _YouTubeExploreScreenState();
}

class _YouTubeExploreScreenState extends State<YouTubeExploreScreen> with SingleTickerProviderStateMixin {
  final _space = MySpaceService.instance;
  final _linkController = TextEditingController();
  final _titleController = TextEditingController();
  late final TabController _tabs;
  late Future<List<Map<String, Object?>>> _saved;
  late Future<List<Map<String, Object?>>> _history;
  bool _saving = false;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  String _searchType = 'video';
  bool _searching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _refresh();
  }

  void _refresh() {
    _saved = _space.getYouTubeVideos();
    _history = _space.getYouTubeVideos(history: true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _linkController.dispose();
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String? _videoId(String input) {
    final value = input.trim();
    final patterns = [
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      if (match != null) return match.group(1);
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(value)) return value;
    return null;
  }


  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    if (_youtubeApiKey.isEmpty) {
      setState(() => _searchError = 'API key is missing in this APK build.');
      return;
    }
    setState(() { _searching = true; _searchError = null; _results = []; });
    final client = HttpClient();
    try {
      final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
        'part': 'snippet', 'q': q, 'type': _searchType, 'maxResults': '20', 'key': _youtubeApiKey,
      });
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception(json['error']?['message'] ?? 'Search request failed');
      if (mounted) setState(() => _results = (json['items'] as List? ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _searchError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _saveSearchResult(Map<String, dynamic> item) async {
    final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
    final videoId = (item['id'] as Map<String, dynamic>?)?['videoId']?.toString();
    if (videoId == null) return;
    final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
    await _space.saveYouTubeVideo(videoId: videoId, title: snippet['title']?.toString() ?? 'Video',
      channelTitle: snippet['channelTitle']?.toString(),
      thumbnailUrl: (thumbnails['high']?['url'] ?? thumbnails['medium']?['url'])?.toString());
    if (mounted) { setState(_refresh); _message('Saved to My Space.'); }
  }

  Future<void> _openSearchResult(Map<String, dynamic> item) async {
    final id = (item['id'] as Map<String, dynamic>?)?['videoId']?.toString();
    if (_searchType == 'channel') {
      final channelId = (item['id'] as Map<String, dynamic>?)?['channelId']?.toString();
      if (channelId != null) await launchUrl(Uri.parse('https://www.youtube.com/channel/' + channelId), mode: LaunchMode.externalApplication);
      return;
    }
    if (id == null) return;
    final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
    await _space.markYouTubeVideoWatched(id);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => YouTubeVideoPlayerScreen(videoId: id, title: snippet['title']?.toString() ?? 'Video')));
    if (mounted) setState(_refresh);
  }

  Widget _searchResults() {
    if (_searching) return const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()));
    if (_searchError != null) return Padding(padding: const EdgeInsets.all(12), child: Text(_searchError!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
    if (_results.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _results[index];
        final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
        final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
        final thumb = (thumbs['high']?['url'] ?? thumbs['medium']?['url'] ?? thumbs['default']?['url'])?.toString();
        final isVideo = _searchType == 'video';
        return Card(child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: thumb == null
            ? _thumbPlaceholder()
            : Image.network(thumb, width: 86, height: 54, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _thumbPlaceholder()),
          ),
          title: Text(snippet['title']?.toString() ?? 'Untitled', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(snippet['channelTitle']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _openSearchResult(item),
          trailing: isVideo ? IconButton(icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Save video', onPressed: () => _saveSearchResult(item)) : const Icon(Icons.open_in_new_rounded),
        ));
      },
    );
  }

  Widget _thumbPlaceholder() => Container(width: 86, height: 54, color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Icon(Icons.play_circle_outline_rounded, color: Theme.of(context).colorScheme.primary));

  Future<void> _addVideo() async {
    _linkController.clear();
    _titleController.clear();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Save a video', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(controller: _linkController, decoration: const InputDecoration(labelText: 'YouTube video link or ID', hintText: 'Paste a YouTube link', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Video title (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save to My Space'))),
        ]),
      ),
    );
    if (accepted != true) return;
    final id = _videoId(_linkController.text);
    if (id == null) {
      _message('Enter a valid YouTube video link or 11-character video ID.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _space.saveYouTubeVideo(videoId: id, title: _titleController.text.trim().isEmpty ? 'YouTube video' : _titleController.text.trim());
      if (mounted) setState(_refresh);
      _message('Video saved to My Space.');
    } catch (e) {
      _message('Could not save video: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _play(Map<String, Object?> video) async {
    final id = video['video_id'] as String;
    await _space.markYouTubeVideoWatched(id);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => YouTubeVideoPlayerScreen(videoId: id, title: video['title'] as String)));
    if (mounted) setState(_refresh);
  }

  Future<void> _remove(String id) async {
    await _space.removeYouTubeVideo(id);
    if (mounted) setState(_refresh);
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Widget _videoList(Future<List<Map<String, Object?>>> future, {required bool history}) {
    return FutureBuilder<List<Map<String, Object?>>>(future: future, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text('Unable to load videos: ${snapshot.error}'));
      final videos = snapshot.data ?? [];
      if (videos.isEmpty) return Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(history ? Icons.history_rounded : Icons.bookmark_border_rounded, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(history ? 'No watch history yet' : 'No saved videos yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(history ? 'Videos you play from your library will appear here.' : 'Save YouTube links to keep them organized in My Space.', textAlign: TextAlign.center),
          if (!history) TextButton.icon(onPressed: _addVideo, icon: const Icon(Icons.add), label: const Text('Save a video')),
        ]),
      ));
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final video = videos[index];
          final id = video['video_id'] as String;
          return Card(child: ListTile(
            onTap: () => _play(video),
            leading: Container(width: 52, height: 52, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.play_circle_outline_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 30)),
            title: Text(video['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('YouTube • ${history ? 'Recently watched' : 'Saved in My Space'}'),
            trailing: history ? const Icon(Icons.play_arrow_rounded) : PopupMenuButton<String>(
              onSelected: (value) { if (value == 'remove') _remove(id); if (value == 'copy') Clipboard.setData(ClipboardData(text: 'https://youtu.be/$id')); },
              itemBuilder: (_) => const [PopupMenuItem(value: 'copy', child: Text('Copy link')), PopupMenuItem(value: 'remove', child: Text('Remove from saved'))],
            ),
          ));
        },
      );
    });
  }

  Widget _exploreTab() => ListView(padding: const EdgeInsets.all(16), children: [
    Text('Find videos and channels', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    Wrap(spacing: 8, children: [
      ChoiceChip(label: const Text('Videos'), selected: _searchType == 'video', onSelected: (_) => setState(() => _searchType = 'video')),
      ChoiceChip(label: const Text('Channels'), selected: _searchType == 'channel', onSelected: (_) => setState(() => _searchType = 'channel')),
    ]),
    const SizedBox(height: 10),
    TextField(controller: _searchController, textInputAction: TextInputAction.search, onSubmitted: (_) => _search(),
      decoration: InputDecoration(hintText: 'Search ' + (_searchType == 'video' ? 'videos' : 'channels'), prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(onPressed: _searching ? null : _search, icon: const Icon(Icons.arrow_forward_rounded)), border: const OutlineInputBorder())),
    const SizedBox(height: 12),
    Text('Search results', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    _searchResults(),
    if (_results.isEmpty && !_searching && _searchError == null)
      Padding(padding: const EdgeInsets.symmetric(vertical: 28), child: Column(children: [
        Icon(Icons.video_library_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8), const Text('Search videos or channels, or save a link.'),
      ])),
    const SizedBox(height: 20),
    Card(child: ListTile(leading: const Icon(Icons.link_rounded), title: const Text('Save by link'), subtitle: const Text('Add using video link or ID'), trailing: const Icon(Icons.chevron_right), onTap: _saving ? null : _addVideo)),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Explore Videos'),
      bottom: TabBar(controller: _tabs, tabs: const [
        Tab(text: 'Explore', icon: Icon(Icons.explore_outlined)),
        Tab(text: 'Saved', icon: Icon(Icons.bookmark_border_rounded)),
        Tab(text: 'History', icon: Icon(Icons.history_rounded)),
      ]),
    ),
    floatingActionButton: FloatingActionButton.extended(onPressed: _saving ? null : _addVideo, icon: const Icon(Icons.add_link_rounded), label: const Text('Save video')),
    body: TabBarView(controller: _tabs, children: [
      _exploreTab(),
      _videoList(_saved, history: false),
      _videoList(_history, history: true),
    ]),
  );
}
