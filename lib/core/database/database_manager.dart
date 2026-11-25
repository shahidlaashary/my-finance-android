import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the single SQLite connection for my_finance.db.
///
/// Domain modules keep their own queries and business rules. This class only
/// coordinates opening, sharing, and closing the common database connection.
class DatabaseManager {
  DatabaseManager._();

  static final DatabaseManager instance = DatabaseManager._();

  static const String _databaseName = 'my_finance.db';

  Database? _database;
  Future<Database>? _opening;
  Future<void> Function(Database, int)? _onCreate;

  Future<Database> initialize({
    required Future<void> Function(Database, int) onCreate,
  }) async {
    _onCreate ??= onCreate;

    final current = _database;
    if (current != null && current.isOpen) return current;

    final pending = _opening;
    if (pending != null) return pending;

    final future = _openDatabase(_onCreate!);
    _opening = future;
    try {
      final opened = await future;
      _database = opened;
      return opened;
    } finally {
      if (identical(_opening, future)) _opening = null;
    }
  }

  Future<Database> _openDatabase(
    Future<void> Function(Database, int) onCreate,
  ) async {
    final databasePath = await getDatabasesPath();
    final fullPath = p.join(databasePath, _databaseName);
    return openDatabase(
      fullPath,
      version: 1,
      onCreate: onCreate,
    );
  }

  Database get database {
    final current = _database;
    if (current == null || !current.isOpen) {
      throw StateError(
        'Finance database is not initialized. Call FinanceDB.instance.init() first.',
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

  Future<void> reopen() async {
    final onCreate = _onCreate;
    if (onCreate == null) {
      throw StateError(
        'Finance database has not been initialized before reopen.',
      );
    }
    await initialize(onCreate: onCreate);
  }
}
