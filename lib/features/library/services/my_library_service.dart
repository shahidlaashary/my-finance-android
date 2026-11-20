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
      version: 2,
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
      },
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
      await destination.delete(recursive: true);
      await staging.rename(destination.path);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }
}
