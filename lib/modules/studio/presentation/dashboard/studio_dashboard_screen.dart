import 'package:flutter/material.dart';
import 'package:my_finance/modules/studio/services/studio_dashboard_service.dart';
import 'package:my_finance/modules/studio/presentation/media_library/studio_media_library_screen.dart';

class StudioDashboardScreen extends StatefulWidget {
  const StudioDashboardScreen({super.key});

  @override
  State<StudioDashboardScreen> createState() => _StudioDashboardScreenState();
}

class _StudioDashboardScreenState extends State<StudioDashboardScreen> {
  late Future<StudioDashboardSummary> _summary;

  static const _sections = <_StudioSection>[
    _StudioSection('Media Library', 'Import and browse managed audio and video files', Icons.perm_media_outlined),
    _StudioSection('Music ID', 'Audio identification and fingerprinting', Icons.music_note_rounded),
    _StudioSection('Video ID', 'Video identification and fingerprinting', Icons.video_library_outlined),
    _StudioSection('Compare', 'Compare two or more media files', Icons.compare_arrows_rounded),
    _StudioSection('Catalogue', 'Browse and organize registered content', Icons.library_music_outlined),
    _StudioSection('Rights Management', 'Manage ownership and licensing records', Icons.verified_user_outlined),
    _StudioSection('Recording', 'Recording workspace', Icons.mic_none_rounded, placeholder: true),
    _StudioSection('Reports', 'Analysis and activity reports', Icons.analytics_outlined),
    _StudioSection('Management', 'Studio administration and system controls', Icons.settings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _summary = StudioDashboardService.instance.loadSummary();
  }

  void _openSection(_StudioSection section) {
    if (section.title == 'Media Library') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const StudioMediaLibraryScreen()),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _StudioSectionPlaceholderScreen(section: section),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FutureBuilder<StudioDashboardSummary>(
      future: _summary,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Text('Studio', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 5),
            Text(
              'Your media identification and rights workspace',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _StudioStatCard(
                    label: 'Media Files',
                    value: summary?.mediaFiles.toString() ?? (snapshot.hasError ? '—' : '…'),
                    icon: Icons.perm_media_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StudioStatCard(
                    label: 'Active Jobs',
                    value: summary?.pendingJobs.toString() ?? (snapshot.hasError ? '—' : '…'),
                    icon: Icons.pending_actions_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StudioStatCard(
                    label: 'Failed Jobs',
                    value: summary?.failedJobs.toString() ?? (snapshot.hasError ? '—' : '…'),
                    icon: Icons.error_outline_rounded,
                  ),
                ),
              ],
            ),
            if (snapshot.hasError) ...[
              const SizedBox(height: 10),
              Text(
                'Studio database could not be opened: ${snapshot.error}',
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _summary = StudioDashboardService.instance.loadSummary();
                  }),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry database connection'),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text('Studio Systems', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sections.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.28,
              ),
              itemBuilder: (context, index) {
                final section = _sections[index];
                return _StudioSectionCard(
                  section: section,
                  onTap: () => _openSection(section),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _StudioStatCard extends StatelessWidget {
  const _StudioStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioSection {
  const _StudioSection(
    this.title,
    this.description,
    this.icon, {
    this.placeholder = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool placeholder;
}

class _StudioSectionCard extends StatelessWidget {
  const _StudioSectionCard({
    required this.section,
    required this.onTap,
  });

  final _StudioSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(section.icon, size: 25, color: colors.primary),
              const Spacer(),
              Text(
                section.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                section.placeholder ? 'Coming later' : section.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioSectionPlaceholderScreen extends StatelessWidget {
  const _StudioSectionPlaceholderScreen({required this.section});

  final _StudioSection section;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(section.icon, size: 52, color: colors.primary),
              const SizedBox(height: 16),
              Text(section.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                section.placeholder
                    ? 'Recording is reserved as a placeholder for a future phase.'
                    : 'This Studio system will be implemented in its dedicated development phase.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
