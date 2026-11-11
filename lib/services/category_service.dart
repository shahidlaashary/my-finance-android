import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/finance_category.dart';

class CategoryService {
  static Database? _database;
  static Future<Database>? _databaseFuture;

  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    if (_databaseFuture != null) return _databaseFuture!;
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
    final path = await getDatabasesPath();
    return openDatabase('$path/my_finance.db');
  }

  static Future<void> closeDatabase() async {
    final pending = _databaseFuture;
    if (pending != null) { try { await pending; } catch (_) {} }
    final db = _database;
    _database = null;
    _databaseFuture = null;
    if (db != null && db.isOpen) await db.close();
  }

  static String _key(String type) =>
      type.trim().toLowerCase() == 'income' ? 'income_categories' : 'expense_categories';

  static Future<List<FinanceCategory>> getCategories(String type, {int? parentId}) async {
    if (parentId != null) return [];
    final db = await database;
    final rows = await db.query('app_settings', columns: ['setting_value'],
      where: 'setting_key = ?', whereArgs: [_key(type)], limit: 1);
    if (rows.isEmpty) return [];
    try {
      final decoded = jsonDecode((rows.first['setting_value'] ?? '[]').toString());
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);
        return FinanceCategory(
          name: (map['name'] ?? '').toString(),
          type: type.trim().toLowerCase(),
          icon: (map['icon'] ?? 'category').toString(),
        );
      }).where((item) => item.name.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(String type, List<FinanceCategory> categories) async {
    final db = await database;
    final values = categories.map((item) => {
      'name': item.name,
      'icon': int.tryParse(item.icon) ?? 0,
    }).toList();
    await db.insert('app_settings', {
      'setting_key': _key(type),
      'setting_value': jsonEncode(values),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> addCategory(FinanceCategory category) async {
    final items = await getCategories(category.type);
    if (items.any((item) => item.name.toLowerCase() == category.name.toLowerCase())) {
      throw Exception('Category already exists.');
    }
    items.add(category);
    await _save(category.type, items);
    return items.length;
  }

  static Future<int> updateCategory(FinanceCategory category) async {
    final items = await getCategories(category.type);
    final index = items.indexWhere((item) => item.name == category.name);
    if (index < 0) throw Exception('Category not found.');
    items[index] = category;
    await _save(category.type, items);
    return 1;
  }

  static Future<int> deleteCategory(int id) async {
    throw UnsupportedError('Categories are stored by name in app_settings; delete by category name instead.');
  }
}
