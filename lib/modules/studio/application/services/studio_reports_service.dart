import 'package:sqflite/sqflite.dart';

import '../../infrastructure/database/studio_database_manager.dart';

class StudioReportSummary {
  const StudioReportSummary({
    required this.recentComparisons,
    required this.recentEvidence,
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

  final List<Map<String, Object?>> recentComparisons;
  final List<Map<String, Object?>> recentEvidence;

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
  StudioReportsService({Future<Database> Function()? databaseProvider})
      : _databaseProvider = databaseProvider ??
            StudioDatabaseManager.instance.initialize;

  final Future<Database> Function() _databaseProvider;

  Future<StudioReportSummary> load() async {
    final db = await _databaseProvider();
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

    final recentComparisons = await db.rawQuery('''
      SELECT c.id, c.algorithm_key, c.algorithm_version, c.match_score,
             c.matched_landmarks, c.offset_ms, c.result_json, c.created_at,
             l.original_name AS left_name, r.original_name AS right_name,
             l.media_type AS left_media_type, r.media_type AS right_media_type
      FROM studio_comparison_history c
      INNER JOIN studio_media_files l ON l.id = c.left_media_id
      INNER JOIN studio_media_files r ON r.id = c.right_media_id
      ORDER BY c.created_at DESC
      LIMIT 20
    ''');
    final recentEvidence = await db.rawQuery('''
      SELECT e.id, e.evidence_type, e.title, e.description, e.file_path,
             e.checksum_sha256, e.created_at, c.id AS claim_id,
             c.title AS claim_title, c.claimant_name, c.status AS claim_status
      FROM studio_claim_evidence e
      INNER JOIN studio_rights_claims c ON c.id = e.claim_id
      ORDER BY e.created_at DESC
      LIMIT 20
    ''');

    return StudioReportSummary(
      recentComparisons: recentComparisons,
      recentEvidence: recentEvidence,
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
