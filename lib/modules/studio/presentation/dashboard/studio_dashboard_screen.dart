import 'package:flutter/material.dart';
import 'package:my_finance/modules/studio/services/studio_dashboard_service.dart';
import 'package:my_finance/modules/studio/presentation/media_library/studio_media_library_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_catalogue_rights_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_music_id_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_video_id_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_reports_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_management_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_recording_screen.dart';
import 'package:my_finance/modules/studio/presentation/ai_music/studio_ai_music_screen.dart';

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
    _StudioSection('AI Music', 'Create song projects and manage authorized voice profiles', Icons.auto_awesome_rounded),
    _StudioSection('Video ID', 'Video identification and fingerprinting', Icons.video_library_outlined),
    _StudioSection('Compare', 'Compare two or more media files', Icons.compare_arrows_rounded),
    _StudioSection('Catalogue', 'Browse and organize registered content', Icons.library_music_outlined),
    _StudioSection('Rights Management', 'Manage ownership and licensing records', Icons.verified_user_outlined),
    _StudioSection('Recording', 'Record clean audio directly into your Studio library', Icons.mic_none_rounded),
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
    if (section.title == 'Reports') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudioReportsScreen()));
      return;
    }
    if (section.title == 'Management') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudioManagementScreen()));
      return;
    }
    if (section.title == 'Recording') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudioRecordingScreen()));
      return;
    }
    if (section.title == 'AI Music') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudioAiMusicScreen()));
      return;
    }
    if (section.title == 'Video ID') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudioVideoIdScreen()));
      return;
    }
    if (section.title == 'Music ID' || section.title == 'Compare') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudioMusicIdScreen(section: section.title)));
      return;
    }
    if (section.title == 'Catalogue' || section.title == 'Rights Management') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => StudioCatalogueRightsScreen(section: section.title)),
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text('STUDIO WORKSPACE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 1.35)),
            const SizedBox(height: 5),
            Text('Studio', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.7)),
            const SizedBox(height: 5),
            Text(
              'Manage media, discover matches and protect your creative rights',
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
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text('Your Studio', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.35))),
              Text('${_sections.length} systems', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
            ]),
            const SizedBox(height: 11),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sections.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.68,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
        ],
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

  Color accent(ColorScheme colors) {
    switch (title) {
      case 'Media Library':
        return const Color(0xFF3978B8);
      case 'Music ID':
        return const Color(0xFF8B5BC2);
      case 'AI Music':
        return const Color(0xFFB66A35);
      case 'Video ID':
        return const Color(0xFF258B83);
      case 'Compare':
        return const Color(0xFF5576B8);
      case 'Catalogue':
        return const Color(0xFF9A6B38);
      case 'Rights Management':
        return const Color(0xFF43845D);
      case 'Recording':
        return const Color(0xFFB34F64);
      case 'Reports':
        return const Color(0xFF6476A5);
      case 'Management':
        return colors.primary;
      default:
        return colors.primary;
    }
  }
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = section.accent(colors);
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.105),
                colors.surfaceContainerLow,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(section.icon, size: 19, color: accent),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 17,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                section.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                section.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.22,
                  fontSize: 11,
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
