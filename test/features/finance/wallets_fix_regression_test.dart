import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/recurring_transaction_model.dart';
import 'package:my_finance/features/finance/services/recurring_transaction_service.dart';

void main() {
  late Directory databaseDirectory;
  final recurring = RecurringTransactionService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp('wallets_fix_test_');
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    await FinanceDB.instance.init();
  });

  tearDown(() async {
    await RecurringTransactionService.closeDatabase();
    await FinanceDB.instance.close();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  Future<int> wallet(String name, String currency, double balance) {
    return FinanceDB.instance.addWallet(
      name: name,
      type: 'Bank',
      currency: currency,
      openingBalance: balance,
      iconCode: 1,
      excludeTotal: false,
    );
  }

  Future<void> setRate(String currency, double rate) {
    return FinanceDB.instance.saveExchangeRate(currency, rate);
  }

  RecurringTransactionModel schedule({
    required int walletId,
    int? toWalletId,
    String type = 'Income',
    double amount = 10,
    double fee = 0,
  }) {
    final date = DateTime(2026, 12, 1);
    return RecurringTransactionModel(
      title: 'Wallet regression schedule',
      type: type,
      amount: amount,
      transferFee: fee,
      walletId: walletId,
      toWalletId: toWalletId,
      frequency: 'Monthly',
      startDate: date,
      nextRunDate: date,
    );
  }

  test('rejects non-finite opening balances at database boundary', () async {
    await expectLater(
      wallet('Invalid wallet', 'PKR', double.nan),
      throwsA(isA<Exception>()),
    );
    expect(await FinanceDB.instance.getWallets(), isEmpty);
  });

  test('rejects non-finite current balance while editing wallet', () async {
    final id = await wallet('Cash', 'PKR', 500);
    await expectLater(
      FinanceDB.instance.updateWallet(
        id: id,
        name: 'Cash',
        type: 'Bank',
        currency: 'PKR',
        requestedCurrentBalance: double.infinity,
        iconCode: 1,
        excludeTotal: false,
      ),
      throwsA(isA<Exception>()),
    );
    expect((await FinanceDB.instance.getWallet(id))!['balance'], 500);
  });

  test('does not silently omit a wallet when its exchange rate is missing', () async {
    await wallet('Foreign', 'EUR', 100);
    await expectLater(
      FinanceDB.instance.getTotalBalanceInBaseCurrency(),
      throwsA(isA<Exception>()),
    );
  });

  test('converts recurring income amount and fee when wallet currency changes', () async {
    final id = await wallet('USD', 'USD', 100);
    await setRate('USD', 280);
    await recurring.addRecurringTransaction(schedule(walletId: id, amount: 12));

    await FinanceDB.instance.updateWallet(
      id: id,
      name: 'PKR Wallet',
      type: 'Bank',
      currency: 'PKR',
      requestedCurrentBalance: 28000,
      iconCode: 1,
      excludeTotal: false,
    );

    final schedules = await recurring.getRecurringTransactions();
    expect(schedules.single.amount, closeTo(3360, 0.001));
  });

  test('blocks deleting a wallet referenced by a recurring schedule', () async {
    final id = await wallet('Cash', 'PKR', 500);
    await recurring.addRecurringTransaction(schedule(walletId: id));

    await expectLater(
      FinanceDB.instance.deleteWallet(id),
      throwsA(isA<Exception>()),
    );
    expect(await FinanceDB.instance.getWallet(id), isNotNull);
  });

  test('blocks currency changes for a wallet linked to recurring transfer', () async {
    final source = await wallet('USD source', 'USD', 100);
    final destination = await wallet('USD destination', 'USD', 100);
    await setRate('USD', 280);
    await recurring.addRecurringTransaction(
      schedule(walletId: source, toWalletId: destination, type: 'Transfer'),
    );

    await expectLater(
      FinanceDB.instance.updateWallet(
        id: source,
        name: 'PKR source',
        type: 'Bank',
        currency: 'PKR',
        requestedCurrentBalance: 28000,
        iconCode: 1,
        excludeTotal: false,
      ),
      throwsA(isA<Exception>()),
    );
    expect((await FinanceDB.instance.getWallet(source))!['currency'], 'USD');
  });

  test('converts committee rollback delta and linked entry wallet amount', () async {
    final id = await wallet('USD', 'USD', 100);
    await setRate('USD', 280);
    final db = FinanceDB.instance.db;
    await db.execute('''
      CREATE TABLE committee_entries (
        id INTEGER PRIMARY KEY,
        wallet_id INTEGER NOT NULL,
        wallet_amount REAL NOT NULL,
        wallet_currency TEXT NOT NULL
      )
    ''');
    await db.insert('transactions', {
      'type': 'Transfer',
      'amount': 20.0,
      'wallet_id': id,
      'to_wallet_id': null,
      'to_amount': null,
      'exchange_rate': null,
      'balance_delta': -20.0,
      'category': 'Committee Transfer',
      'note': 'Committee entry',
      'date': DateTime(2026, 11, 1).toIso8601String(),
      'created_at': DateTime(2026, 11, 1).toIso8601String(),
    });
    await db.insert('committee_entries', {
      'id': 1,
      'wallet_id': id,
      'wallet_amount': 20.0,
      'wallet_currency': 'USD',
    });

    await FinanceDB.instance.updateWallet(
      id: id,
      name: 'PKR',
      type: 'Bank',
      currency: 'PKR',
      requestedCurrentBalance: 28000,
      iconCode: 1,
      excludeTotal: false,
    );

    final transaction = (await db.query(
      'transactions',
      where: "category = 'Committee Transfer'",
    )).single;
    final entry = (await db.query('committee_entries')).single;
    expect((transaction['amount'] as num).toDouble(), closeTo(5600, 0.001));
    expect((transaction['balance_delta'] as num).toDouble(), closeTo(-5600, 0.001));
    expect((entry['wallet_amount'] as num).toDouble(), closeTo(5600, 0.001));
    expect(entry['wallet_currency'], 'PKR');
  });
}
