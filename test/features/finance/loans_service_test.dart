import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/models/repayment_model.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp('my_finance_loans_test_');
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    await FinanceDB.instance.init();
  });

  tearDown(() async {
    await LoansService.closeDatabase();
    await FinanceDB.instance.close();
    if (await databaseDirectory.exists()) await databaseDirectory.delete(recursive: true);
  });

  Future<int> wallet(double opening) => FinanceDB.instance.addWallet(
    name: 'Loan Test Wallet', type: 'Cash', currency: 'PKR',
    openingBalance: opening, iconCode: 1, excludeTotal: false,
  );

  LoansModel loanModel(int walletId, double amount) => LoansModel(
    borrowerName: 'Test Borrower', borrowerPhone: '', amount: amount,
    remainingAmount: amount, walletId: walletId,
    lendingDate: DateTime(2026, 11, 13).toIso8601String(), dueDate: null,
    notes: '', status: 'active', createdAt: DateTime(2026, 11, 13).toIso8601String(),
  );

  test('loan and repayment change balances and outstanding correctly', () async {
    final walletId = await wallet(10000);
    final loanId = await LoansService.addLoan(loanModel(walletId, 3000));
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 7000);

    await LoansService.addRepayment(RepaymentModel(
      loanId: loanId, amount: 1000, walletId: walletId,
      repaymentDate: DateTime(2026, 11, 20).toIso8601String(), paymentMethod: 'cash',
      notes: '', createdAt: DateTime(2026, 11, 20).toIso8601String(),
    ));
    final loan = await LoansService.getLoanById(loanId);
    expect(loan!.remainingAmount, 2000);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 8000);
  });

  test('repayment cannot exceed outstanding amount', () async {
    final walletId = await wallet(10000);
    final loanId = await LoansService.addLoan(loanModel(walletId, 1000));
    await expectLater(
      LoansService.addRepayment(RepaymentModel(
        loanId: loanId, amount: 1001, walletId: walletId,
        repaymentDate: DateTime(2026, 11, 20).toIso8601String(), paymentMethod: 'cash',
        notes: '', createdAt: DateTime(2026, 11, 20).toIso8601String(),
      )),
      throwsA(isA<Exception>()),
    );
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 9000);
    expect((await LoansService.getLoanById(loanId))!.remainingAmount, 1000);
    expect(await LoansService.getRepayments(loanId), isEmpty);
  });

  test('deleting repayment reverses its wallet and loan effects', () async {
    final walletId = await wallet(10000);
    final loanId = await LoansService.addLoan(loanModel(walletId, 3000));
    final repaymentId = await LoansService.addRepayment(RepaymentModel(
      loanId: loanId, amount: 1000, walletId: walletId,
      repaymentDate: DateTime(2026, 11, 20).toIso8601String(), paymentMethod: 'cash',
      notes: '', createdAt: DateTime(2026, 11, 20).toIso8601String(),
    ));
    await LoansService.deleteRepayment(repaymentId);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 7000);
    expect((await LoansService.getLoanById(loanId))!.remainingAmount, 3000);
    expect(await LoansService.getRepayments(loanId), isEmpty);
  });

  test('deleting loan reverses original loan and all repayments', () async {
    final walletId = await wallet(10000);
    final loanId = await LoansService.addLoan(loanModel(walletId, 3000));
    await LoansService.addRepayment(RepaymentModel(
      loanId: loanId, amount: 1000, walletId: walletId,
      repaymentDate: DateTime(2026, 11, 20).toIso8601String(), paymentMethod: 'cash',
      notes: '', createdAt: DateTime(2026, 11, 20).toIso8601String(),
    ));
    await LoansService.deleteLoan(loanId);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 10000);
    expect(await LoansService.getLoanById(loanId), isNull);
  });
}
