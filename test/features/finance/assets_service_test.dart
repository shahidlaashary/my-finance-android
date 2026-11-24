import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
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
}
