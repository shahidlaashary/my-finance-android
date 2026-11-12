import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/finance_category.dart';
import 'package:my_finance/features/finance/services/category_service.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'my_finance_category_test_',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    await FinanceDB.instance.init();
  });

  tearDown(() async {
    await FinanceDB.instance.close();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('loads default categories through the shared FinanceDB connection',
      () async {
    final income = await CategoryService.getCategories('INCOME');
    final expense = await CategoryService.getCategories('expense');

    expect(income, isNotEmpty);
    expect(expense, isNotEmpty);
    expect(income.every((item) => item.type == 'income'), isTrue);
    expect(expense.every((item) => item.type == 'expense'), isTrue);

    final savedIncome = await FinanceDB.instance.getCategories('Income');
    expect(savedIncome.map((item) => item['name']),
        containsAll(income.map((item) => item.name)));
  });

  test('adds, updates and deletes categories in the shared store', () async {
    await CategoryService.getCategories('expense');

    final addedCount = await CategoryService.addCategory(
      const FinanceCategory(
        name: 'Test Category',
        type: 'expense',
        icon: '12345',
      ),
    );
    expect(addedCount, greaterThan(0));

    var categories = await CategoryService.getCategories('expense');
    final added = categories.singleWhere(
      (item) => item.name == 'Test Category',
    );
    expect(added.icon, '12345');

    await CategoryService.updateCategory(
      FinanceCategory(
        id: added.id,
        name: 'Updated Test Category',
        type: 'expense',
        icon: '54321',
      ),
    );

    categories = await CategoryService.getCategories('expense');
    final updated = categories.singleWhere(
      (item) => item.name == 'Updated Test Category',
    );
    expect(updated.icon, '54321');

    final saved = await FinanceDB.instance.getCategories('Expense');
    expect(saved.map((item) => item['name']),
        contains('Updated Test Category'));

    expect(
      await CategoryService.deleteCategory(updated.id!, type: 'EXPENSE'),
      1,
    );
    categories = await CategoryService.getCategories('expense');
    expect(
      categories.any((item) => item.name == 'Updated Test Category'),
      isFalse,
    );
  });

  test('rejects duplicate category names without adding another item',
      () async {
    await CategoryService.getCategories('income');
    await CategoryService.addCategory(
      const FinanceCategory(
        name: 'Unique Test Income',
        type: 'income',
        icon: '777',
      ),
    );

    await expectLater(
      CategoryService.addCategory(
        const FinanceCategory(
          name: 'unique test income',
          type: 'INCOME',
          icon: '888',
        ),
      ),
      throwsA(isA<Exception>()),
    );

    final matches = (await CategoryService.getCategories('income'))
        .where((item) => item.name.toLowerCase() == 'unique test income');
    expect(matches, hasLength(1));
  });
}
