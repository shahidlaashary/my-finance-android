import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/modules/finance/models/finance_category.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

/// Category operations backed by the application's single FinanceDB connection.
///
/// Categories are stored in app_settings and are shared by the category
/// manager, transaction forms, budgets and recurring transactions.
class CategoryService {
  CategoryService._();

  static List<Map<String, dynamic>> _defaultCategories(String type) {
    final income = [
      {'name': 'Salary', 'icon': Icons.account_balance_wallet_outlined.codePoint},
      {'name': 'Business', 'icon': Icons.business_center_outlined.codePoint},
      {'name': 'Investment', 'icon': Icons.trending_up_outlined.codePoint},
      {'name': 'Gift', 'icon': Icons.card_giftcard_outlined.codePoint},
      {'name': 'Rental Income', 'icon': Icons.home_work_outlined.codePoint},
      {'name': 'Freelance', 'icon': Icons.laptop_mac_outlined.codePoint},
      {'name': 'Interest / Profit', 'icon': Icons.savings_outlined.codePoint},
      {'name': 'Other Income', 'icon': Icons.more_horiz_rounded.codePoint},
    ];
    final expense = [
      {'name': 'Food & Dining', 'icon': Icons.restaurant_outlined.codePoint},
      {'name': 'Transport', 'icon': Icons.directions_car_outlined.codePoint},
      {'name': 'Shopping', 'icon': Icons.shopping_bag_outlined.codePoint},
      {'name': 'Rent / Home', 'icon': Icons.home_outlined.codePoint},
      {'name': 'Bills & Utilities', 'icon': Icons.receipt_long_outlined.codePoint},
      {'name': 'Health', 'icon': Icons.health_and_safety_outlined.codePoint},
      {'name': 'Education', 'icon': Icons.school_outlined.codePoint},
      {'name': 'Clothing', 'icon': Icons.checkroom_outlined.codePoint},
      {'name': 'Mobile & Internet', 'icon': Icons.phone_android_outlined.codePoint},
      {'name': 'Family', 'icon': Icons.people_outline.codePoint},
      {'name': 'Travel', 'icon': Icons.flight_outlined.codePoint},
      {'name': 'Entertainment', 'icon': Icons.movie_outlined.codePoint},
      {'name': 'Charity', 'icon': Icons.volunteer_activism_outlined.codePoint},
      {'name': 'Other Expense', 'icon': Icons.more_horiz_rounded.codePoint},
    ];
    return (type == 'Income' ? income : expense)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> _saveMaps(
    String key,
    List<Map<String, dynamic>> values,
  ) async {
    await DatabaseManager.instance.database.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': jsonEncode(values)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static String _normalizedType(String type) {
    final normalized = type.trim().toLowerCase();
    if (normalized == 'income') return 'Income';
    if (normalized == 'expense') return 'Expense';
    throw ArgumentError.value(type, 'type', 'Expected income or expense.');
  }

  static Future<List<Map<String, dynamic>>> getCategoryMaps(
    String type,
  ) async {
    final normalizedType = _normalizedType(type);
    final key = normalizedType == 'Income'
        ? 'income_categories'
        : 'expense_categories';
    final db = DatabaseManager.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    final raw = rows.isEmpty ? null : rows.first['setting_value']?.toString();
    if (raw == null || raw.isEmpty) {
      final defaults = _defaultCategories(normalizedType);
      await _saveMaps(key, defaults);
      return defaults;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    } catch (_) {
      // Invalid stored data is replaced with the original defaults.
    }

    final defaults = _defaultCategories(normalizedType);
    await _saveMaps(key, defaults);
    return defaults;
  }

  static Future<void> saveCategoryMaps(
    String type,
    List<Map<String, dynamic>> categories,
  ) async {
    final normalizedType = _normalizedType(type);
    final key = normalizedType == 'Income'
        ? 'income_categories'
        : 'expense_categories';
    final values = categories.map((item) => <String, dynamic>{
      'name': (item['name'] ?? '').toString().trim(),
      'icon': item['icon'] is num
          ? (item['icon'] as num).toInt()
          : int.tryParse(item['icon']?.toString() ?? '') ?? 0,
    }).toList();
    await _saveMaps(key, values);
  }

  static Future<List<FinanceCategory>> getCategories(
    String type, {
    int? parentId,
  }) async {
    if (parentId != null) return [];

    final normalizedType = _normalizedType(type);
    final stored = await getCategoryMaps(normalizedType);
    return stored.asMap().entries.map((entry) {
      final value = entry.value;
      final rawIcon = value['icon'];
      final iconCode = rawIcon is num
          ? rawIcon.toInt()
          : int.tryParse(rawIcon?.toString() ?? '') ?? 0;

      return FinanceCategory(
        id: entry.key + 1,
        name: (value['name'] ?? '').toString(),
        type: normalizedType.toLowerCase(),
        icon: iconCode.toString(),
      );
    }).where((item) => item.name.isNotEmpty).toList();
  }

  static Future<void> _save(
    String type,
    List<FinanceCategory> categories,
  ) async {
    final normalizedType = _normalizedType(type);
    final values = categories.map((item) => <String, dynamic>{
      'name': item.name.trim(),
      'icon': int.tryParse(item.icon) ?? 0,
    }).toList();
    final key = normalizedType == 'Income'
        ? 'income_categories'
        : 'expense_categories';
    await _saveMaps(key, values);
  }

  static Future<int> addCategory(FinanceCategory category) async {
    final normalizedType = _normalizedType(category.type);
    final items = await getCategories(normalizedType);
    final name = category.name.trim();

    if (name.isEmpty) {
      throw ArgumentError.value(category.name, 'name', 'Category name is required.');
    }
    if (items.any((item) => item.name.toLowerCase() == name.toLowerCase())) {
      throw Exception('Category already exists.');
    }

    items.add(FinanceCategory(
      name: name,
      type: normalizedType.toLowerCase(),
      icon: category.icon,
    ));
    await _save(normalizedType, items);
    return items.length;
  }

  static Future<int> updateCategory(FinanceCategory category) async {
    final normalizedType = _normalizedType(category.type);
    final items = await getCategories(normalizedType);
    final index = category.id == null ? -1 : category.id! - 1;

    if (index < 0 || index >= items.length) {
      throw Exception('Category not found.');
    }

    final name = category.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(category.name, 'name', 'Category name is required.');
    }
    if (items.asMap().entries.any((entry) =>
        entry.key != index &&
        entry.value.name.toLowerCase() == name.toLowerCase())) {
      throw Exception('Category already exists.');
    }

    items[index] = FinanceCategory(
      id: category.id,
      name: name,
      type: normalizedType.toLowerCase(),
      icon: category.icon,
    );
    await _save(normalizedType, items);
    return 1;
  }

  static Future<int> deleteCategory(
    int id, {
    String type = 'expense',
  }) async {
    final normalizedType = _normalizedType(type);
    final items = await getCategories(normalizedType);
    final index = id - 1;

    if (index < 0 || index >= items.length) return 0;

    final removed = items[index];
    await RecycleBinService.archive(type: 'Category', title: removed.name,
      table: normalizedType == 'Income' ? 'income_categories' : 'expense_categories',
      id: id, record: {'name': removed.name, 'icon': int.tryParse(removed.icon) ?? 0, '_index': index});
    items.removeAt(index);
    await _save(normalizedType, items);
    return 1;
  }
}
