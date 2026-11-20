import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// My Library owns its database and files, independently from finance data.
class MyLibraryService {
  MyLibraryService._();
  static final MyLibraryService instance = MyLibraryService._();

  Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    final appDir = await getApplicationDocumentsDirectory();
    final libraryDir = Directory(p.join(appDir.path, 'my_library'));
    await libraryDir.create(recursive: true);
    _database = await openDatabase(
      p.join(libraryDir.path, 'my_library.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE library_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            file_name TEXT NOT NULL,
            file_path TEXT NOT NULL,
            file_type TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            added_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<List<Map<String, Object?>>> getItems() async {
    final db = await database;
    return db.query('library_items', orderBy: 'added_at DESC');
  }

  Future<void> addFile(File source, String originalName) async {
    final db = await database;
    final extension = p.extension(originalName).toLowerCase();
    final audioExtensions = {'.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac'};
    final documentExtensions = {'.pdf', '.epub'};
    if (!audioExtensions.contains(extension) &&
        !documentExtensions.contains(extension)) {
      throw const FormatException('Only PDF, EPUB and common audio files are supported.');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final filesDir = Directory(p.join(appDir.path, 'my_library', 'files'));
    await filesDir.create(recursive: true);
    final safeName = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(originalName)}';
    final destination = await source.copy(p.join(filesDir.path, safeName));
    await db.insert('library_items', {
      'title': p.basenameWithoutExtension(originalName),
      'file_name': originalName,
      'file_path': destination.path,
      'file_type': audioExtensions.contains(extension) ? 'audio' : 'book',
      'file_size': await destination.length(),
      'added_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteItem(Map<String, Object?> item) async {
    final db = await database;
    final id = item['id'] as int;
    final filePath = item['file_path'] as String;
    final file = File(filePath);
    if (await file.exists()) await file.delete();
    await db.delete('library_items', where: 'id = ?', whereArgs: [id]);
  }
}
