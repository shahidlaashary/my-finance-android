import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_reports_service.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late StudioReportsService reports;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    reports = StudioReportsService(databaseProvider: () async => database);
  });

  tearDown(() async => database.close());

  test('loads recent comparison details and linked claim evidence', () async {
    final now = DateTime.utc(2026, 1, 1).toIso8601String();
    for (final item in [
      ('media-a', 'Query audio', '/studio/query.wav'),
      ('media-b', 'Reference audio', '/studio/reference.wav'),
    ]) {
      await database.insert('studio_media_files', {
        'id': item.$1,
        'media_type': 'audio',
        'original_name': item.$2,
        'storage_path': item.$3,
        'file_size_bytes': 128,
        'created_at': now,
        'updated_at': now,
      });
    }

    await database.insert('studio_comparison_history', {
      'id': 'comparison-1',
      'left_media_id': 'media-a',
      'right_media_id': 'media-b',
      'algorithm_key': 'audio-landmark-v1',
      'algorithm_version': '1',
      'match_score': 0.875,
      'matched_landmarks': 42,
      'offset_ms': 125,
      'result_json': '{}',
      'created_at': now,
    });

    await database.insert('studio_rights_claims', {
      'id': 'claim-1',
      'claim_type': 'copyright',
      'asset_type': 'audio',
      'asset_id': 'media-a',
      'claimant_name': 'Claimant A',
      'title': 'Audio ownership claim',
      'description': 'Claim details',
      'status': 'under_review',
      'priority': 'normal',
      'created_at': now,
      'updated_at': now,
    });

    await database.insert('studio_claim_evidence', {
      'id': 'evidence-1',
      'claim_id': 'claim-1',
      'evidence_type': 'document',
      'title': 'Original recording receipt',
      'description': 'Purchase receipt',
      'file_path': '/studio/receipt.pdf',
      'created_at': now,
    });

    final summary = await reports.load();

    expect(summary.recentComparisons, hasLength(1));
    expect(summary.recentComparisons.single['left_name'], 'Query audio');
    expect(summary.recentComparisons.single['right_name'], 'Reference audio');
    expect(summary.recentComparisons.single['match_score'], 0.875);
    expect(summary.recentEvidence, hasLength(1));
    expect(summary.recentEvidence.single['title'], 'Original recording receipt');
    expect(summary.recentEvidence.single['claim_title'], 'Audio ownership claim');
    expect(summary.recentEvidence.single['claim_status'], 'under_review');
  });

  test('returns empty detail lists when there are no comparisons or evidence', () async {
    final summary = await reports.load();

    expect(summary.recentComparisons, isEmpty);
    expect(summary.recentEvidence, isEmpty);
  });
}
