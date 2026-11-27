import 'package:sqflite/sqflite.dart';

import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/repositories/studio_fingerprint_repository.dart';

class SqliteStudioFingerprintRepository
    implements StudioFingerprintRepository {
  const SqliteStudioFingerprintRepository(this._database);

  final Database _database;

  @override
  Future<void> register(StudioFingerprint fingerprint) async {
    await _database.insert(
      'studio_fingerprints',
      fingerprint.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<StudioFingerprint?> getById(String id) async {
    final rows = await _database.query(
      'studio_fingerprints',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : StudioFingerprint.fromMap(rows.first);
  }

  @override
  Future<StudioFingerprint?> getForMedia({
    required String mediaFileId,
    required String algorithmKey,
    required String algorithmVersion,
  }) async {
    final rows = await _database.query(
      'studio_fingerprints',
      where: 'media_file_id = ? AND algorithm_key = ? AND algorithm_version = ?',
      whereArgs: [mediaFileId, algorithmKey, algorithmVersion],
      limit: 1,
    );
    return rows.isEmpty ? null : StudioFingerprint.fromMap(rows.first);
  }

  @override
  Future<List<StudioFingerprint>> getForMediaFile(String mediaFileId) async {
    final rows = await _database.query(
      'studio_fingerprints',
      where: 'media_file_id = ?',
      whereArgs: [mediaFileId],
      orderBy: 'created_at DESC, id ASC',
    );
    return rows.map(StudioFingerprint.fromMap).toList(growable: false);
  }

  @override
  Future<void> replaceSegments(
    String fingerprintId,
    List<StudioFingerprintSegment> segments,
  ) async {
    await _database.transaction((txn) async {
      final parent = await txn.query(
        'studio_fingerprints',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [fingerprintId],
        limit: 1,
      );
      if (parent.isEmpty) {
        throw StateError('Studio fingerprint not found: $fingerprintId');
      }

      await txn.delete(
        'studio_fingerprint_segments',
        where: 'fingerprint_id = ?',
        whereArgs: [fingerprintId],
      );
      for (final segment in segments) {
        if (segment.fingerprintId != fingerprintId) {
          throw ArgumentError('All segments must belong to $fingerprintId.');
        }
        await txn.insert(
          'studio_fingerprint_segments',
          segment.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  @override
  Future<List<StudioFingerprintSegment>> getSegments(
    String fingerprintId,
  ) async {
    final rows = await _database.query(
      'studio_fingerprint_segments',
      where: 'fingerprint_id = ?',
      whereArgs: [fingerprintId],
      orderBy: 'segment_index ASC',
    );
    return rows
        .map(StudioFingerprintSegment.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> remove(String id) async {
    await _database.delete(
      'studio_fingerprints',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> updateStatus(
    String id,
    StudioFingerprintStatus status,
  ) async {
    final changed = await _database.update(
      'studio_fingerprints',
      {
        'status': status.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed == 0) {
      throw StateError('Studio fingerprint not found: $id');
    }
  }
}
