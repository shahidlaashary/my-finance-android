
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/finance_category.dart';

class CategoryService {
  static Database? _database;
  static Future<Database>? _databaseFuture;

  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    final pendingFuture = _databaseFuture;

    if (pendingFuture != null) {
      return pendingFuture;
    }

    final future = _openDatabase();
    _databaseFuture = future;

    try {
      return await future;
    } catch (_) {
      if (identical(_databaseFuture, future)) {
        _databaseFuture = null;
      }
      rethrow;
    }
  }

  static Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final databasePath = join(dbPath, 'my_finance.db');

    final db = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await _createTable(db);
      },
      onOpen: (db) async {
        await _createTable(db);
      },
    );

    _database = db;
    return db;
  }

  static Future<void> closeDatabase() async {
    final pendingFuture = _databaseFuture;

    if (pendingFuture != null) {
      try {
        await pendingFuture;
      } catch (_) {}
    }

    final currentDatabase = _database;
    _database = null;

    if (currentDatabase != null && currentDatabase.isOpen) {
      await currentDatabase.close();
    }

    _databaseFuture = null;
  }

  static Future<void> _createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS finance_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT 'category',
        parent_id INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<int> addCategory(FinanceCategory category) async {
    final db = await database;

    return db.insert(
      'finance_categories',
      category.toMap()..remove('id'),
    );
  }

  static Future<List<FinanceCategory>> getCategories(
    String type, {
    int? parentId,
  }) async {
    final db = await database;

    final rows = await db.query(
      'finance_categories',
      where: parentId == null
          ? 'type = ? AND parent_id IS NULL AND is_deleted = 0'
          : 'type = ? AND parent_id = ? AND is_deleted = 0',
      whereArgs: parentId == null ? [type] : [type, parentId],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(FinanceCategory.fromMap).toList();
  }

  static Future<int> updateCategory(FinanceCategory category) async {
    final db = await database;

    return db.update(
      'finance_categories',
      category.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  // Soft delete: historical records remain protected.
  static Future<int> deleteCategory(int id) async {
    final db = await database;

    return db.update(
      'finance_categories',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
