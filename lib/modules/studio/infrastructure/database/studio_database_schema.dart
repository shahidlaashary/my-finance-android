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
      CREATE TABLE studio_artists (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        legal_name TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_labels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_releases (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        release_type TEXT NOT NULL,
        release_date TEXT,
        label_id TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (label_id) REFERENCES studio_labels(id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_tracks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
        media_file_id TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (media_file_id) REFERENCES studio_media_files(id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_release_tracks (
        release_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        disc_number INTEGER NOT NULL DEFAULT 1 CHECK (disc_number > 0),
        track_number INTEGER NOT NULL CHECK (track_number > 0),
        created_at TEXT NOT NULL,
        PRIMARY KEY (release_id, track_id),
        UNIQUE (release_id, disc_number, track_number),
        FOREIGN KEY (release_id) REFERENCES studio_releases(id)
          ON DELETE CASCADE,
        FOREIGN KEY (track_id) REFERENCES studio_tracks(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_release_artists (
        release_id TEXT NOT NULL,
        artist_id TEXT NOT NULL,
        credit_role TEXT NOT NULL DEFAULT 'primary',
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (release_id, artist_id, credit_role),
        FOREIGN KEY (release_id) REFERENCES studio_releases(id)
          ON DELETE CASCADE,
        FOREIGN KEY (artist_id) REFERENCES studio_artists(id)
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_track_artists (
        track_id TEXT NOT NULL,
        artist_id TEXT NOT NULL,
        credit_role TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (track_id, artist_id, credit_role),
        FOREIGN KEY (track_id) REFERENCES studio_tracks(id)
          ON DELETE CASCADE,
        FOREIGN KEY (artist_id) REFERENCES studio_artists(id)
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_release_identifiers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        release_id TEXT NOT NULL,
        identifier_type TEXT NOT NULL,
        identifier_value TEXT NOT NULL,
        issuer TEXT,
        is_official INTEGER NOT NULL DEFAULT 0
          CHECK (is_official IN (0, 1)),
        created_at TEXT NOT NULL,
        UNIQUE (identifier_type, identifier_value),
        FOREIGN KEY (release_id) REFERENCES studio_releases(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_track_identifiers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id TEXT NOT NULL,
        identifier_type TEXT NOT NULL,
        identifier_value TEXT NOT NULL,
        issuer TEXT,
        is_official INTEGER NOT NULL DEFAULT 0
          CHECK (is_official IN (0, 1)),
        created_at TEXT NOT NULL,
        UNIQUE (identifier_type, identifier_value),
        FOREIGN KEY (track_id) REFERENCES studio_tracks(id)
          ON DELETE CASCADE
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
    await db.execute(
      'CREATE INDEX idx_studio_releases_title '
      'ON studio_releases(title COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_tracks_title '
      'ON studio_tracks(title COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_release_tracks_track '
      'ON studio_release_tracks(track_id)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_track_artists_artist '
      'ON studio_track_artists(artist_id)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_release_artists_artist '
      'ON studio_release_artists(artist_id)',
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
