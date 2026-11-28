import 'package:flutter/material.dart';
import 'package:my_finance/modules/studio/application/services/studio_audio_match_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_visual_match_service.dart';
import 'package:my_finance/modules/studio/presentation/studio_audio_match_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_visual_match_screen.dart';

/// Unified Content ID hub: audio and visual matching tools live under one entry.
class StudioContentIdScreen extends StatefulWidget {
  const StudioContentIdScreen({super.key, this.initialSection});
  final String? initialSection;

  @override
  State<StudioContentIdScreen> createState() => _StudioContentIdScreenState();
}

class _StudioContentIdScreenState extends State<StudioContentIdScreen> {
  late Future<List<Map<String, Object?>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<Map<String, Object?>>> _loadHistory() async {
    final results = await Future.wait([
      StudioAudioMatchService().comparisonHistory(),
      StudioVisualMatchService().history(),
    ]);
    final rows = <Map<String, Object?>>[
      ...results[0].map((row) => <String, Object?>{...row, 'match_type': 'Audio Match'}),
      ...results[1].map((row) => <String, Object?>{...row, 'match_type': 'Visual Match'}),
    ];
    rows.sort((a, b) {
      final first = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final second = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return second.compareTo(first);
    });
    return rows.take(30).toList();
  }

  Future<void> _refreshHistory() async {
    final next = _loadHistory();
    setState(() => _historyFuture = next);
    await next;
  }

  void _open(BuildContext context, String option) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      option == 'Visual Match' ? const StudioVisualMatchScreen() :
      StudioAudioMatchScreen(section: option == 'Compare' ? 'Compare' : 'Audio Match')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Content ID'),
        actions: [
          IconButton(
            tooltip: 'Refresh comparison history',
            onPressed: _refreshHistory,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshHistory,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF152F44), Color(0xFF28777C)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.fingerprint_rounded, size: 34, color: Colors.white),
                  const SizedBox(height: 12),
                  Text('CONTENT IDENTIFICATION', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1.4)),
                  const SizedBox(height: 6),
                  Text('Find matches for your work', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text('Explore audio and visual similarity in your Studio media collection.', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _MatchToolCard(title: 'Audio Match', description: 'Identify audio fingerprints and search for similar audio across your media library.', icon: Icons.graphic_eq_rounded, accent: const Color(0xFF8758B7), onTap: () => _open(context, 'Audio Match')),
            const SizedBox(height: 12),
            _MatchToolCard(title: 'Visual Match', description: 'Compare video frame fingerprints and explore visual similarities between clips.', icon: Icons.video_camera_back_outlined, accent: const Color(0xFF21867D), onTap: () => _open(context, 'Visual Match')),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _open(context, 'Compare'), icon: const Icon(Icons.compare_arrows_rounded), label: const Text('Compare audio files')),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Text('Shared comparison history', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                TextButton(onPressed: _refreshHistory, child: const Text('Refresh')),
              ],
            ),
            Text('Recent results from both matching tools', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            _historyList(),
          ],
        ),
      ),
    );
  }

  Widget _historyList() => FutureBuilder<List<Map<String, Object?>>>(
    future: _historyFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.error_outline_rounded),
            title: const Text('History could not be loaded'),
            subtitle: Text(snapshot.error.toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: IconButton(onPressed: _refreshHistory, icon: const Icon(Icons.refresh_rounded)),
          ),
        );
      }
      final rows = snapshot.data ?? const <Map<String, Object?>>[];
      if (rows.isEmpty) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 30, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 8),
                const Text('No comparisons yet'),
                const SizedBox(height: 4),
                Text('Your Audio Match and Visual Match results will appear here.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
      }
      return Column(
        children: rows.map((row) {
          final isAudio = row['match_type'] == 'Audio Match';
          final score = (row['match_score'] as num?)?.toDouble() ?? 0;
          final left = row['left_name']?.toString() ?? 'Unknown media';
          final right = row['right_name']?.toString() ?? 'Unknown media';
          final date = DateTime.tryParse(row['created_at']?.toString() ?? '');
          final dateLabel = date == null ? '' : date.toLocal().toString().split('.').first;
          return Card(
            margin: const EdgeInsets.only(bottom: 7),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                child: Icon(isAudio ? Icons.graphic_eq_rounded : Icons.video_camera_back_outlined),
              ),
              title: Text('$left  vs  $right', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${row['match_type']} • ${(score * 100).toStringAsFixed(1)}% confidence${dateLabel.isEmpty ? '' : ' • $dateLabel'}'),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          );
        }).toList(),
      );
    },
  );
}

class _MatchToolCard extends StatelessWidget {
  const _MatchToolCard({required this.title, required this.description, required this.icon, required this.accent, required this.onTap});
  final String title, description;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: accent, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ])),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}
