import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/installments/services/installment_service.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'my_finance_installment_test_',
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

  Future<int> createWallet(double balance) {
    return FinanceDB.instance.addWallet(
      name: 'Test Wallet',
      type: 'Cash',
      currency: 'PKR',
      openingBalance: balance,
      iconCode: 1,
      excludeTotal: false,
    );
  }

  test('buy contract advance and later payment deduct wallet atomically', () async {
    final walletId = await createWallet(10000);

    final contractId = await InstallmentService.addContract(
      direction: 'buy',
      itemName: 'Laptop',
      partyName: 'Seller',
      totalAmount: 5000,
      advance: 1000,
      walletId: walletId,
      installmentAmount: 1000,
      frequency: 'Monthly',
      startDate: '2026-11-13',
      notes: '',
    );

    expect((await FinanceDB.instance.getWallet(walletId)! )['balance'], 9000);

    await InstallmentService.addPayment(
      contractId: contractId,
      amount: 1000,
      date: '2026-12-13',
      note: 'First installment',
    );

    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect((wallet!['balance'] as num).toDouble(), 8000);
    final contracts = await InstallmentService.getContracts();
    expect((contracts.single['paid_amount'] as num).toDouble(), 2000);
    expect(contracts.single['status'], 'active');
    expect(await InstallmentService.getPayments(contractId), hasLength(2));
  });

  test('overpayment is rejected without changing wallet or contract', () async {
    final walletId = await createWallet(10000);
    final contractId = await InstallmentService.addContract(
      direction: 'buy',
      itemName: 'Phone',
      partyName: 'Seller',
      totalAmount: 3000,
      advance: 500,
      walletId: walletId,
      installmentAmount: 500,
      frequency: 'Monthly',
      startDate: '2026-11-13',
      notes: '',
    );

    await expectLater(
      InstallmentService.addPayment(
        contractId: contractId,
        amount: 2501,
        date: '2026-12-13',
        note: '',
      ),
      throwsA(isA<Exception>()),
    );

    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect((wallet!['balance'] as num).toDouble(), 9500);
    final contract = (await InstallmentService.getContracts()).single;
    expect((contract['paid_amount'] as num).toDouble(), 500);
    expect(await InstallmentService.getPayments(contractId), hasLength(1));
  });

  test('sell contract advance and payment increase wallet', () async {
    final walletId = await createWallet(1000);
    final contractId = await InstallmentService.addContract(
      direction: 'sell',
      itemName: 'Bicycle',
      partyName: 'Buyer',
      totalAmount: 4000,
      advance: 1000,
      walletId: walletId,
      installmentAmount: 1000,
      frequency: 'Monthly',
      startDate: '2026-11-13',
      notes: '',
    );

    await InstallmentService.addPayment(
      contractId: contractId,
      amount: 3000,
      date: '2026-12-13',
      note: 'Final payment',
    );

    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect((wallet!['balance'] as num).toDouble(), 5000);
    final contract = (await InstallmentService.getContracts()).single;
    expect(contract['status'], 'completed');
    expect((contract['paid_amount'] as num).toDouble(), 4000);
  });
}
