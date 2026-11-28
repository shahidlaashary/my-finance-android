import 'package:flutter/material.dart';
import 'package:my_finance/modules/studio/presentation/studio_music_id_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_video_id_screen.dart';

/// Unified Content ID hub: audio and visual matching tools live under one entry.
class StudioContentIdScreen extends StatelessWidget {
  const StudioContentIdScreen({super.key, this.initialSection});
  final String? initialSection;
  void _open(BuildContext context, String option) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      option == 'Visual Match' ? const StudioVideoIdScreen() :
      StudioMusicIdScreen(section: option == 'Compare' ? 'Compare' : 'Audio Match')));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Content ID')), body: ListView(padding: const EdgeInsets.all(18), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF152F44), Color(0xFF28777C)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.fingerprint_rounded, size: 34, color: Colors.white), const SizedBox(height: 12),
          Text('CONTENT IDENTIFICATION', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1.4)),
          const SizedBox(height: 6), Text('Find matches for your work', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8), const Text('Explore audio and visual similarity in your Studio media collection.', style: TextStyle(color: Colors.white70)),
        ])),
      const SizedBox(height: 18),
      _MatchToolCard(title: 'Audio Match', description: 'Identify audio fingerprints and search for similar audio across your media library.', icon: Icons.graphic_eq_rounded, accent: const Color(0xFF8758B7), onTap: () => _open(context, 'Audio Match')),
      const SizedBox(height: 12),
      _MatchToolCard(title: 'Visual Match', description: 'Compare video frame fingerprints and explore visual similarities between clips.', icon: Icons.video_camera_back_outlined, accent: const Color(0xFF21867D), onTap: () => _open(context, 'Visual Match')),
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => _open(context, 'Compare'), icon: const Icon(Icons.compare_arrows_rounded), label: const Text('Compare audio files')),
    ]));
  }
}
class _MatchToolCard extends StatelessWidget {
  const _MatchToolCard({required this.title, required this.description, required this.icon, required this.accent, required this.onTap});
  final String title, description; final IconData icon; final Color accent; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(color: Theme.of(context).colorScheme.surfaceContainerLow, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20),
    child: Padding(padding: const EdgeInsets.all(17), child: Row(children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: accent, size: 24)),
      const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4), Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])), const Icon(Icons.chevron_right_rounded),
    ]))));
}
