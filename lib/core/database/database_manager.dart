import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Ye class my_finance.db ka aik shared SQLite connection manage karti hai.
///
/// Har module apni queries aur business rules ka zimma khud rakhta hai.
/// Ye class sirf common database connection ko open, share aur close karti hai.
class DatabaseManager {
  DatabaseManager._();

  static final DatabaseManager instance = DatabaseManager._();

  static const String _databaseName = 'my_finance.db';

  Database? _database;
  Future<Database>? _opening;
  Future<void> Function(Database, int)? _onCreate;

  /// Database ko zaroorat par aik hi martaba open karke tamam modules ko deta hai.
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

  /// Fresh install ke liye version 1 database connection kholta hai.
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

  /// Pehle se initialized aur open finance database return karta hai.
  Database get database {
    final current = _database;
    if (current == null || !current.isOpen) {
      throw StateError(
        'Finance database is not initialized. Call FinanceDB.instance.init() first.',
      );
    }
    return current;
  }

  /// Pending open mukammal hone ke baad shared connection band karta hai.
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

  /// Pehle se register schema callback ke sath connection dobara kholta hai.
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
