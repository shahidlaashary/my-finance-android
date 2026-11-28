import 'package:flutter/material.dart';
import 'package:my_finance/modules/studio/application/services/studio_dashboard_service.dart';
import 'package:my_finance/modules/studio/presentation/media_library/studio_media_library_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_catalogue_rights_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_reports_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_management_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_recording_screen.dart';
import 'package:my_finance/modules/studio/presentation/ai_music/studio_ai_music_screen.dart';
import 'package:my_finance/modules/studio/presentation/studio_content_id_screen.dart';

class StudioDashboardScreen extends StatefulWidget {
  const StudioDashboardScreen({super.key});

  @override
  State<StudioDashboardScreen> createState() => _StudioDashboardScreenState();
}

class _StudioDashboardScreenState extends State<StudioDashboardScreen> {
  late Future<StudioDashboardSummary> _summary;

  static const _sections = <_StudioSection>[
    _StudioSection('Media Library', 'Import and browse managed audio and video files', Icons.perm_media_outlined),
    _StudioSection('Content ID', 'Audio Match and Visual Match identification tools', Icons.fingerprint_rounded),
    _StudioSection('AI Music', 'Create song projects and manage authorized voice profiles', Icons.auto_awesome_rounded),
    
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
    if (section.title == 'Content ID') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudioContentIdScreen()));
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF10283C), Color(0xFF1F5667), Color(0xFF267B7A)],
                ),
                boxShadow: [BoxShadow(color: const Color(0xFF174A5A).withValues(alpha: .18), blurRadius: 24, offset: const Offset(0, 9))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: Color(0xFF8FE1D1),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Studio',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('A dedicated space for your media, discovery and creative tools.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: .82))),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 7, children: [
                  _StudioMetricPill(icon: Icons.folder_open_rounded, label: 'MEDIA', value: summary?.mediaFiles.toString() ?? (snapshot.hasError ? '—' : '…')),
                  _StudioMetricPill(icon: Icons.pending_actions_rounded, label: 'QUEUED', value: summary?.pendingJobs.toString() ?? (snapshot.hasError ? '—' : '…')),
                  _StudioMetricPill(icon: Icons.error_outline_rounded, label: 'FAILED', value: summary?.failedJobs.toString() ?? (snapshot.hasError ? '—' : '…')),
                ]),
              ]),
            ),
            if (snapshot.hasError) ...[
              const SizedBox(height: 10),
              Text('Studio summary unavailable: ${snapshot.error}', style: TextStyle(color: colors.error, fontSize: 12)),
              TextButton.icon(onPressed: () => setState(() => _summary = StudioDashboardService.instance.loadSummary()),
                icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('Workspace tools', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              Text('${_sections.length} tools', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
            ]),
            const SizedBox(height: 11),
            GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _sections.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 9, childAspectRatio: 1.52),
              itemBuilder: (context, index) => _StudioSectionCard(section: _sections[index], onTap: () => _openSection(_sections[index])),
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
      case 'Content ID':
        return const Color(0xFF8B5BC2);
      case 'AI Music':
        return const Color(0xFFB66A35);
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
          padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
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
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(section.icon, size: 17, color: accent),
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

class _StudioMetricPill extends StatelessWidget {
  const _StudioMetricPill({required this.icon, required this.label, required this.value});
  final IconData icon; final String label; final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .11), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .13))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white70, size: 15), const SizedBox(width: 7),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9, letterSpacing: .6)),
      ]),
    ]),
  );
}

