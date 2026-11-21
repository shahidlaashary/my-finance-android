import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_finance/features/space/screens/youtube_video_player_screen.dart';
import 'package:my_finance/features/space/services/my_space_service.dart';

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
    super.dispose();
  }

  String? _videoId(String input) {
    final value = input.trim();
    final patterns = [
      RegExp(r'youtu\\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\\.com/shorts/([a-zA-Z0-9_-]{11})'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      if (match != null) return match.group(1);
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(value)) return value;
    return null;
  }

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
        padding: const EdgeInsets.all(16),
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

  Widget _exploreTab() => ListView(padding: const EdgeInsets.all(20), children: [
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.video_collection_outlined, size: 34, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text('Explore Videos', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('Play YouTube videos in the app and keep the ones you like in your personal library.'),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _addVideo, icon: const Icon(Icons.link_rounded), label: const Text('Add YouTube video link'))),
      ]),
    ),
    const SizedBox(height: 18),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('YouTube search setup', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Video and channel search will be enabled after the YouTube Data API key is configured. You can already save links and play videos here.'),
    ]))),
    const SizedBox(height: 12),
    Text('Your library', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    SizedBox(height: 210, child: _videoList(_saved, history: false)),
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
