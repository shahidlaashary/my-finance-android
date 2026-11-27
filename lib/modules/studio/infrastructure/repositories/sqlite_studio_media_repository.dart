import 'package:sqflite/sqflite.dart';

import '../../domain/entities/studio_media_file.dart';
import '../../domain/repositories/studio_media_repository.dart';

class SqliteStudioMediaRepository implements StudioMediaRepository {
  const SqliteStudioMediaRepository(this._database);

  final Database _database;

  @override
  Future<void> register(StudioMediaFile mediaFile) async {
    await _database.insert(
      'studio_media_files',
      mediaFile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<StudioMediaFile?> getById(String id) async {
    final rows = await _database.query(
      'studio_media_files',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StudioMediaFile.fromMap(rows.first);
  }

  @override
  Future<List<StudioMediaFile>> getAll({
    StudioMediaType? mediaType,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit < 1 || offset < 0) {
      throw ArgumentError('limit must be positive and offset cannot be negative.');
    }

    final conditions = <String>[];
    final arguments = <Object?>[];

    if (mediaType != null) {
      conditions.add('media_type = ?');
      arguments.add(mediaType.name);
    }

    final normalizedSearch = search?.trim();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      conditions.add('(original_name LIKE ? OR storage_path LIKE ?)');
      final pattern = '%$normalizedSearch%';
      arguments
        ..add(pattern)
        ..add(pattern);
    }

    final rows = await _database.query(
      'studio_media_files',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'created_at DESC, id ASC',
      limit: limit,
      offset: offset,
    );

    return rows.map(StudioMediaFile.fromMap).toList(growable: false);
  }

  @override
  Future<void> updateImportStatus(
    String id,
    StudioMediaImportStatus status,
  ) async {
    final changed = await _database.update(
      'studio_media_files',
      {
        'import_status': status.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed == 0) {
      throw StateError('Studio media file not found: $id');
    }
  }

  @override
  Future<void> removeRecord(String id) async {
    await _database.delete(
      'studio_media_files',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
