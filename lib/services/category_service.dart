
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/finance_category.dart';

class CategoryService {
  static const int _databaseVersion = 3;

  static Database? _database;
  static Future<Database>? _databaseFuture;

  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    if (_databaseFuture != null) {
      return _databaseFuture!;
    }

    final future = _openDatabase();
    _databaseFuture = future;

    try {
      _database = await future;
      return _database!;
    } finally {
      _databaseFuture = null;
    }
  }

  static Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();

    return openDatabase(
      p.join(dbPath, 'my_finance.db'),
      version: _databaseVersion,
      onOpen: (db) async {
        await _ensureCategoryTable(db);
      },
    );
  }

  static Future<void> _ensureCategoryTable(
    DatabaseExecutor db,
  ) async {
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

    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
      AND name = 'transactions'
    ''');

    if (tables.isNotEmpty) {
      final columns = await db.rawQuery(
        'PRAGMA table_info(transactions)',
      );

      final hasCategoryColumn = columns.any(
        (column) => column['name'] == 'category_id',
      );

      if (!hasCategoryColumn) {
        await db.execute(
          'ALTER TABLE transactions ADD COLUMN category_id INTEGER',
        );
      }

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_transactions_category_id
        ON transactions(category_id)
      ''');
    }
  }

  static Future<void> closeDatabase() async {
    final pending = _databaseFuture;

    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }

    final db = _database;
    _database = null;
    _databaseFuture = null;

    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  static Future<int> addCategory(FinanceCategory category) async {
    final db = await database;

    final data = category.toMap()..remove('id');

    data['type'] = (data['type'] as String).trim().toLowerCase();

    return db.insert('finance_categories', data);
  }

  static Future<List<FinanceCategory>> getCategories(
    String type, {
    int? parentId,
  }) async {
    final db = await database;

    final normalizedType = type.trim().toLowerCase();

    final rows = await db.query(
      'finance_categories',
      where: parentId == null
          ? 'LOWER(type) = ? AND parent_id IS NULL AND is_deleted = 0'
          : 'LOWER(type) = ? AND parent_id = ? AND is_deleted = 0',
      whereArgs: parentId == null
          ? [normalizedType]
          : [normalizedType, parentId],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(FinanceCategory.fromMap).toList();
  }

  static Future<int> updateCategory(FinanceCategory category) async {
    final db = await database;

    final data = category.toMap()..remove('id');

    data['type'] = (data['type'] as String).trim().toLowerCase();

    return db.update(
      'finance_categories',
      data,
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

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
