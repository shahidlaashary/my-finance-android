import 'package:sqflite/sqflite.dart';

import '../../infrastructure/database/studio_database_manager.dart';

class StudioReportSummary {
  const StudioReportSummary({
    required this.generatedAt,
    required this.media,
    required this.audio,
    required this.video,
    required this.fingerprints,
    required this.tracks,
    required this.artists,
    required this.releases,
    required this.holders,
    required this.ownerships,
    required this.licenses,
    required this.comparisons,
    required this.pendingJobs,
    required this.failedJobs,
    required this.totalClaims,
    required this.openClaims,
    required this.resolvedClaims,
    required this.evidenceItems,
  });

  final DateTime generatedAt;
  final int media;
  final int audio;
  final int video;
  final int fingerprints;
  final int tracks;
  final int artists;
  final int releases;
  final int holders;
  final int ownerships;
  final int licenses;
  final int comparisons;
  final int pendingJobs;
  final int failedJobs;
  final int totalClaims;
  final int openClaims;
  final int resolvedClaims;
  final int evidenceItems;
}

class StudioReportsService {
  Future<StudioReportSummary> load() async {
    final db = await StudioDatabaseManager.instance.initialize();
    final counts = await Future.wait([
      _count(db, 'studio_media_files'),
      _count(db, 'studio_fingerprints'),
      _count(db, 'studio_tracks'),
      _count(db, 'studio_artists'),
      _count(db, 'studio_releases'),
      _count(db, 'studio_rights_holders'),
      _count(db, 'studio_ownership_records'),
      _count(db, 'studio_licenses'),
      _count(db, 'studio_comparison_history'),
      _count(db, 'studio_rights_claims'),
      _count(db, 'studio_claim_evidence'),
    ]);

    final audio = await _countWhere(
      db,
      'studio_media_files',
      "media_type = 'audio'",
    );
    final video = await _countWhere(
      db,
      'studio_media_files',
      "media_type = 'video'",
    );
    final pending = await _countWhere(
      db,
      'studio_processing_jobs',
      "status IN ('pending', 'queued', 'running')",
    );
    final failed = await _countWhere(
      db,
      'studio_processing_jobs',
      "status = 'failed'",
    );
    final openClaims = await _countWhere(
      db,
      'studio_rights_claims',
      "status IN ('submitted', 'under_review')",
    );
    final resolvedClaims = await _countWhere(
      db,
      'studio_rights_claims',
      "status IN ('resolved', 'rejected', 'withdrawn')",
    );

    return StudioReportSummary(
      generatedAt: DateTime.now(),
      media: counts[0],
      audio: audio,
      video: video,
      fingerprints: counts[1],
      tracks: counts[2],
      artists: counts[3],
      releases: counts[4],
      holders: counts[5],
      ownerships: counts[6],
      licenses: counts[7],
      comparisons: counts[8],
      totalClaims: counts[9],
      evidenceItems: counts[10],
      pendingJobs: pending,
      failedJobs: failed,
      openClaims: openClaims,
      resolvedClaims: resolvedClaims,
    );
  }

  Future<int> _count(Database db, String table) async {
    const allowed = {
      'studio_media_files',
      'studio_fingerprints',
      'studio_tracks',
      'studio_artists',
      'studio_releases',
      'studio_rights_holders',
      'studio_ownership_records',
      'studio_licenses',
      'studio_comparison_history',
      'studio_rights_claims',
      'studio_claim_evidence',
    };
    if (!allowed.contains(table)) {
      throw ArgumentError('Unsupported report table');
    }
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.first['c'] as num).toInt();
  }

  Future<int> _countWhere(
    Database db,
    String table,
    String where,
  ) async {
    const allowed = {
      'studio_media_files',
      'studio_processing_jobs',
      'studio_rights_claims',
    };
    if (!allowed.contains(table)) {
      throw ArgumentError('Unsupported report table');
    }
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE $where',
    );
    return (rows.first['c'] as num).toInt();
  }
}
