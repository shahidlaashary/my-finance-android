import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'my_finance_transactions_test_',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    await FinanceDB.instance.init();
  });

  tearDown(() async {
    // Dono database connections band kar ke temporary test data saaf karte hain.
    await TransactionsService.closeDatabase();
    await FinanceDB.instance.close();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  Future<int> createWallet(String name, String currency, double balance) {
    return FinanceDB.instance.addWallet(
      name: name,
      type: 'Cash',
      currency: currency,
      openingBalance: balance,
      iconCode: 1,
      excludeTotal: false,
    );
  }

  test('editing cross-currency transfer keeps received amount and recalculates balances', () async {
    final sourceId = await createWallet('USD Wallet', 'USD', 1000);
    final destinationId = await createWallet('PKR Wallet', 'PKR', 0);

    final transactionId = await TransactionsService.addTransaction(
      type: 'Transfer',
      amount: 100,
      walletId: sourceId,
      toWalletId: destinationId,
      toAmount: 28000,
      note: 'Initial transfer',
      date: DateTime(2026, 11, 13).toIso8601String(),
    );

    await TransactionsService.updateTransaction(
      id: transactionId,
      type: 'Transfer',
      amount: 120,
      walletId: sourceId,
      toWalletId: destinationId,
      toAmount: 33600,
      exchangeRate: 280,
      note: 'Updated transfer',
      date: DateTime(2026, 11, 13).toIso8601String(),
    );

    final source = await FinanceDB.instance.getWallet(sourceId);
    final destination = await FinanceDB.instance.getWallet(destinationId);
    final record = (await TransactionsService.getTransactions())
        .singleWhere((item) => item['id'] == transactionId);

    expect((source!['balance'] as num).toDouble(), closeTo(880, 0.001));
    expect((destination!['balance'] as num).toDouble(), closeTo(33600, 0.001));
    expect((record['amount'] as num).toDouble(), 120);
    expect((record['to_amount'] as num).toDouble(), 33600);
    expect((record['exchange_rate'] as num).toDouble(), 280);
    expect(record['note'], 'Updated transfer');
  });

  test('same-currency transfer cannot save a different received amount', () async {
    final sourceId = await createWallet('Source PKR', 'PKR', 1000);
    final destinationId = await createWallet('Destination PKR', 'PKR', 100);

    await expectLater(
      TransactionsService.addTransaction(
        type: 'Transfer',
        amount: 100,
        walletId: sourceId,
        toWalletId: destinationId,
        toAmount: 95,
        note: 'Invalid transfer',
        date: DateTime(2026, 11, 13).toIso8601String(),
      ),
      throwsA(isA<Exception>()),
    );

    final source = await FinanceDB.instance.getWallet(sourceId);
    final destination = await FinanceDB.instance.getWallet(destinationId);
    expect((source!['balance'] as num).toDouble(), 1000);
    expect((destination!['balance'] as num).toDouble(), 100);
    expect(await TransactionsService.getTransactions(), isEmpty);
  });
}
