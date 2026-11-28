import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../application/services/studio_reports_service.dart';

class StudioReportsScreen extends StatefulWidget {
  const StudioReportsScreen({super.key});

  @override
  State<StudioReportsScreen> createState() => _StudioReportsScreenState();
}

class _StudioReportsScreenState extends State<StudioReportsScreen> {
  late Future<StudioReportSummary> _future;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = StudioReportsService().load();
  }

  Future<void> _refresh() async {
    final next = StudioReportsService().load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _export(StudioReportSummary report) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final document = pw.Document();
      final generated = report.generatedAt.toLocal().toString().split('.').first;
      final sections = <List<String>>[
        ['MEDIA LIBRARY', 'Total files', report.media.toString()],
        ['MEDIA LIBRARY', 'Audio files', report.audio.toString()],
        ['MEDIA LIBRARY', 'Video files', report.video.toString()],
        ['IDENTIFICATION', 'Fingerprints generated', report.fingerprints.toString()],
        ['IDENTIFICATION', 'Saved comparisons', report.comparisons.toString()],
        ['CATALOGUE', 'Tracks', report.tracks.toString()],
        ['CATALOGUE', 'Artists', report.artists.toString()],
        ['CATALOGUE', 'Releases', report.releases.toString()],
        ['RIGHTS', 'Rights holders', report.holders.toString()],
        ['RIGHTS', 'Ownership records', report.ownerships.toString()],
        ['RIGHTS', 'Licences', report.licenses.toString()],
        ['RIGHTS', 'Total claims', report.totalClaims.toString()],
        ['RIGHTS', 'Open claims', report.openClaims.toString()],
        ['RIGHTS', 'Resolved / closed claims', report.resolvedClaims.toString()],
        ['RIGHTS', 'Evidence records', report.evidenceItems.toString()],
        ['PROCESSING', 'Active jobs', report.pendingJobs.toString()],
        ['PROCESSING', 'Failed jobs', report.failedJobs.toString()],
      ];
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            pw.Text('Studio Activity Report',
                style: pw.TextStyle(
                    fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text('Generated: $generated',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 18),
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.15),
                1: const pw.FlexColumnWidth(2.5),
                2: const pw.FlexColumnWidth(0.8),
              },
              children: [
                _pdfRow(['SECTION', 'METRIC', 'COUNT'], header: true),
                ...sections.map((row) => _pdfRow(row)),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'This report contains local Studio database totals. It does not verify ownership, legal status, or external platform claims.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => document.save(),
        name: 'studio-activity-report.pdf',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  pw.TableRow _pdfRow(List<String> values, {bool header = false}) {
    return pw.TableRow(
      decoration: header
          ? const pw.BoxDecoration(color: PdfColors.grey300)
          : null,
      children: values
          .map(
            (value) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 7, vertical: 6),
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight:
                      header ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<(String, int, IconData)> items,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 15),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 76,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                child: Row(
                  children: [
                    Icon(item.$3, size: 20, color: colors.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item.$1,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      item.$2.toString(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _detailSection(
    BuildContext context,
    String title,
    List<Widget> children, {
    required String emptyText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 15),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (children.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(emptyText,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          )
        else
          ...children,
      ],
    );
  }

  Widget _detailTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    String? timestamp,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: colors.primary),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [subtitle, if (timestamp != null) timestamp].join('\\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh report',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<StudioReportSummary>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 40),
                    const SizedBox(height: 10),
                    Text('Report loading failed: ${snapshot.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'All-time Studio overview',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _exporting ? null : () => _export(data),
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(_exporting ? 'Preparing' : 'Export PDF'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Updated ${data.generatedAt.toLocal().toString().split('.').first}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                _section(context, 'Media library', [
                  ('Total media', data.media, Icons.perm_media_outlined),
                  ('Audio', data.audio, Icons.music_note_rounded),
                  ('Video', data.video, Icons.video_library_outlined),
                  ('Fingerprints', data.fingerprints, Icons.fingerprint_rounded),
                ]),
                _section(context, 'Catalogue & identification', [
                  ('Tracks', data.tracks, Icons.library_music_outlined),
                  ('Artists', data.artists, Icons.person_outline_rounded),
                  ('Releases', data.releases, Icons.album_outlined),
                  ('Comparisons', data.comparisons, Icons.compare_arrows_rounded),
                ]),
                _section(context, 'Rights management', [
                  ('Rights holders', data.holders, Icons.people_outline_rounded),
                  ('Ownership', data.ownerships, Icons.verified_user_outlined),
                  ('Licences', data.licenses, Icons.description_outlined),
                  ('All claims', data.totalClaims, Icons.gavel_rounded),
                  ('Open claims', data.openClaims, Icons.pending_actions_rounded),
                  ('Closed claims', data.resolvedClaims, Icons.task_alt_rounded),
                  ('Evidence records', data.evidenceItems, Icons.attach_file_rounded),
                ]),
                _detailSection(
                  context,
                  'Recent Content ID comparisons',
                  data.recentComparisons.map((item) {
                    final score = (item['match_score'] as num?)?.toDouble();
                    final scoreText = score == null ? 'Score unavailable' :
                        '${score.toStringAsFixed(1)}% confidence';
                    final offset = item['offset_ms'] as int?;
                    return _detailTile(
                      context,
                      Icons.compare_arrows_rounded,
                      '${item['left_name']}  ↔  ${item['right_name']}',
                      '${item['algorithm_key'] ?? 'Unknown algorithm'} • $scoreText • ${item['matched_landmarks'] ?? 0} matched points${offset == null ? '' : ' • ${offset}ms offset'}',
                      item['created_at']?.toString(),
                    );
                  }).toList(),
                  emptyText: 'No Content ID comparisons have been saved yet.',
                ),
                _detailSection(
                  context,
                  'Recent claim evidence',
                  data.recentEvidence.map((item) => _detailTile(
                    context,
                    Icons.attach_file_rounded,
                    item['title']?.toString() ?? 'Untitled evidence',
                    '${item['evidence_type']} • Claim: ${item['claim_title']} • ${item['claim_status']}',
                    item['created_at']?.toString(),
                  )).toList(),
                  emptyText: 'No claim evidence has been attached yet.',
                ),
                _section(context, 'Processing', [
                  ('Active jobs', data.pendingJobs, Icons.pending_actions_rounded),
                  ('Failed jobs', data.failedJobs, Icons.error_outline_rounded),
                ]),
                const SizedBox(height: 14),
                Text(
                  'Counts are read from the local Studio database. They are activity indicators, not legal verification or proof of copyright ownership.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
