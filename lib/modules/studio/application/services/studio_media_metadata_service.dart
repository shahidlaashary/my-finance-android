import 'package:sqflite/sqflite.dart';

import '../../infrastructure/database/studio_database_manager.dart';
import 'studio_id3_metadata_reader.dart';

/// Persists technical audio tags separately from the media-file record.
class StudioMediaMetadataService {
  Future<Database> get _db => StudioDatabaseManager.instance.initialize();

  Future<void> saveAudioTags(String mediaFileId, StudioAudioMetadata metadata,
      {String source = 'id3'}) async {
    final db = await _db;
    await db.insert(
      'studio_media_metadata',
      {
        'media_file_id': mediaFileId,
        'title': metadata.title,
        'artist': metadata.artist,
        'album': metadata.album,
        'track': metadata.track,
        'year': metadata.year,
        'genre': metadata.genre,
        'metadata_source': source,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getForMedia(String mediaFileId) async {
    final rows = await (await _db).query(
      'studio_media_metadata',
      where: 'media_file_id = ?',
      whereArgs: [mediaFileId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
}
