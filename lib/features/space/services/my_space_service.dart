import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

/// Independent local data store for My Space.
/// Finance database and finance records are never opened or modified here.
class MySpaceService {
  MySpaceService._();
  static final MySpaceService instance = MySpaceService._();

  static const _databaseName = 'space.db';
  static const _tableName = 'space_items';
  static const _playlistsTable = 'space_playlists';
  static const _playlistItemsTable = 'space_playlist_items';
  static const _collectionsTable = 'space_collections';
  static const _collectionItemsTable = 'space_collection_items';

  Database? _database;
  Future<Database>? _opening;

  Future<Directory> get spaceDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(appDir.path, 'my_space'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> get filesDirectory async {
    final directory = Directory(p.join((await spaceDirectory).path, 'files'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Database> get database async {
    final current = _database;
    if (current != null && current.isOpen) return current;
    final pending = _opening;
    if (pending != null) return pending;

    final future = _openDatabase();
    _opening = future;
    try {
      return await future;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _openDatabase() async {
    final directory = await spaceDirectory;
    final db = await openDatabase(
      p.join(directory.path, _databaseName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            file_name TEXT NOT NULL,
            file_path TEXT NOT NULL,
            file_type TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            added_at TEXT NOT NULL,
            last_page INTEGER NOT NULL DEFAULT 1,
            last_position_ms INTEGER NOT NULL DEFAULT 0,
            last_epub_cfi TEXT
          )
        ''');
      },
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
    // Idempotent add-on tables; no change to the existing Space schema.
    await _ensureAddOnTables(db);
    await _ensureSectionTables(db);
    _database = db;
    return db;
  }


  Future<void> _ensureAddOnTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS $_playlistsTable (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS $_playlistItemsTable (playlist_id INTEGER NOT NULL, item_id INTEGER NOT NULL, added_at TEXT NOT NULL, PRIMARY KEY (playlist_id, item_id), FOREIGN KEY (playlist_id) REFERENCES $_playlistsTable(id) ON DELETE CASCADE, FOREIGN KEY (item_id) REFERENCES $_tableName(id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE IF NOT EXISTS $_collectionsTable (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS $_collectionItemsTable (collection_id INTEGER NOT NULL, item_id INTEGER NOT NULL UNIQUE, added_at TEXT NOT NULL, PRIMARY KEY (collection_id, item_id), FOREIGN KEY (collection_id) REFERENCES $_collectionsTable(id) ON DELETE CASCADE, FOREIGN KEY (item_id) REFERENCES $_tableName(id) ON DELETE CASCADE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_space_collection_items_collection ON $_collectionItemsTable(collection_id)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS space_youtube_videos (
        video_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        channel_title TEXT NOT NULL DEFAULT '',
        thumbnail_url TEXT NOT NULL DEFAULT '',
        saved_at TEXT NOT NULL,
        last_watched_at TEXT
      )
    """);
  }

  Future<void> saveYouTubeVideo({required String videoId, required String title, String? channelTitle, String? thumbnailUrl}) async {
    final db = await database;
    await db.insert('space_youtube_videos', {
      'video_id': videoId,
      'title': title.trim().isEmpty ? 'YouTube video' : title.trim(),
      'channel_title': channelTitle ?? '',
      'thumbnail_url': thumbnailUrl ?? '',
      'saved_at': DateTime.now().toIso8601String(),
      'last_watched_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getYouTubeVideos({bool history = false}) async {
    final db = await database;
    return db.query('space_youtube_videos',
      where: history ? 'last_watched_at IS NOT NULL' : null,
      orderBy: history ? 'last_watched_at DESC' : 'saved_at DESC');
  }

  Future<void> markYouTubeVideoWatched(String videoId) async {
    await (await database).update('space_youtube_videos',
      {'last_watched_at': DateTime.now().toIso8601String()},
      where: 'video_id = ?', whereArgs: [videoId]);
  }

  Future<void> removeYouTubeVideo(String videoId) async {
    await (await database).delete('space_youtube_videos',
      where: 'video_id = ?', whereArgs: [videoId]);
  }

  Future<void> _ensureSectionTables(Database db) async {
    for (final table in ['space_agreements']) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT '',
          party_one TEXT NOT NULL DEFAULT '',
          party_two TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT '',
          start_date TEXT NOT NULL DEFAULT '',
          end_date TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          template_id INTEGER,
          template_title_snapshot TEXT NOT NULL DEFAULT '',
          template_body_snapshot TEXT NOT NULL DEFAULT '',
          label_name TEXT NOT NULL DEFAULT '',
          address TEXT NOT NULL DEFAULT '',
          territory TEXT NOT NULL DEFAULT 'Worldwide',
          term_years TEXT NOT NULL DEFAULT '10',
          track_details TEXT NOT NULL DEFAULT '',
          designation TEXT NOT NULL DEFAULT '',
          agreement_date TEXT NOT NULL DEFAULT '',
          witness_name TEXT NOT NULL DEFAULT '',
          signature_data TEXT NOT NULL DEFAULT '',
          stamp_attachment_id INTEGER,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS space_agreement_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    final templateCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM space_agreement_templates')) ?? 0;
    if (templateCount == 0) {
      await db.insert('space_agreement_templates', {
        'title': 'Music Rights Agreement',
        'body': '''1. This is to certify that I, {{first_party}}, residing at {{address}}, and duly authorized signatory for the content listed in this agreement, authorize {{label_name}} as a Digital Content Partner to distribute and administer the content on national and international platforms for the territories stated below.

2. I am the Artist, producer and copyright owner of the content and the track(s) listed in this agreement. The listed material is my own copyrighted material.

3. No other service provider or party is authorized to sell or offer this content to any platform or claim any rights for the content.

4. I authorize the rights for the track(s) listed below to be distributed and released worldwide.

5. All rights of this content, including Audio/Visual, FM Radio, Cable Network, Television Channel Broadcasting, Publishing, Physical/Digital Formats, Mobile Ring Back Tones (CRBTs) and future formats worldwide, are granted to the Label. No other service provider or party is authorized to sell or offer the content to any platform or claim any rights.

6. I accept that if any rights violations or online disputes are found, I will be responsible for the legal and financial consequences arising from the same.

7. This agreement is valid for {{term_years}} years from the date of signing.''',
        'is_default': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<Map<String, Object?>>> getAgreements() async =>
      (await database).query('space_agreements', orderBy: 'updated_at DESC');

  Future<int> saveAgreement(Map<String, Object?> record) async {
    const table = 'space_agreements';
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final values = <String, Object?>{
      'title': (record['title'] ?? '').toString().trim(),
      'category': (record['category'] ?? '').toString().trim(),
      'party_one': (record['party_one'] ?? '').toString().trim(),
      'party_two': (record['party_two'] ?? '').toString().trim(),
      'status': (record['status'] ?? '').toString().trim(),
      'start_date': (record['start_date'] ?? '').toString().trim(),
      'end_date': (record['end_date'] ?? '').toString().trim(),
      'description': (record['description'] ?? '').toString().trim(),
      'notes': (record['notes'] ?? '').toString().trim(),
      'template_id': record['template_id'],
      'template_title_snapshot': (record['template_title_snapshot'] ?? '').toString(),
      'template_body_snapshot': (record['template_body_snapshot'] ?? '').toString(),
      'label_name': (record['label_name'] ?? '').toString().trim(),
      'address': (record['address'] ?? '').toString().trim(),
      'territory': (record['territory'] ?? 'Worldwide').toString().trim(),
      'term_years': (record['term_years'] ?? '10').toString().trim(),
      'track_details': (record['track_details'] ?? '').toString().trim(),
      'designation': (record['designation'] ?? '').toString().trim(),
      'agreement_date': (record['agreement_date'] ?? '').toString().trim(),
      'witness_name': (record['witness_name'] ?? '').toString().trim(),
      'signature_data': (record['signature_data'] ?? '').toString(),
      'stamp_attachment_id': record['stamp_attachment_id'],
      'updated_at': now,
    };
    if ((values['title'] as String).isEmpty) {
      throw const FormatException('Title is required.');
    }
    final id = record['id'] as int?;
    if (id == null) {
      values['created_at'] = now;
      return await db.insert(table, values);
    } else {
      await db.update(table, values, where: 'id = ?', whereArgs: [id]);
      return id;
    }
  }


  Future<void> deleteAgreement(int id) async {
    await (await database).delete('space_agreements', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> getItems({String? fileType}) async {
    final db = await database;
    return db.query(
      _tableName,
      where: fileType == null ? null : 'file_type = ?',
      whereArgs: fileType == null ? null : [fileType],
      orderBy: 'added_at DESC',
    );
  }

  Future<void> addFile(File source, String originalName) async {
    final extension = p.extension(originalName).toLowerCase();
    const audioExtensions = {'.mp3', '.m4a', '.wav', '.flac'};
    const bookExtensions = {'.pdf', '.epub'};
    const photoExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
    const videoExtensions = {'.mp4', '.m4v', '.mov', '.mkv', '.avi', '.webm', '.3gp'};
    if (!audioExtensions.contains(extension) &&
        !bookExtensions.contains(extension) &&
        !photoExtensions.contains(extension) &&
        !videoExtensions.contains(extension)) {
      throw const FormatException('Supported formats: PDF, EPUB, audio, JPG, PNG, WEBP, GIF, BMP, MP4, MOV, MKV, AVI and WEBM.');
    }
    if (!await source.exists()) throw Exception('Selected file could not be found.');

    final db = await database;
    final destinationDirectory = await filesDirectory;
    final safeName = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(originalName)}';
    final destination = File(p.join(destinationDirectory.path, safeName));

    try {
      final copied = await source.copy(destination.path);
      final fileSize = await copied.length();
      await db.insert(_tableName, {
        'title': p.basenameWithoutExtension(originalName),
        'file_name': originalName,
        'file_path': copied.path,
        'file_type': audioExtensions.contains(extension) ? 'audio' : bookExtensions.contains(extension) ? 'book' : photoExtensions.contains(extension) ? 'photos' : 'videos',
        'file_size': fileSize,
        'added_at': DateTime.now().toIso8601String(),
        'last_page': 1,
        'last_position_ms': 0,
      });
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> getPlaylists() async =>
      (await database).query(_playlistsTable, orderBy: 'name COLLATE NOCASE');

  Future<int> createPlaylist(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const FormatException('Playlist name is required.');
    return (await database).insert(_playlistsTable, {'name': clean, 'created_at': DateTime.now().toIso8601String()});
  }

  Future<void> deletePlaylist(int id) async {
    final db = await database;
    final rows = await db.query(_playlistsTable, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final record = Map<String,dynamic>.from(rows.first);
    final links = await db.query(_playlistItemsTable, where: 'playlist_id = ?', whereArgs: [id]);
    await RecycleBinService.archive(
      type: 'Space Playlist', title: record['name']?.toString() ?? 'Playlist',
      table: 'space_playlists', id: id, record: record,
      related: links.map((e) => Map<String,dynamic>.from(e)).toList(),
    );
    await db.transaction((txn) async {
      await txn.delete(_playlistItemsTable, where: 'playlist_id = ?', whereArgs: [id]);
      await txn.delete(_playlistsTable, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> addItemToPlaylist(int playlistId, int itemId) async {
    await (await database).insert(_playlistItemsTable, {
      'playlist_id': playlistId, 'item_id': itemId, 'added_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> getPlaylistItems(int playlistId) async =>
      (await database).rawQuery('SELECT i.* FROM $_tableName i INNER JOIN $_playlistItemsTable pi ON pi.item_id = i.id WHERE pi.playlist_id = ? ORDER BY pi.added_at DESC', [playlistId]);

  Future<void> removeItemFromPlaylist(int playlistId, int itemId) async {
    await (await database).delete(_playlistItemsTable, where: 'playlist_id = ? AND item_id = ?', whereArgs: [playlistId, itemId]);
  }

  Future<List<Map<String, Object?>>> getCollections() async =>
      (await database).query(_collectionsTable, orderBy: 'name COLLATE NOCASE');

  Future<int> createCollection(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const FormatException('Folder name is required.');
    return (await database).insert(_collectionsTable, {'name': clean, 'created_at': DateTime.now().toIso8601String()});
  }

  Future<void> renameCollection(int id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const FormatException('Folder name is required.');
    await (await database).update(_collectionsTable, {'name': clean}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCollection(int id) async {
    final db = await database;
    final rows = await db.query(_collectionsTable, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final record = Map<String,dynamic>.from(rows.first);
    final links = await db.query(_collectionItemsTable, where: 'collection_id = ?', whereArgs: [id]);
    await RecycleBinService.archive(
      type: 'Space Folder', title: record['name']?.toString() ?? 'Folder',
      table: 'space_collections', id: id, record: record,
      related: links.map((e) => Map<String,dynamic>.from(e)).toList(),
    );
    await db.transaction((txn) async {
      await txn.delete(_collectionItemsTable, where: 'collection_id = ?', whereArgs: [id]);
      await txn.delete(_collectionsTable, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> restoreArchivedSpaceGroup(
    String table, Map<String,dynamic> record, List<Map<String,dynamic>> related,
  ) async {
    final db = await database;
    final isPlaylist = table == 'space_playlists';
    final parentTable = isPlaylist ? _playlistsTable : _collectionsTable;
    final linkTable = isPlaylist ? _playlistItemsTable : _collectionItemsTable;
    final parentKey = isPlaylist ? 'playlist_id' : 'collection_id';
    await db.transaction((txn) async {
      final existing = await txn.query(parentTable, where: 'id = ?', whereArgs: [record['id']], limit: 1);
      if (existing.isNotEmpty) throw StateError('This Space group already exists.');
      await txn.insert(parentTable, record);
      for (final link in related) {
        await txn.insert(linkTable, link);
      }
    });
  }

  Future<void> moveItemToCollection(int itemId, int? collectionId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(_collectionItemsTable, where: 'item_id = ?', whereArgs: [itemId]);
      if (collectionId != null) {
        await txn.insert(_collectionItemsTable, {
          'collection_id': collectionId,
          'item_id': itemId,
          'added_at': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> getCollectionItems(int collectionId) async =>
      (await database).rawQuery(
        'SELECT i.* FROM $_tableName i INNER JOIN $_collectionItemsTable ci ON ci.item_id = i.id WHERE ci.collection_id = ? ORDER BY i.added_at DESC',
        [collectionId],
      );

  Future<Map<String, Object>> getStorageInformation() async {
    final row = await (await database).rawQuery("SELECT COUNT(*) AS total_count, COALESCE(SUM(file_size), 0) AS total_bytes, SUM(CASE WHEN file_type = 'book' THEN 1 ELSE 0 END) AS book_count, SUM(CASE WHEN file_type = 'audio' THEN 1 ELSE 0 END) AS audio_count, SUM(CASE WHEN file_type = 'photos' THEN 1 ELSE 0 END) AS photos_count, SUM(CASE WHEN file_type = 'videos' THEN 1 ELSE 0 END) AS videos_count FROM $_tableName");
    final value = row.first;
    return {
      'total_count': (value['total_count'] as int?) ?? 0,
      'total_bytes': (value['total_bytes'] as int?) ?? 0,
      'book_count': (value['book_count'] as int?) ?? 0,
      'audio_count': (value['audio_count'] as int?) ?? 0,
      'photos_count': (value['photos_count'] as int?) ?? 0,
      'videos_count': (value['videos_count'] as int?) ?? 0,
    };
  }

  Future<void> saveReadingPage(int id, int page) async {
    final db = await database;
    await db.update(
      _tableName,
      {'last_page': page < 1 ? 1 : page},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveEpubPosition(int id, String cfi) async {
    final db = await database;
    await db.update(
      _tableName,
      {'last_epub_cfi': cfi},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveAudioPosition(int id, Duration position) async {
    final db = await database;
    await db.update(
      _tableName,
      {'last_position_ms': position.inMilliseconds < 0 ? 0 : position.inMilliseconds},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteItem(Map<String, Object?> item) async {
    final db = await database;
    final id = item['id'] as int;
    final record = Map<String, dynamic>.from(item);
    // Keep the original media file in Space storage until the central Recycle Bin expires or the user permanently deletes it.
    await RecycleBinService.archive(
      type: 'Space ${item['file_type'] ?? 'media'}',
      title: (item['title'] ?? item['file_name'] ?? 'Space item').toString(),
      table: 'space_items',
      id: id,
      record: record,
    );
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Closes the database before a whole-app backup/restore operation.
  Future<void> closeForBackupOrRestore() async {
    final db = _database;
    _database = null;
    _opening = null;
    if (db != null && db.isOpen) await db.close();
  }

  /// Copies the complete module payload into a caller-owned full-app backup.
  /// The caller is responsible for placing this folder inside the single app backup.
  Future<void> copyIntoFullBackup(Directory backupRoot) async {
    await closeForBackupOrRestore();
    final source = await spaceDirectory;
    final destination = Directory(p.join(backupRoot.path, 'my_space'));
    if (await destination.exists()) await destination.delete(recursive: true);
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: source.path);
      final targetPath = p.join(destination.path, relative);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(targetPath)).create(recursive: true);
        await entity.copy(targetPath);
      }
    }
    // Verify every source file was copied completely before reporting success.
    await for (final entity in source.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relative = p.relative(entity.path, from: source.path);
        final copied = File(p.join(destination.path, relative));
        if (!await copied.exists() || await copied.length() != await entity.length()) {
          throw FileSystemException('Space backup verification failed', copied.path);
        }
      }
    }
  }

  /// Restores the module payload supplied by the full-app restore process.
  Future<void> restoreFromFullBackup(Directory backupRoot) async {
    await closeForBackupOrRestore();
    final source = Directory(p.join(backupRoot.path, 'my_space'));
    if (!await source.exists()) return; // Older backups may not contain a Space.
    final destination = await spaceDirectory;
    final staging = Directory('${destination.path}_restore_tmp');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      await for (final entity in source.list(recursive: true, followLinks: false)) {
        final relative = p.relative(entity.path, from: source.path);
        final targetPath = p.join(staging.path, relative);
        if (entity is Directory) {
          await Directory(targetPath).create(recursive: true);
        } else if (entity is File) {
          await Directory(p.dirname(targetPath)).create(recursive: true);
          await entity.copy(targetPath);
        }
      }
      final previous = Directory('${destination.path}_restore_previous');
      if (await previous.exists()) await previous.delete(recursive: true);
      final hadPrevious = await destination.exists();
      if (hadPrevious) await destination.rename(previous.path);
      try {
        await staging.rename(destination.path);
        if (await previous.exists()) await previous.delete(recursive: true);
      } catch (_) {
        if (await destination.exists()) await destination.delete(recursive: true);
        if (hadPrevious && await previous.exists()) {
          await previous.rename(destination.path);
        }
        rethrow;
      }
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }
}
