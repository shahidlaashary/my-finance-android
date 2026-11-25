import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/models/repayment_model.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  final assets = AssetsService();

  setUpAll(() {
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return Directory.systemTemp.path;
      }
      throw MissingPluginException('Unsupported path_provider method: ${call.method}');
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'my_finance_assets_test_',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    await FinanceDB.instance.init();
  });

  tearDown(() async {
    await TransactionsService.closeDatabase();
    await LoansService.closeDatabase();
    await FinanceDB.instance.close();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  Future<int> createWallet(double balance) => FinanceDB.instance.addWallet(
        name: 'Asset Test Wallet',
        type: 'Cash',
        currency: 'PKR',
        openingBalance: balance,
        iconCode: 1,
        excludeTotal: false,
      );

  AssetsModel asset({
    required String name,
    required double price,
    required int walletId,
    String paymentType = 'Wallet',
    int? partyId,
  }) =>
      AssetsModel(
        name: name,
        category: 'Other',
        purchasePrice: price,
        currentValue: price,
        purchaseDate: DateTime(2026, 11, 1),
        walletId: walletId,
        paymentType: paymentType,
        partyId: partyId,
        currency: 'PKR',
      );

  test('loan-funded asset purchase works without any wallet', () async {
    final partyId = await LoansService.addParty(
      name: 'Asset Seller',
      currency: 'PKR',
    );

    final assetId = await assets.addAssetWithAttachments(
      asset(
        name: 'Credit Purchased Asset',
        price: 500,
        walletId: 0,
        paymentType: 'Loan',
        partyId: partyId,
      ),
      const [],
    );

    final saved = await assets.getAssetById(assetId);
    final loans = await LoansService.getLoans();
    final walletRows = await FinanceDB.instance.db.query('wallets');

    expect(saved, isNotNull);
    expect(saved!.paymentType.toLowerCase(), 'loan');
    expect(saved.walletId, 0);
    expect(saved.linkedLoanId, isNotNull);
    expect(loans, hasLength(1));
    expect(loans.single.loanType, 'taken');
    expect(loans.single.partyId, partyId);
    expect(loans.single.amount, 500);
    expect(loans.single.remainingAmount, 500);
    expect(walletRows, isEmpty);
  });

  test('credit asset sale creates receivable and repayments credit wallet', () async {
    final walletId = await createWallet(1000);
    final buyerId = await LoansService.addParty(
      name: 'Asset Buyer',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Wallet Purchased Asset', price: 400, walletId: walletId),
      const [],
    );

    final afterPurchase = await FinanceDB.instance.getWallet(walletId);
    expect((afterPurchase!['balance'] as num).toDouble(), 600);

    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: 0,
      paymentType: 'Loan',
      partyId: buyerId,
      walletAmount: 0,
      walletCurrency: 'PKR',
    );

    final sold = await assets.getAssetById(assetId);
    final saleLoan = (await LoansService.getLoans())
        .singleWhere((loan) => loan.sourceType == 'asset_sale');
    expect(sold!.isSold, isTrue);
    expect(sold.saleLinkedLoanId, saleLoan.id);
    expect(saleLoan.loanType, 'given');
    expect(saleLoan.remainingAmount, 500);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 600);

    await LoansService.addRepayment(
      RepaymentModel(
        loanId: saleLoan.id!,
        amount: 200,
        walletId: walletId,
        repaymentDate: '2026-11-11',
        createdAt: DateTime(2026, 11, 11).toIso8601String(),
      ),
    );

    final afterRepayment = await FinanceDB.instance.getWallet(walletId);
    final updatedLoan = await LoansService.getLoanById(saleLoan.id!);
    expect((afterRepayment!['balance'] as num).toDouble(), 800);
    expect(updatedLoan!.remainingAmount, 300);
  });

  test('deleting credit-sale repayment is blocked when received funds were spent', () async {
    final walletId = await createWallet(1000);
    final buyerId = await LoansService.addParty(
      name: 'Repayment Delete Buyer',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Credit Sale Repayment Asset', price: 400, walletId: walletId),
      const [],
    );
    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: 0,
      paymentType: 'Loan',
      partyId: buyerId,
      walletAmount: 0,
      walletCurrency: 'PKR',
    );
    final loan = (await LoansService.getLoans())
        .singleWhere((entry) => entry.sourceType == 'asset_sale');
    final repaymentId = await LoansService.addRepayment(
      RepaymentModel(
        loanId: loan.id!,
        amount: 200,
        walletId: walletId,
        repaymentDate: '2026-11-11',
        createdAt: DateTime(2026, 11, 11).toIso8601String(),
      ),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'balance': 50},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      LoansService.deleteRepayment(repaymentId),
      throwsA(isA<Exception>()),
    );

    final savedLoan = await LoansService.getLoanById(loan.id!);
    final savedRepayments = await LoansService.getRepayments(loan.id!);
    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect(savedLoan!.remainingAmount, 300);
    expect(savedRepayments, hasLength(1));
    expect((wallet!['balance'] as num).toDouble(), 50);
  });

  test('updating a repayment validates the combined wallet reversal and replacement', () async {
    final walletId = await createWallet(1000);
    final buyerId = await LoansService.addParty(
      name: 'Repayment Update Buyer',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Credit Sale Update Asset', price: 400, walletId: walletId),
      const [],
    );
    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: 0,
      paymentType: 'Loan',
      partyId: buyerId,
      walletAmount: 0,
      walletCurrency: 'PKR',
    );
    final loan = (await LoansService.getLoans())
        .singleWhere((entry) => entry.sourceType == 'asset_sale');
    final repaymentId = await LoansService.addRepayment(
      RepaymentModel(
        loanId: loan.id!,
        amount: 200,
        walletId: walletId,
        repaymentDate: '2026-11-11',
        createdAt: DateTime(2026, 11, 11).toIso8601String(),
      ),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'balance': 50},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await LoansService.updateRepayment(
      RepaymentModel(
        id: repaymentId,
        loanId: loan.id!,
        amount: 150,
        walletId: walletId,
        repaymentDate: '2026-11-12',
        createdAt: DateTime(2026, 11, 12).toIso8601String(),
      ),
    );

    final updatedLoan = await LoansService.getLoanById(loan.id!);
    final updatedRepayments = await LoansService.getRepayments(loan.id!);
    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect(updatedLoan!.remainingAmount, 350);
    expect(updatedRepayments.single.amount, 150);
    expect((wallet!['balance'] as num).toDouble(), 0);
  });

  test('updating asset-purchase repayment uses net wallet effect for Loan Taken', () async {
    final walletId = await createWallet(1000);
    final sellerId = await LoansService.addParty(
      name: 'Purchase Repayment Update Seller',
      currency: 'PKR',
    );
    await assets.addAssetWithAttachments(
      asset(
        name: 'Credit Purchase Repayment Update Asset',
        price: 500,
        walletId: 0,
        paymentType: 'Loan',
        partyId: sellerId,
      ),
      const [],
    );
    final loan = (await LoansService.getLoans()).single;
    final repaymentId = await LoansService.addRepayment(
      RepaymentModel(
        loanId: loan.id!,
        amount: 200,
        walletId: walletId,
        repaymentDate: '2026-11-11',
        createdAt: DateTime(2026, 11, 11).toIso8601String(),
      ),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'balance': 50},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await LoansService.updateRepayment(
      RepaymentModel(
        id: repaymentId,
        loanId: loan.id!,
        amount: 250,
        walletId: walletId,
        repaymentDate: '2026-11-12',
        createdAt: DateTime(2026, 11, 12).toIso8601String(),
      ),
    );

    final updatedLoan = await LoansService.getLoanById(loan.id!);
    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect(updatedLoan!.remainingAmount, 250);
    expect((wallet!['balance'] as num).toDouble(), 0);
  });

  test('deleting sold asset is blocked if reversing sale would make wallet negative', () async {
    final walletId = await createWallet(1000);
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Spent Sale Proceeds Asset', price: 400, walletId: walletId),
      const [],
    );

    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: walletId,
      paymentType: 'Wallet',
      walletAmount: 500,
      walletCurrency: 'PKR',
    );

    await FinanceDB.instance.db.update(
      'wallets',
      {'balance': 50},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      assets.deleteAsset(assetId),
      throwsA(isA<Exception>()),
    );

    final saved = await assets.getAssetById(assetId);
    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect(saved, isNotNull);
    expect(saved!.isSold, isTrue);
    expect((wallet!['balance'] as num).toDouble(), 50);
  });


  test('deleting a loan is blocked if reversing repayments would make a wallet negative', () async {
    final lendingWalletId = await createWallet(1000);
    final repaymentWalletId = await FinanceDB.instance.addWallet(
      name: 'Repayment Test Wallet',
      type: 'Cash',
      currency: 'PKR',
      openingBalance: 100,
      iconCode: 1,
      excludeTotal: false,
    );
    final partyId = await LoansService.addParty(
      name: 'Ordinary Loan Delete Party',
      currency: 'PKR',
    );
    final loanId = await LoansService.addLoan(
      LoansModel(
        partyId: partyId,
        loanType: 'given',
        amount: 500,
        remainingAmount: 500,
        walletId: lendingWalletId,
        currency: 'PKR',
        lendingDate: '2026-11-20',
        createdAt: DateTime(2026, 11, 20).toIso8601String(),
      ),
    );
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 200,
        walletId: repaymentWalletId,
        repaymentDate: '2026-11-21',
        createdAt: DateTime(2026, 11, 21).toIso8601String(),
      ),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'balance': 100},
      where: 'id = ?',
      whereArgs: [repaymentWalletId],
    );

    await expectLater(
      LoansService.deleteLoan(loanId),
      throwsA(isA<Exception>()),
    );

    expect(await LoansService.getLoanById(loanId), isNotNull);
    expect(await LoansService.getRepayments(loanId), hasLength(1));
    expect(
      (await FinanceDB.instance.getWallet(lendingWalletId))!['balance'],
      500,
    );
    expect(
      (await FinanceDB.instance.getWallet(repaymentWalletId))!['balance'],
      100,
    );
  });



  test('reducing Loan Taken amount is blocked if wallet cannot reverse the credit', () async {
    final walletId = await createWallet(1000);
    final partyId = await LoansService.addParty(
      name: 'Loan Taken Amount Edit Party',
      currency: 'PKR',
    );
    final loanId = await LoansService.addLoan(
      LoansModel(
        partyId: partyId,
        loanType: 'taken',
        amount: 500,
        remainingAmount: 500,
        walletId: walletId,
        currency: 'PKR',
        lendingDate: '2026-11-20',
        createdAt: DateTime(2026, 11, 20).toIso8601String(),
      ),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'balance': 100},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      LoansService.updateLoanDetails(
        loanId: loanId,
        amount: 300,
        lendingDate: '2026-11-20',
        dueDate: null,
        notes: 'Updated amount',
      ),
      throwsA(isA<Exception>()),
    );

    final savedLoan = await LoansService.getLoanById(loanId);
    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect(savedLoan, isNotNull);
    expect(savedLoan!.amount, 500);
    expect(savedLoan.remainingAmount, 500);
    expect((wallet!['balance'] as num).toDouble(), 100);
  });




  test('restoring a repayment is blocked if its wallet currency changed', () async {
    final lendingWalletId = await createWallet(1000);
    final repaymentWalletId = await FinanceDB.instance.addWallet(
      name: 'Archived Repayment Wallet',
      type: 'Cash',
      currency: 'PKR',
      openingBalance: 1000,
      iconCode: 1,
      excludeTotal: false,
    );
    final partyId = await LoansService.addParty(
      name: 'Archived Repayment Currency Party',
      currency: 'PKR',
    );
    final loanId = await LoansService.addLoan(
      LoansModel(
        partyId: partyId,
        loanType: 'given',
        amount: 300,
        remainingAmount: 300,
        walletId: lendingWalletId,
        currency: 'PKR',
        lendingDate: '2026-11-20',
        createdAt: DateTime(2026, 11, 20).toIso8601String(),
      ),
    );
    final repaymentId = await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 100,
        walletId: repaymentWalletId,
        repaymentDate: '2026-11-21',
        createdAt: DateTime(2026, 11, 21).toIso8601String(),
      ),
    );
    await LoansService.deleteRepayment(repaymentId);
    final archivedRepayment = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'loan_repayments' &&
          item['source_id'].toString() == repaymentId.toString(),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [repaymentWalletId],
    );

    await expectLater(
      RecycleBinService.restore(archivedRepayment['id'] as int),
      throwsA(isA<Exception>()),
    );

    final savedLoan = await LoansService.getLoanById(loanId);
    expect(savedLoan!.remainingAmount, 300);
    expect(await LoansService.getRepayments(loanId), isEmpty);
    expect(
      (await FinanceDB.instance.getWallet(repaymentWalletId))!['currency'],
      'USD',
    );
  });

  test('cross-currency repayment edit and delete use the saved wallet-side amount', () async {
    final usdWalletId = await FinanceDB.instance.addWallet(
      name: 'USD Loan Wallet',
      type: 'Bank',
      currency: 'USD',
      openingBalance: 1000,
      iconCode: 1,
      excludeTotal: false,
    );
    final pkrWalletId = await FinanceDB.instance.addWallet(
      name: 'PKR Repayment Wallet',
      type: 'Cash',
      currency: 'PKR',
      openingBalance: 1000,
      iconCode: 1,
      excludeTotal: false,
    );
    final partyId = await LoansService.addParty(
      name: 'USD Repayment Party',
      currency: 'USD',
    );
    await FinanceDB.instance.db.insert('exchange_rates', {
      'currency': 'USD',
      'rate': 280.0,
      'updated_at': DateTime(2026, 11, 20).toIso8601String(),
    });
    final loanId = await LoansService.addLoan(
      LoansModel(
        partyId: partyId,
        loanType: 'given',
        amount: 100,
        remainingAmount: 100,
        walletId: usdWalletId,
        currency: 'USD',
        lendingDate: '2026-11-20',
        createdAt: DateTime(2026, 11, 20).toIso8601String(),
      ),
    );

    final repaymentId = await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 10,
        walletId: pkrWalletId,
        repaymentDate: '2026-11-21',
        createdAt: DateTime(2026, 11, 21).toIso8601String(),
      ),
    );
    expect(
      (await FinanceDB.instance.getWallet(pkrWalletId))!['balance'],
      3800,
    );

    await FinanceDB.instance.db.update(
      'exchange_rates',
      {'rate': 300.0},
      where: 'currency = ?',
      whereArgs: ['USD'],
    );
    await LoansService.updateRepayment(
      RepaymentModel(
        id: repaymentId,
        loanId: loanId,
        amount: 20,
        walletId: pkrWalletId,
        repaymentDate: '2026-11-22',
        createdAt: DateTime(2026, 11, 22).toIso8601String(),
      ),
    );

    final editedRepayment = (await LoansService.getRepayments(loanId)).single;
    expect(editedRepayment.walletCurrency, 'PKR');
    expect(editedRepayment.walletAmount, 6000);
    expect(
      (await FinanceDB.instance.getWallet(pkrWalletId))!['balance'],
      7000,
    );

    await LoansService.deleteRepayment(repaymentId);
    final finalLoan = await LoansService.getLoanById(loanId);
    expect(finalLoan!.remainingAmount, 100);
    expect(
      (await FinanceDB.instance.getWallet(pkrWalletId))!['balance'],
      1000,
    );
  });

  test('restoring an ordinary loan is blocked if a repayment wallet currency changed', () async {
    final lendingWalletId = await createWallet(1000);
    final repaymentWalletId = await createWallet(1000);
    final partyId = await LoansService.addParty(
      name: 'Loan Restore Repayment Currency Party',
      currency: 'PKR',
    );
    final loanId = await LoansService.addLoan(
      LoansModel(
        partyId: partyId,
        loanType: 'given',
        amount: 300,
        remainingAmount: 300,
        walletId: lendingWalletId,
        currency: 'PKR',
        lendingDate: '2026-11-20',
        createdAt: DateTime(2026, 11, 20).toIso8601String(),
      ),
    );
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 100,
        walletId: repaymentWalletId,
        repaymentDate: '2026-11-21',
        createdAt: DateTime(2026, 11, 21).toIso8601String(),
      ),
    );
    await LoansService.deleteLoan(loanId);
    final archivedLoan = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'loans' &&
          item['source_id'].toString() == loanId.toString(),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [repaymentWalletId],
    );

    await expectLater(
      RecycleBinService.restore(archivedLoan['id'] as int),
      throwsA(isA<Exception>()),
    );

    expect(await LoansService.getLoanById(loanId), isNull);
    expect(await LoansService.getRepayments(loanId), isEmpty);
    expect(
      (await FinanceDB.instance.getWallet(repaymentWalletId))!['currency'],
      'USD',
    );
  });

  test('restoring an ordinary loan is blocked if its source wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final partyId = await LoansService.addParty(
      name: 'Loan Restore Currency Party',
      currency: 'PKR',
    );
    final loanId = await LoansService.addLoan(
      LoansModel(
        partyId: partyId,
        loanType: 'given',
        amount: 300,
        remainingAmount: 300,
        walletId: walletId,
        currency: 'PKR',
        lendingDate: '2026-11-20',
        createdAt: DateTime(2026, 11, 20).toIso8601String(),
      ),
    );
    await LoansService.deleteLoan(loanId);
    final archivedLoan = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'loans' &&
          item['source_id'].toString() == loanId.toString(),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      RecycleBinService.restore(archivedLoan['id'] as int),
      throwsA(isA<Exception>()),
    );

    expect(await LoansService.getLoanById(loanId), isNull);
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['currency'],
      'USD',
    );
  });

  test('restoring a Loan Given with same-wallet repayments validates the net balance', () async {
    final walletId = await createWallet(1000);
    final partyId = await LoansService.addParty(
      name: 'Loan Restore Net Balance Party',
      currency: 'PKR',
    );
    final loanId = await LoansService.addLoan(
      LoansModel(
        partyId: partyId,
        loanType: 'given',
        amount: 500,
        remainingAmount: 500,
        walletId: walletId,
        currency: 'PKR',
        lendingDate: '2026-11-20',
        createdAt: DateTime(2026, 11, 20).toIso8601String(),
      ),
    );
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 200,
        walletId: walletId,
        repaymentDate: '2026-11-21',
        createdAt: DateTime(2026, 11, 21).toIso8601String(),
      ),
    );
    await LoansService.deleteLoan(loanId);

    await FinanceDB.instance.db.update(
      'wallets',
      {'balance': 300},
      where: 'id = ?',
      whereArgs: [walletId],
    );
    final archivedLoan = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'loans' &&
          item['source_id'].toString() == loanId.toString(),
    );

    await RecycleBinService.restore(archivedLoan['id'] as int);

    final restoredLoan = await LoansService.getLoanById(loanId);
    final repayments = await LoansService.getRepayments(loanId);
    final wallet = await FinanceDB.instance.getWallet(walletId);
    expect(restoredLoan, isNotNull);
    expect(restoredLoan!.remainingAmount, 300);
    expect(repayments, hasLength(1));
    expect((wallet!['balance'] as num).toDouble(), 0);
  });

  test('restoring asset with deleted linked party requires party restoration first',
      () async {
    final partyId = await LoansService.addParty(
      name: 'Restore Asset Seller',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(
        name: 'Archived Credit Asset',
        price: 250,
        walletId: 0,
        paymentType: 'Loan',
        partyId: partyId,
      ),
      const [],
    );

    await assets.deleteAsset(assetId);
    await LoansService.deleteParty(partyId);

    final assetArchive = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'assets',
    );
    await expectLater(
      RecycleBinService.restore(assetArchive['id'] as int),
      throwsA(isA<Exception>()),
    );
    expect(await assets.getAssets(), isEmpty);

    final partyArchive = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'loan_parties',
    );
    await RecycleBinService.restore(partyArchive['id'] as int);
    await RecycleBinService.restore(assetArchive['id'] as int);

    final restored = (await assets.getAssets()).single;
    final linkedLoan = await LoansService.getLoanById(restored.linkedLoanId!);
    expect(restored.id, assetId);
    expect(linkedLoan, isNotNull);
    expect(linkedLoan!.partyId, partyId);
    expect(linkedLoan.currency, 'PKR');
  });

  test('restoring a sold wallet-funded asset replays purchase and sale balances', () async {
    final walletId = await createWallet(1000);
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Sold Asset Restore Balance', price: 400, walletId: walletId),
      const [],
    );
    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: walletId,
      paymentType: 'Wallet',
      walletAmount: 500,
      walletCurrency: 'PKR',
    );

    expect(
      (await FinanceDB.instance.getWallet(walletId))!['balance'],
      1100,
    );
    await assets.deleteAsset(assetId);
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['balance'],
      1000,
    );

    final archived = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'assets' &&
          item['source_id'].toString() == assetId.toString(),
    );
    await RecycleBinService.restore(archived['id'] as int);

    final restored = await assets.getAssetById(assetId);
    expect(restored, isNotNull);
    expect(restored!.isSold, isTrue);
    expect(restored.salePrice, 500);
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['balance'],
      1100,
    );
  });

  test('restoring a credit-sold asset is blocked if a repayment wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final buyerId = await LoansService.addParty(
      name: 'Credit Sale Restore Currency Buyer',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Credit Sale Currency Restore Asset', price: 400, walletId: walletId),
      const [],
    );
    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: 0,
      paymentType: 'Loan',
      partyId: buyerId,
      walletAmount: 0,
      walletCurrency: 'PKR',
    );
    final saleLoan = (await LoansService.getLoans()).singleWhere(
      (loan) => loan.sourceType == 'asset_sale',
    );
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: saleLoan.id!,
        amount: 200,
        walletId: walletId,
        repaymentDate: '2026-11-11',
        createdAt: DateTime(2026, 11, 11).toIso8601String(),
      ),
    );
    await assets.deleteAsset(assetId);
    final archivedAsset = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'assets' &&
          item['source_id'].toString() == assetId.toString(),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      RecycleBinService.restore(archivedAsset['id'] as int),
      throwsA(isA<Exception>()),
    );

    expect(await assets.getAssetById(assetId), isNull);
    expect(await LoansService.getLoanById(saleLoan.id!), isNull);
    expect(await LoansService.getRepayments(saleLoan.id!), isEmpty);
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['currency'],
      'USD',
    );
  });

  test('restoring a credit-sold asset restores sale loan repayments and balances', () async {
    final walletId = await createWallet(1000);
    final buyerId = await LoansService.addParty(
      name: 'Credit Sale Restore Buyer',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Credit Sale Restore Asset', price: 400, walletId: walletId),
      const [],
    );
    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: 0,
      paymentType: 'Loan',
      partyId: buyerId,
      walletAmount: 0,
      walletCurrency: 'PKR',
    );
    final saleLoan = (await LoansService.getLoans()).singleWhere(
      (loan) => loan.sourceType == 'asset_sale',
    );
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: saleLoan.id!,
        amount: 200,
        walletId: walletId,
        repaymentDate: '2026-11-11',
        createdAt: DateTime(2026, 11, 11).toIso8601String(),
      ),
    );
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['balance'],
      800,
    );

    await assets.deleteAsset(assetId);
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['balance'],
      1000,
    );
    expect(await LoansService.getLoanById(saleLoan.id!), isNull);

    final archived = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'assets' &&
          item['source_id'].toString() == assetId.toString(),
    );
    await RecycleBinService.restore(archived['id'] as int);

    final restored = await assets.getAssetById(assetId);
    final restoredLoan = await LoansService.getLoanById(saleLoan.id!);
    final repayments = await LoansService.getRepayments(saleLoan.id!);
    expect(restored, isNotNull);
    expect(restored!.isSold, isTrue);
    expect(restored.saleLinkedLoanId, saleLoan.id);
    expect(restoredLoan, isNotNull);
    expect(restoredLoan!.remainingAmount, 300);
    expect(repayments, hasLength(1));
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['balance'],
      800,
    );
  });
  test('editing or deleting a repayment is blocked if its wallet currency changed', () async {
    final lendingWalletId = await createWallet(1000);
    final repaymentWalletId = await createWallet(1000);
    final partyId = await LoansService.addParty(
      name: 'Changed Repayment Wallet Currency Party',
      currency: 'PKR',
    );
    final loanId = await LoansService.addLoan(
      LoansModel(
        partyId: partyId,
        loanType: 'given',
        amount: 300,
        remainingAmount: 300,
        walletId: lendingWalletId,
        currency: 'PKR',
        lendingDate: '2026-11-20',
        createdAt: DateTime(2026, 11, 20).toIso8601String(),
      ),
    );
    final repaymentId = await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 100,
        walletId: repaymentWalletId,
        repaymentDate: '2026-11-21',
        createdAt: DateTime(2026, 11, 21).toIso8601String(),
      ),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [repaymentWalletId],
    );

    await expectLater(
      LoansService.updateRepayment(
        RepaymentModel(
          id: repaymentId,
          loanId: loanId,
          amount: 80,
          walletId: repaymentWalletId,
          repaymentDate: '2026-11-22',
          createdAt: DateTime(2026, 11, 22).toIso8601String(),
        ),
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      LoansService.deleteRepayment(repaymentId),
      throwsA(isA<Exception>()),
    );

    final savedLoan = await LoansService.getLoanById(loanId);
    final savedRepayments = await LoansService.getRepayments(loanId);
    expect(savedLoan!.remainingAmount, 200);
    expect(savedRepayments, hasLength(1));
    expect(savedRepayments.single.amount, 100);
    expect(
      (await FinanceDB.instance.getWallet(repaymentWalletId))!['balance'],
      1100,
    );
  });

  test('deleting a credit-sold asset is blocked if a repayment wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final buyerId = await LoansService.addParty(
      name: 'Credit Sale Delete Currency Buyer',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Credit Sale Delete Currency Asset', price: 400, walletId: walletId),
      const [],
    );
    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: 0,
      paymentType: 'Loan',
      partyId: buyerId,
      walletAmount: 0,
      walletCurrency: 'PKR',
    );
    final saleLoan = (await LoansService.getLoans()).singleWhere(
      (loan) => loan.sourceType == 'asset_sale',
    );
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: saleLoan.id!,
        amount: 200,
        walletId: walletId,
        repaymentDate: '2026-11-11',
        createdAt: DateTime(2026, 11, 11).toIso8601String(),
      ),
    );
    await FinanceDB.instance.db.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      assets.deleteAsset(assetId),
      throwsA(isA<Exception>()),
    );

    expect(await assets.getAssetById(assetId), isNotNull);
    expect(await LoansService.getLoanById(saleLoan.id!), isNotNull);
    expect(await LoansService.getRepayments(saleLoan.id!), hasLength(1));
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['balance'],
      800,
    );
  });

}
