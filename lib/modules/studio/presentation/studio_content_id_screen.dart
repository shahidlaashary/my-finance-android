import 'dart:convert';

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
  String _historyFilter = 'All';

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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: ['All', 'Audio Match', 'Visual Match'].map((filter) =>
                FilterChip(
                  label: Text(filter),
                  selected: _historyFilter == filter,
                  onSelected: (_) => setState(() => _historyFilter = filter),
                ),
              ).toList(),
            ),
            const SizedBox(height: 8),
            _historyList(),
          ],
        ),
      ),
    );
  }

  void _showHistoryDetails(Map<String, Object?> row) {
    final isAudio = row['match_type'] == 'Audio Match';
    final rawResult = row['result_json']?.toString();
    Map<String, Object?> resultData = const {};
    if (rawResult != null && rawResult.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawResult);
        if (decoded is Map) {
          resultData = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } on FormatException {
        // Older or malformed result payloads should not block history details.
      }
    }
    String percent(Object? value) {
      final number = (value as num?)?.toDouble();
      return number == null ? 'Not recorded' : '${(number * 100).toStringAsFixed(1)}%';
    }
    final score = ((row['match_score'] as num?)?.toDouble() ?? 0) * 100;
    final date = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final dateLabel = date == null ? 'Not available' : date.toLocal().toString();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(isAudio ? Icons.graphic_eq_rounded : Icons.video_camera_back_outlined),
                const SizedBox(width: 10),
                Text(row['match_type']?.toString() ?? 'Content ID', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 16),
              Text('${row['left_name'] ?? 'Unknown media'}  vs  ${row['right_name'] ?? 'Unknown media'}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              _detailRow(context, 'Confidence', '${score.toStringAsFixed(1)}%'),
              if (isAudio) ...[
                _detailRow(context, 'Query coverage', percent(resultData['queryCoverage'])),
                _detailRow(context, 'Reference coverage', percent(resultData['referenceCoverage'])),
                _detailRow(context, 'Query landmarks', '${resultData['queryLandmarks'] ?? 'Not recorded'}'),
                _detailRow(context, 'Reference landmarks', '${resultData['referenceLandmarks'] ?? 'Not recorded'}'),
                _detailRow(context, 'Matched query timestamps', _timestampSummary(resultData['matchedQueryTimestampsMs'])),
                _detailRow(context, 'Matched reference timestamps', _timestampSummary(resultData['matchedReferenceTimestampsMs'])),
              ] else ...[
                _detailRow(context, 'Query frames', '${resultData['queryFrames'] ?? 'Not recorded'}'),
                _detailRow(context, 'Reference frames', '${resultData['referenceFrames'] ?? 'Not recorded'}'),
                _detailRow(context, 'Matched query timestamps', _timestampSummary(resultData['matchedQueryTimestampsMs'])),
                _detailRow(context, 'Matched reference timestamps', _timestampSummary(resultData['matchedReferenceTimestampsMs'])),
              ],
              _detailRow(context, isAudio ? 'Matched landmarks' : 'Matched frames', '${row['matched_landmarks'] ?? row['matched_frames'] ?? 'Not recorded'}'),
              _detailRow(context, 'Estimated offset', '${row['offset_ms'] ?? 'Not recorded'} ms'),
              _detailRow(context, 'Algorithm', '${row['algorithm_key'] ?? 'Not recorded'}'),
              _detailRow(context, 'Algorithm version', '${row['algorithm_version'] ?? 'Not recorded'}'),
              _detailRow(context, 'Compared at', dateLabel),
            ],
          ),
        ),
      ),
    );
  }

  String _timestampSummary(Object? value) {
    if (value is! List || value.isEmpty) return 'Not recorded';
    final values = value.take(6).map((item) {
      final ms = (item as num).toInt();
      final seconds = ms / 1000;
      return '${seconds.toStringAsFixed(1)}s';
    }).join(', ');
    return value.length > 6 ? '$values, … (${value.length} total)' : values;
  }

  Widget _detailRow(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
    ]),
  );

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
      final allRows = snapshot.data ?? const <Map<String, Object?>>[];
      final rows = _historyFilter == 'All'
          ? allRows
          : allRows.where((row) => row['match_type'] == _historyFilter).toList();
      if (rows.isEmpty) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 30, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(allRows.isEmpty ? 'No comparisons yet' : 'No ${_historyFilter.toLowerCase()} results yet'),
                const SizedBox(height: 4),
                Text(allRows.isEmpty ? 'Your Audio Match and Visual Match results will appear here.' : 'Choose another history filter to see saved comparisons.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
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
              onTap: () => _showHistoryDetails(row),
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
