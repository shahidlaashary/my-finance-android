import 'package:flutter/material.dart';

import '../application/services/studio_audio_match_service.dart';
import '../application/services/studio_processing_queue_service.dart';
import '../domain/entities/studio_media_file.dart';
import '../engines/audio_fingerprint/studio_audio_fingerprint_matcher.dart';

class StudioAudioMatchScreen extends StatefulWidget {
  const StudioAudioMatchScreen({super.key, required this.section});

  final String section;

  @override
  State<StudioAudioMatchScreen> createState() => _StudioAudioMatchScreenState();
}

class _StudioAudioMatchScreenState extends State<StudioAudioMatchScreen> {
  final _service = StudioAudioMatchService();
  List<StudioMediaFile> _files = [];
  List<StudioAudioCandidate> _candidates = [];
  List<Map<String, Object?>> _history = [];
  bool _loading = true;
  bool _processing = false;
  String? _scanSummary;
  String? _scanProgress;
  String? _error;
  String? _first;
  String? _second;
  StudioAudioFingerprintMatch? _result;

  bool get _isCompareMode => widget.section == 'Compare';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final files = await _service.audioFiles();
      final history = await _service.comparisonHistory();
      if (!mounted) return;
      files.sort((a, b) =>
          a.originalName.toLowerCase().compareTo(b.originalName.toLowerCase()));
      setState(() {
        _files = files;
        _history = history;
        _first = files.any((file) => file.id == _first)
            ? _first
            : (files.isNotEmpty ? files.first.id : null);
        _second = files.any((file) => file.id == _second)
            ? _second
            : (files.length > 1 ? files[1].id : null);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _identify(StudioMediaFile file) async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _scanProgress = 'Preparing fingerprint…';
      _scanSummary = null;
      _candidates = [];
      _error = null;
    });
    try {
      await StudioProcessingQueueService()
          .runFingerprintJob(mediaId: file.id, mediaType: 'audio');
      if (!mounted) return;
      setState(() => _scanProgress = 'Scanning local audio library…');
      final scan = await _service.scanMatches(file.id,
          onProgress: (completed, total) {
        if (!mounted) return;
        setState(() => _scanProgress = total == 0
            ? 'No other audio files to compare.'
            : 'Comparing $completed of $total files…');
      });
      if (!mounted) return;
      final summary =
          'Compared ${scan.comparedCount} files; skipped ${scan.skippedCount} unreadable or unsupported files.';
      setState(() {
        _candidates = scan.matches;
        _scanSummary = summary;
        _scanProgress = null;
      });
      _toast(scan.matches.isEmpty
          ? 'No matching candidates. $summary'
          : 'Scan completed. ${scan.matches.length} candidates. $summary');
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanProgress = null;
          _error = 'Audio Match failed: $error';
        });
        _toast('Audio Match failed: $error');
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _runComparison() async {
    if (_first == null || _second == null || _first == _second) {
      _toast('Select two different audio files.');
      return;
    }
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final result = await _service.compare(_first!, _second!);
      final history = await _service.comparisonHistory();
      if (!mounted) return;
      setState(() {
        _result = result;
        _history = history;
      });
    } catch (error) {
      _toast('Comparison failed: $error');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.section)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _files.isEmpty
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _isCompareMode ? _compareBody() : _musicBody(),
                ),
    );
  }

  Widget _errorState() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 90),
          Icon(Icons.error_outline_rounded,
              size: 42, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text('Studio Audio Match could not load',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(_error ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
              child: OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'))),
        ],
      );

  Widget _introCard({required IconData icon, required String title, required String description}) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                  const SizedBox(height: 4),
                  Text(description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.35,
                          )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _musicBody() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
        children: [
          _introCard(
            icon: Icons.graphic_eq_rounded,
            title: 'Audio identification',
            description:
                'Generate a fingerprint and search for similar audio in your local Studio library.',
          ),
          _sectionTitle(
            'Audio library',
            '${_files.length} managed audio ${_files.length == 1 ? 'file' : 'files'}',
          ),
          if (_files.isEmpty)
            _emptyCard(
              icon: Icons.library_music_outlined,
              title: 'Your audio library is empty',
              message: 'Import MP3, OGG or WAV files from Media Library to start identifying audio.',
            ),
          ..._files.map(_audioFileTile),
          if (_processing || _scanProgress != null)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(_scanProgress ?? 'Processing audio…',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          if (_scanSummary != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_scanSummary!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          if (_candidates.isNotEmpty) ...[
            _sectionTitle(
              'Candidate matches',
              '${_candidates.length} possible ${_candidates.length == 1 ? 'match' : 'matches'} found',
            ),
            ..._candidates.map(_candidateTile),
            _disclaimer(),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      );

  Widget _audioFileTile(StudioMediaFile file) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.audio_file_rounded,
              color: colors.onSecondaryContainer),
        ),
        title: Text(file.originalName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text((file.fileExtension ?? 'Audio').toUpperCase()),
        trailing: IconButton.filledTonal(
          tooltip: 'Identify in library',
          onPressed: _processing ? null : () => _identify(file),
          icon: const Icon(Icons.fingerprint_rounded),
        ),
      ),
    );
  }

  Widget _candidateTile(StudioAudioCandidate candidate) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        dense: true,
        leading: Icon(
          candidate.match.isMatch
              ? Icons.check_circle_outline_rounded
              : Icons.info_outline_rounded,
          color: candidate.match.isMatch ? colors.primary : colors.onSurfaceVariant,
        ),
        title: Text(candidate.media.originalName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Confidence: ${_pct(candidate.match.confidence)} • ${candidate.match.matchedLandmarks} landmarks',
        ),
      ),
    );
  }

  Widget _compareBody() {
    final choices = _files
        .map((file) => DropdownMenuItem<String>(
              value: file.id,
              child: Text(file.originalName, overflow: TextOverflow.ellipsis),
            ))
        .toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
      children: [
        _introCard(
          icon: Icons.compare_arrows_rounded,
          title: 'Audio comparison',
          description:
              'Compare two managed audio files using their generated fingerprints and review similarity signals.',
        ),
        _sectionTitle('Select audio files', 'Choose two different files'),
        if (_files.length < 2)
          _emptyCard(
            icon: Icons.library_add_outlined,
            title: 'More audio files needed',
            message: 'Import at least two audio files in Media Library before comparing.',
          ),
        DropdownButtonFormField<String>(
          value: _files.any((file) => file.id == _first) ? _first : null,
          items: choices,
          decoration: const InputDecoration(
            labelText: 'First audio file',
            prefixIcon: Icon(Icons.looks_one_outlined),
            border: OutlineInputBorder(),
          ),
          onChanged: _processing ? null : (value) => setState(() => _first = value),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _files.any((file) => file.id == _second) ? _second : null,
          items: choices,
          decoration: const InputDecoration(
            labelText: 'Second audio file',
            prefixIcon: Icon(Icons.looks_two_outlined),
            border: OutlineInputBorder(),
          ),
          onChanged: _processing ? null : (value) => setState(() => _second = value),
        ),
        const SizedBox(height: 13),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _processing || _files.length < 2 ? null : _runComparison,
            icon: const Icon(Icons.compare_arrows_rounded),
            label: Text(_processing ? 'Processing…' : 'Compare audio'),
          ),
        ),
        if (_processing)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_result != null) _audioComparisonResult(),
        if (_history.isNotEmpty) ...[
          _sectionTitle('Recent comparisons', 'Latest saved local comparisons'),
          ..._history.take(20).map(_historyTile),
        ],
      ],
    );
  }

  Widget _audioComparisonResult() {
    final result = _result!;
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.isMatch ? Icons.verified_outlined : Icons.insights_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    result.isMatch ? 'Potential audio match' : 'No strong match found',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            _resultMetric('Confidence', _pct(result.confidence)),
            _resultMetric('Matched landmarks',
                '${result.matchedLandmarks} / ${result.queryLandmarks}'),
            _resultMetric('Query coverage', _pct(result.queryCoverage)),
            _resultMetric('Reference coverage', _pct(result.referenceCoverage)),
            _resultMetric('Estimated offset', '${result.offsetMs} ms'),
            _resultMetric('Matched query timestamps', _timestampSummary(result.matchedQueryTimestampsMs)),
            _resultMetric('Matched reference timestamps', _timestampSummary(result.matchedReferenceTimestampsMs)),
            const SizedBox(height: 9),
            _disclaimer(),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(Map<String, Object?> item) {
    final score = ((item['match_score'] as num).toDouble() * 100)
        .toStringAsFixed(1);
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.history_rounded),
        title: Text('${item['left_name']} vs ${item['right_name']}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('Score: $score% • ${item['matched_landmarks']} landmarks'),
      ),
    );
  }

  String _timestampSummary(List<int> timestamps) {
    if (timestamps.isEmpty) return 'Not recorded';
    final visible = timestamps.take(5)
        .map((ms) => '${(ms / 1000).toStringAsFixed(1)}s')
        .join(', ');
    return timestamps.length > 5
        ? '$visible, … (${timestamps.length} total)'
        : visible;
  }

  Widget _resultMetric(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
            ),
            Text(value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
          ],
        ),
      );

  Widget _emptyCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, size: 32,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    )),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ],
        ),
      ),
    );
  }

  Widget _disclaimer() => Text(
        'Similarity results are candidate signals, not proof of ownership or infringement.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
}
