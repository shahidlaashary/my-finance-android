import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Independent local data store for My Library.
/// Finance database and finance records are never opened or modified here.
class MyLibraryService {
  MyLibraryService._();
  static final MyLibraryService instance = MyLibraryService._();

  static const _databaseName = 'my_library.db';
  static const _tableName = 'library_items';
  static const _playlistsTable = 'library_playlists';
  static const _playlistItemsTable = 'library_playlist_items';
  static const _collectionsTable = 'library_collections';

  Database? _database;
  Future<Database>? _opening;

  Future<Directory> get libraryDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(appDir.path, 'my_library'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> get filesDirectory async {
    final directory = Directory(p.join((await libraryDirectory).path, 'files'));
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
    final directory = await libraryDirectory;
    final db = await openDatabase(
      p.join(directory.path, _databaseName),
      version: 3,
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
            last_position_ms INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE TABLE $_playlistsTable (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE $_playlistItemsTable (playlist_id INTEGER NOT NULL, item_id INTEGER NOT NULL, added_at TEXT NOT NULL, PRIMARY KEY (playlist_id, item_id), FOREIGN KEY (playlist_id) REFERENCES $_playlistsTable(id) ON DELETE CASCADE, FOREIGN KEY (item_id) REFERENCES $_tableName(id) ON DELETE CASCADE)');
        await db.execute('CREATE TABLE $_collectionsTable (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)');
        await db.execute('ALTER TABLE $_tableName ADD COLUMN collection_id INTEGER');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN last_page INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN last_position_ms INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute('CREATE TABLE $_playlistsTable (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)');
          await db.execute('CREATE TABLE $_playlistItemsTable (playlist_id INTEGER NOT NULL, item_id INTEGER NOT NULL, added_at TEXT NOT NULL, PRIMARY KEY (playlist_id, item_id), FOREIGN KEY (playlist_id) REFERENCES $_playlistsTable(id) ON DELETE CASCADE, FOREIGN KEY (item_id) REFERENCES $_tableName(id) ON DELETE CASCADE)');
          await db.execute('CREATE TABLE $_collectionsTable (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)');
          await db.execute('ALTER TABLE $_tableName ADD COLUMN collection_id INTEGER');
          await db.execute('CREATE INDEX idx_library_items_collection ON $_tableName(collection_id)');
        }
      },
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
    _database = db;
    return db;
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
    const audioExtensions = {'.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac'};
    const bookExtensions = {'.pdf', '.epub'};
    if (!audioExtensions.contains(extension) && !bookExtensions.contains(extension)) {
      throw const FormatException('Supported formats: PDF, EPUB, MP3, M4A, AAC, WAV, OGG and FLAC.');
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
        'file_type': audioExtensions.contains(extension) ? 'audio' : 'book',
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
    await db.transaction((txn) async {
      await txn.update(_tableName, {'collection_id': null}, where: 'collection_id = ?', whereArgs: [id]);
      await txn.delete(_collectionsTable, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> moveItemToCollection(int itemId, int? collectionId) async {
    await (await database).update(_tableName, {'collection_id': collectionId}, where: 'id = ?', whereArgs: [itemId]);
  }

  Future<List<Map<String, Object?>>> getCollectionItems(int collectionId) async =>
      (await database).query(_tableName, where: 'collection_id = ?', whereArgs: [collectionId], orderBy: 'added_at DESC');

  Future<Map<String, Object>> getStorageInformation() async {
    final row = (await database).rawQuery("SELECT COUNT(*) AS total_count, COALESCE(SUM(file_size), 0) AS total_bytes, SUM(CASE WHEN file_type = 'book' THEN 1 ELSE 0 END) AS book_count, SUM(CASE WHEN file_type = 'audio' THEN 1 ELSE 0 END) AS audio_count FROM $_tableName");
    final value = row.first;
    return {
      'total_count': (value['total_count'] as int?) ?? 0,
      'total_bytes': (value['total_bytes'] as int?) ?? 0,
      'book_count': (value['book_count'] as int?) ?? 0,
      'audio_count': (value['audio_count'] as int?) ?? 0,
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
    final filePath = item['file_path'] as String;
    await db.transaction((txn) async {
      await txn.delete(_tableName, where: 'id = ?', whereArgs: [id]);
    });
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Metadata is removed; an orphaned file can be cleaned up later.
    }
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
    final source = await libraryDirectory;
    final destination = Directory(p.join(backupRoot.path, 'my_library'));
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
          throw FileSystemException('Library backup verification failed', copied.path);
        }
      }
    }
  }

  /// Restores the module payload supplied by the full-app restore process.
  Future<void> restoreFromFullBackup(Directory backupRoot) async {
    await closeForBackupOrRestore();
    final source = Directory(p.join(backupRoot.path, 'my_library'));
    if (!await source.exists()) return; // Older backups may not contain a Library.
    final destination = await libraryDirectory;
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
