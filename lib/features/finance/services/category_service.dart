import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/finance_category.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

/// Category operations backed by the application's single FinanceDB connection.
///
/// Categories are stored in app_settings and are shared by the category
/// manager, transaction forms, budgets and recurring transactions.
class CategoryService {
  CategoryService._();

  static String _normalizedType(String type) {
    final normalized = type.trim().toLowerCase();
    if (normalized == 'income') return 'Income';
    if (normalized == 'expense') return 'Expense';
    throw ArgumentError.value(type, 'type', 'Expected income or expense.');
  }

  static Future<void> closeDatabase() async {
    // FinanceDB owns the shared connection and is closed by the restore flow.
  }

  static Future<List<FinanceCategory>> getCategories(
    String type, {
    int? parentId,
  }) async {
    if (parentId != null) return [];

    final normalizedType = _normalizedType(type);
    final stored = await FinanceDB.instance.getCategories(normalizedType);

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
    final values = categories.map((item) {
      return <String, dynamic>{
        'name': item.name.trim(),
        'icon': int.tryParse(item.icon) ?? 0,
      };
    }).toList();

    await FinanceDB.instance.saveCategories(normalizedType, values);
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
