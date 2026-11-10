import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Use SQLite FFI so the same database code can run in desktop tests/CI.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    await FinanceDB.instance.init();
  });

  setUp(() async {
    final db = FinanceDB.instance.db;

    // Keep each test independent while preserving the app's required PKR rate.
    await db.delete('transactions');
    await db.delete('wallets');
    await db.delete(
      'exchange_rates',
      where: 'currency != ?',
      whereArgs: ['PKR'],
    );
  });

  group('FinanceDB', () {
    test('initializes the default PKR exchange rate', () async {
      expect(await FinanceDB.instance.getExchangeRate('PKR'), 1.0);
    });

    test('adds a wallet and trims its name', () async {
      final id = await FinanceDB.instance.addWallet(
        name: '  Cash Wallet  ',
        type: 'Cash',
        currency: 'PKR',
        openingBalance: 1250,
        iconCode: 1,
        excludeTotal: false,
      );

      final wallet = await FinanceDB.instance.getWallet(id);

      expect(wallet, isNotNull);
      expect(wallet!['name'], 'Cash Wallet');
      expect(wallet['balance'], 1250);
      expect(wallet['opening_balance'], 1250);
    });

    test('converts wallet balances into PKR for the grand total', () async {
      await FinanceDB.instance.saveExchangeRate('USD', 280);

      await FinanceDB.instance.addWallet(
        name: 'PKR Cash',
        type: 'Cash',
        currency: 'PKR',
        openingBalance: 1000,
        iconCode: 1,
        excludeTotal: false,
      );
      await FinanceDB.instance.addWallet(
        name: 'Dollar Wallet',
        type: 'Bank',
        currency: 'USD',
        openingBalance: 10,
        iconCode: 2,
        excludeTotal: false,
      );

      expect(await FinanceDB.instance.getTotalBalancePKR(), 3800);
    });

    test('does not include wallets marked exclude_total in grand total', () async {
      await FinanceDB.instance.addWallet(
        name: 'Hidden from total',
        type: 'Savings',
        currency: 'PKR',
        openingBalance: 5000,
        iconCode: 1,
        excludeTotal: true,
      );

      expect(await FinanceDB.instance.getTotalBalancePKR(), 0);
    });

    test('rejects invalid exchange rates', () async {
      await expectLater(
        FinanceDB.instance.saveExchangeRate('USD', 0),
        throwsException,
      );
      await expectLater(
        FinanceDB.instance.saveExchangeRate('PKR', 280),
        throwsException,
      );
    });

    test('income and expense totals only sum their own transaction types',
        () async {
      final now = DateTime.now().toIso8601String();
      final db = FinanceDB.instance.db;

      for (final transaction in [
        {'type': 'Income', 'amount': 1500.0},
        {'type': 'Income', 'amount': 500.0},
        {'type': 'Expense', 'amount': 300.0},
        {'type': 'Transfer', 'amount': 900.0},
        {'type': 'Adjustment', 'amount': 100.0},
      ]) {
        await db.insert('transactions', {
          ...transaction,
          'wallet_id': 1,
          'category': 'Test',
          'note': '',
          'date': now,
          'created_at': now,
        });
      }

      expect(await FinanceDB.instance.totalByType('Income'), 2000);
      expect(await FinanceDB.instance.totalByType('Expense'), 300);
    });

    test('prevents deleting a wallet that has linked transactions', () async {
      final walletId = await FinanceDB.instance.addWallet(
        name: 'Linked Wallet',
        type: 'Cash',
        currency: 'PKR',
        openingBalance: 100,
        iconCode: 1,
        excludeTotal: false,
      );

      final now = DateTime.now().toIso8601String();
      await FinanceDB.instance.db.insert('transactions', {
        'type': 'Expense',
        'amount': 10.0,
        'wallet_id': walletId,
        'category': 'Test',
        'note': '',
        'date': now,
        'created_at': now,
      });

      await expectLater(
        FinanceDB.instance.deleteWallet(walletId),
        throwsException,
      );

      expect(await FinanceDB.instance.getWallet(walletId), isNotNull);
    });
  });
}
