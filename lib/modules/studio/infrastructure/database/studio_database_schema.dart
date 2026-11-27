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


    await db.execute('''
      CREATE TABLE studio_fingerprints (
        id TEXT PRIMARY KEY,
        media_file_id TEXT NOT NULL,
        media_type TEXT NOT NULL CHECK (media_type IN ('audio', 'video')),
        algorithm_key TEXT NOT NULL,
        algorithm_version TEXT NOT NULL,
        fingerprint_format TEXT NOT NULL,
        data_file_path TEXT NOT NULL UNIQUE,
        checksum_sha256 TEXT,
        sample_rate INTEGER CHECK (sample_rate IS NULL OR sample_rate > 0),
        channels INTEGER CHECK (channels IS NULL OR channels > 0),
        duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
        frame_count INTEGER NOT NULL DEFAULT 0 CHECK (frame_count >= 0),
        status TEXT NOT NULL DEFAULT 'generated'
          CHECK (status IN ('pending', 'generated', 'indexed', 'failed', 'stale')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (media_file_id, algorithm_key, algorithm_version),
        FOREIGN KEY (media_file_id) REFERENCES studio_media_files(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_fingerprint_segments (
        fingerprint_id TEXT NOT NULL,
        segment_index INTEGER NOT NULL CHECK (segment_index >= 0),
        start_ms INTEGER NOT NULL CHECK (start_ms >= 0),
        end_ms INTEGER NOT NULL CHECK (end_ms > start_ms),
        data_offset_bytes INTEGER NOT NULL CHECK (data_offset_bytes >= 0),
        data_length_bytes INTEGER NOT NULL CHECK (data_length_bytes > 0),
        signature_hash TEXT,
        PRIMARY KEY (fingerprint_id, segment_index),
        FOREIGN KEY (fingerprint_id) REFERENCES studio_fingerprints(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_fingerprint_indexes (
        id TEXT PRIMARY KEY,
        algorithm_key TEXT NOT NULL,
        algorithm_version TEXT NOT NULL,
        index_file_path TEXT NOT NULL UNIQUE,
        checksum_sha256 TEXT,
        item_count INTEGER NOT NULL DEFAULT 0 CHECK (item_count >= 0),
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'ready', 'failed', 'stale')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_studio_fingerprints_media '
      'ON studio_fingerprints(media_file_id, algorithm_key, algorithm_version)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_fingerprints_status '
      'ON studio_fingerprints(status, media_type)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_fingerprint_segments_time '
      'ON studio_fingerprint_segments(fingerprint_id, start_ms, end_ms)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_fingerprint_indexes_status '
      'ON studio_fingerprint_indexes(status, algorithm_key)',
    );

    await db.execute('''
      CREATE TABLE studio_rights_holders (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, holder_type TEXT NOT NULL,
        contact TEXT, notes TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE studio_ownership_records (
        id TEXT PRIMARY KEY, holder_id TEXT NOT NULL, asset_type TEXT NOT NULL,
        asset_id TEXT NOT NULL, share_percent REAL NOT NULL CHECK (share_percent > 0 AND share_percent <= 100),
        territory TEXT NOT NULL DEFAULT 'Worldwide', start_date TEXT, end_date TEXT,
        notes TEXT, created_at TEXT NOT NULL,
        FOREIGN KEY(holder_id) REFERENCES studio_rights_holders(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE TABLE studio_licenses (
        id TEXT PRIMARY KEY, asset_type TEXT NOT NULL, asset_id TEXT NOT NULL,
        licensor TEXT NOT NULL, licensee TEXT NOT NULL, usage_type TEXT NOT NULL,
        territory TEXT NOT NULL DEFAULT 'Worldwide', start_date TEXT, end_date TEXT,
        exclusive INTEGER NOT NULL DEFAULT 0 CHECK(exclusive IN (0,1)),
        status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','expired','terminated')),
        document_path TEXT, notes TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE studio_comparison_history (
        id TEXT PRIMARY KEY, left_media_id TEXT NOT NULL, right_media_id TEXT NOT NULL,
        algorithm_key TEXT, algorithm_version TEXT, match_score REAL NOT NULL,
        matched_landmarks INTEGER NOT NULL DEFAULT 0, offset_ms INTEGER,
        result_json TEXT, created_at TEXT NOT NULL,
        FOREIGN KEY(left_media_id) REFERENCES studio_media_files(id) ON DELETE CASCADE,
        FOREIGN KEY(right_media_id) REFERENCES studio_media_files(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_studio_ownership_asset ON studio_ownership_records(asset_type, asset_id)');
    await db.execute('CREATE INDEX idx_studio_licenses_asset ON studio_licenses(asset_type, asset_id)');
    await db.execute('CREATE INDEX idx_studio_compare_date ON studio_comparison_history(created_at DESC)');
    await db.execute('''
      CREATE TABLE studio_ai_voice_profiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        owner_name TEXT NOT NULL,
        sample_path TEXT NOT NULL,
        consent_granted INTEGER NOT NULL DEFAULT 0
          CHECK (consent_granted IN (0, 1)),
        consent_scope TEXT NOT NULL,
        consent_recorded_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE studio_ai_music_projects (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        prompt TEXT NOT NULL DEFAULT '',
        lyrics TEXT NOT NULL DEFAULT '',
        genre TEXT NOT NULL,
        language TEXT NOT NULL,
        mood TEXT NOT NULL,
        voice_profile_id TEXT,
        status TEXT NOT NULL DEFAULT 'draft'
          CHECK (status IN ('draft', 'queued', 'generating', 'completed', 'failed')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (voice_profile_id) REFERENCES studio_ai_voice_profiles(id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_studio_ai_projects_updated '
      'ON studio_ai_music_projects(updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_studio_ai_voice_consent '
      'ON studio_ai_voice_profiles(consent_granted, created_at DESC)',
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
