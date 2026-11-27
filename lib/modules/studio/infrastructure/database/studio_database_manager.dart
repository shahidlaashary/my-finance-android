import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'studio_database_schema.dart';

/// Owns the independent studio.db SQLite connection.
class StudioDatabaseManager {
  StudioDatabaseManager._();

  static final StudioDatabaseManager instance = StudioDatabaseManager._();

  static const String databaseName = 'studio.db';

  Database? _database;
  Future<Database>? _opening;

  Future<Database> initialize() async {
    final current = _database;
    if (current != null && current.isOpen) return current;

    final pending = _opening;
    if (pending != null) return pending;

    final opening = _openDatabase();
    _opening = opening;
    try {
      final database = await opening;
      _database = database;
      return database;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<Database> _openDatabase() async {
    final databaseDirectory = await getDatabasesPath();
    final databasePath = p.join(databaseDirectory, databaseName);

    return openDatabase(
      databasePath,
      version: StudioDatabaseSchema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: StudioDatabaseSchema.create,
    );
  }

  Database get database {
    final current = _database;
    if (current == null || !current.isOpen) {
      throw StateError(
        'Studio database is not initialized. '
        'Call StudioDatabaseManager.instance.initialize() first.',
      );
    }
    return current;
  }

  Future<void> close() async {
    final pending = _opening;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A failed open has no live connection to close.
      }
    }

    final current = _database;
    _database = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
  }
}
