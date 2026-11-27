import 'package:sqflite/sqflite.dart';

/// Fresh V1 schema for Studio. Studio owns this schema independently
/// from the application's finance and My Space databases.
class StudioDatabaseSchema {
  StudioDatabaseSchema._();

  static const int version = 1;

  static Future<void> create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE studio_metadata (
        metadata_key TEXT PRIMARY KEY,
        metadata_value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_id_sequences (
        entity_type TEXT PRIMARY KEY,
        next_value INTEGER NOT NULL CHECK (next_value > 0),
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        entity_type TEXT,
        entity_id TEXT,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_media_files (
        id TEXT PRIMARY KEY,
        media_type TEXT NOT NULL CHECK (media_type IN ('audio', 'video')),
        original_name TEXT NOT NULL,
        storage_path TEXT NOT NULL UNIQUE,
        mime_type TEXT,
        file_extension TEXT,
        file_size_bytes INTEGER NOT NULL DEFAULT 0
          CHECK (file_size_bytes >= 0),
        duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
        checksum_sha256 TEXT,
        import_status TEXT NOT NULL DEFAULT 'imported',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_processing_jobs (
        id TEXT PRIMARY KEY,
        job_type TEXT NOT NULL,
        target_type TEXT,
        target_id TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN (
            'pending', 'queued', 'running',
            'completed', 'failed', 'cancelled'
          )),
        progress REAL NOT NULL DEFAULT 0
          CHECK (progress >= 0 AND progress <= 100),
        attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        started_at TEXT,
        completed_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_studio_media_type_created '
      'ON studio_media_files(media_type, created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_jobs_status_created '
      'ON studio_processing_jobs(status, created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_activity_created '
      'ON studio_activity_logs(created_at)',
    );

    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('studio_metadata', {
      'metadata_key': 'schema_version',
      'metadata_value': version.toString(),
      'updated_at': now,
    });
    await db.insert('studio_metadata', {
      'metadata_key': 'studio_installation_status',
      'metadata_value': 'initialized',
      'updated_at': now,
    });
  }
}
