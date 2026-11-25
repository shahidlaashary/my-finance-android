import 'package:my_finance/core/database/database_manager.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/modules/finance/models/assets_model.dart';
import 'package:my_finance/modules/finance/models/loans_model.dart';
import 'package:my_finance/modules/finance/models/repayment_model.dart';
import 'package:my_finance/modules/finance/services/assets_service.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';
import 'package:my_finance/modules/parties/services/party_service.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
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

  Future<Map<String, int>> createLoanWithRepayment() async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Repayment Reconciliation Party',
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
        lendingDate: '2026-11-01',
        createdAt: DateTime(2026, 11, 1).toIso8601String(),
      ),
    );
    final repaymentId = await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 100,
        walletId: walletId,
        repaymentDate: '2026-11-02',
        createdAt: DateTime(2026, 11, 2).toIso8601String(),
      ),
    );
    await DatabaseManager.instance.database.update(
      'loans',
      {'remaining_amount': 350},
      where: 'id = ?',
      whereArgs: [loanId],
    );
    return {
      'walletId': walletId,
      'loanId': loanId,
      'repaymentId': repaymentId,
    };
  }

  test('party names are unique only within the same party type', () async {
    final individualId = await PartyService.addParty(
      name: 'Same Name Party',
      partyType: 'Individual',
      phone: '03000000001',
    );
    final businessId = await PartyService.addParty(
      name: 'Same Name Party',
      partyType: 'Business',
      phone: '03000000002',
    );

    expect(businessId, isNot(individualId));
    await expectLater(
      PartyService.addParty(
        name: ' same name party ',
        partyType: 'Individual',
        phone: '03000000003',
      ),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('already exists under Individual type'),
      )),
    );
    await expectLater(
      PartyService.addParty(
        name: 'Same Name Party',
        partyType: 'Business',
      ),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('already exists under Business type'),
      )),
    );
  });

  test('updating a party blocks duplicate name and type but allows other type', () async {
    final firstId = await PartyService.addParty(
      name: 'Update Party',
      partyType: 'Individual',
    );
    final secondId = await PartyService.addParty(
      name: 'Other Party',
      partyType: 'Individual',
    );

    await expectLater(
      PartyService.updateParty(
        id: secondId,
        name: ' update party ',
        partyType: 'Individual',
      ),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('already exists under Individual type'),
      )),
    );

    await PartyService.updateParty(
      id: secondId,
      name: 'Update Party',
      partyType: 'Business',
    );

    final parties = await PartyService.getParties();
    expect(parties.where((party) => party['name'] == 'Update Party'), hasLength(2));
    expect(parties.map((party) => party['id']).toSet(), containsAll([firstId, secondId]));
  });

  test('loan-funded asset purchase works without any wallet', () async {
    final partyId = await PartyService.addParty(
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
    final walletRows = await DatabaseManager.instance.database.query('wallets');

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
    final buyerId = await PartyService.addParty(
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
    final buyerId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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
    final buyerId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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
    final sellerId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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

  test('deleting asset is blocked if purchase wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Purchase Currency Guard Asset', price: 400, walletId: walletId),
      const [],
    );
    await DatabaseManager.instance.database.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(assets.deleteAsset(assetId), throwsA(isA<Exception>()));
    expect(await assets.getAssetById(assetId), isNotNull);
    expect((await FinanceDB.instance.getWallet(walletId))!['currency'], 'USD');
  });

  test('deleting sold asset is blocked if sale wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Sale Currency Guard Asset', price: 400, walletId: walletId),
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
    await DatabaseManager.instance.database.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(assets.deleteAsset(assetId), throwsA(isA<Exception>()));
    expect((await assets.getAssetById(assetId))!.isSold, isTrue);
    expect((await FinanceDB.instance.getWallet(walletId))!['currency'], 'USD');
  });

  test('restoring asset is blocked if purchase wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Restore Purchase Currency Asset', price: 400, walletId: walletId),
      const [],
    );
    await assets.deleteAsset(assetId);
    final archived = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'assets' &&
          item['source_id'].toString() == assetId.toString(),
    );
    await DatabaseManager.instance.database.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      RecycleBinService.restore(archived['id'] as int),
      throwsA(isA<Exception>()),
    );
    expect(await assets.getAssetById(assetId), isNull);
    expect((await FinanceDB.instance.getWallet(walletId))!['currency'], 'USD');
  });

  test('restoring sold asset is blocked if sale wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Restore Sale Currency Asset', price: 400, walletId: walletId),
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
    await assets.deleteAsset(assetId);
    final archived = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'assets' &&
          item['source_id'].toString() == assetId.toString(),
    );
    await DatabaseManager.instance.database.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      RecycleBinService.restore(archived['id'] as int),
      throwsA(isA<Exception>()),
    );
    expect(await assets.getAssetById(assetId), isNull);
    expect((await FinanceDB.instance.getWallet(walletId))!['currency'], 'USD');
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

    await DatabaseManager.instance.database.update(
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
    final partyId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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
    final partyId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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
    final partyId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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
    final partyId = await PartyService.addParty(
      name: 'USD Repayment Party',
      currency: 'USD',
    );
    await DatabaseManager.instance.database.insert('exchange_rates', {
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

    await DatabaseManager.instance.database.update(
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
    final partyId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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
    final partyId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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

  test('restoring an ordinary loan requires its deleted party to be restored first', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Loan Restore Missing Party',
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
    await PartyService.deleteParty(partyId);

    final archivedLoan = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'loans' &&
          item['source_id'].toString() == loanId.toString(),
    );
    await expectLater(
      RecycleBinService.restore(archivedLoan['id'] as int),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('Restore the linked party before restoring this loan'),
      )),
    );
    expect(await LoansService.getLoanById(loanId), isNull);

    final archivedParty = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'loan_parties' &&
          item['source_id'].toString() == partyId.toString(),
    );
    await RecycleBinService.restore(archivedParty['id'] as int);
    await RecycleBinService.restore(archivedLoan['id'] as int);

    final restoredLoan = await LoansService.getLoanById(loanId);
    expect(restoredLoan, isNotNull);
    expect(restoredLoan!.partyId, partyId);
  });

  test('restoring an ordinary loan is blocked if its party currency changed', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Loan Restore Party Currency',
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
    await DatabaseManager.instance.database.update(
      'loan_parties',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [partyId],
    );

    await expectLater(
      RecycleBinService.restore(archivedLoan['id'] as int),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('linked party currency has changed'),
      )),
    );
    expect(await LoansService.getLoanById(loanId), isNull);
  });

  test('restoring a Loan Given with same-wallet repayments validates the net balance', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
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

    await DatabaseManager.instance.database.update(
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
    final partyId = await PartyService.addParty(
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
    await PartyService.deleteParty(partyId);

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
    final buyerId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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
    final buyerId = await PartyService.addParty(
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
    final partyId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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
    final buyerId = await PartyService.addParty(
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
    await DatabaseManager.instance.database.update(
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

  test('editing an ordinary loan is blocked if its source wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Loan Edit Source Currency Party',
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
    await DatabaseManager.instance.database.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      LoansService.updateLoanDetails(
        loanId: loanId,
        amount: 350,
        lendingDate: '2026-11-22',
        dueDate: null,
        notes: 'Should not be saved',
      ),
      throwsA(isA<Exception>()),
    );

    final savedLoan = await LoansService.getLoanById(loanId);
    expect(savedLoan, isNotNull);
    expect(savedLoan!.amount, 300);
    expect(savedLoan.lendingDate, '2026-11-20');
    expect(savedLoan.notes, isEmpty);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 700);
  });

  test('deleting an ordinary loan is blocked if its source wallet currency changed', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Loan Delete Source Currency Party',
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
    await DatabaseManager.instance.database.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [walletId],
    );

    await expectLater(
      LoansService.deleteLoan(loanId),
      throwsA(isA<Exception>()),
    );

    final savedLoan = await LoansService.getLoanById(loanId);
    expect(savedLoan, isNotNull);
    expect(savedLoan!.amount, 300);
    expect(await LoansService.getRepayments(loanId), isEmpty);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 700);
    expect(
      await DatabaseManager.instance.database.query(
        'recycle_bin',
        where: 'source_table = ? AND source_id = ?',
        whereArgs: ['loans', loanId.toString()],
      ),
      isEmpty,
    );
  });

  test('deleting an ordinary loan is blocked if a repayment wallet currency changed', () async {
    final lendingWalletId = await createWallet(1000);
    final repaymentWalletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Ordinary Loan Delete Currency Party',
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
    await DatabaseManager.instance.database.update(
      'wallets',
      {'currency': 'USD'},
      where: 'id = ?',
      whereArgs: [repaymentWalletId],
    );

    await expectLater(
      LoansService.deleteLoan(loanId),
      throwsA(isA<Exception>()),
    );

    final savedLoan = await LoansService.getLoanById(loanId);
    expect(savedLoan, isNotNull);
    expect(savedLoan!.remainingAmount, 200);
    expect(await LoansService.getRepayments(loanId), hasLength(1));
    expect(
      (await FinanceDB.instance.getWallet(lendingWalletId))!['balance'],
      700,
    );
    expect(
      (await FinanceDB.instance.getWallet(repaymentWalletId))!['balance'],
      1100,
    );
  });



  test('editing a wallet-funded asset moves the purchase debit atomically', () async {
    final originalWalletId = await createWallet(1000);
    final replacementWalletId = await FinanceDB.instance.addWallet(
      name: 'Replacement Asset Wallet',
      type: 'Cash',
      currency: 'PKR',
      openingBalance: 1000,
      iconCode: 1,
      excludeTotal: false,
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Editable Wallet Asset', price: 400, walletId: originalWalletId),
      const [],
    );

    final saved = await assets.getAssetById(assetId);
    await assets.updateAsset(saved!.copyWith(
      purchasePrice: 500,
      currentValue: 450,
      walletId: replacementWalletId,
      notes: 'Updated purchase details',
    ));

    final updated = await assets.getAssetById(assetId);
    expect(updated!.purchasePrice, 500);
    expect(updated.currentValue, 450);
    expect(updated.walletId, replacementWalletId);
    expect(updated.notes, 'Updated purchase details');
    expect((await FinanceDB.instance.getWallet(originalWalletId))!['balance'], 1000);
    expect((await FinanceDB.instance.getWallet(replacementWalletId))!['balance'], 500);
  });

  test('editing a loan-funded asset updates its linked loan when no repayments exist', () async {
    final originalPartyId = await PartyService.addParty(
      name: 'Original Asset Seller',
      currency: 'PKR',
    );
    final replacementPartyId = await PartyService.addParty(
      name: 'Replacement Asset Seller',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(
        name: 'Editable Credit Asset',
        price: 500,
        walletId: 0,
        paymentType: 'Loan',
        partyId: originalPartyId,
      ),
      const [],
    );
    final original = await assets.getAssetById(assetId);

    await assets.updateAsset(original!.copyWith(
      name: 'Updated Credit Asset',
      purchasePrice: 600,
      purchaseDate: DateTime(2026, 11, 5),
      partyId: replacementPartyId,
    ));

    final updated = await assets.getAssetById(assetId);
    final loan = await LoansService.getLoanById(original.linkedLoanId!);
    expect(updated!.name, 'Updated Credit Asset');
    expect(updated.purchasePrice, 600);
    expect(updated.partyId, replacementPartyId);
    expect(loan!.partyId, replacementPartyId);
    expect(loan.amount, 600);
    expect(loan.remainingAmount, 600);
    expect(loan.lendingDate, '2026-11-05');
  });

  test('editing loan-funded asset terms is blocked after repayments exist', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Repaid Asset Seller',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(
        name: 'Repaid Credit Asset',
        price: 500,
        walletId: 0,
        paymentType: 'Loan',
        partyId: partyId,
      ),
      const [],
    );
    final saved = await assets.getAssetById(assetId);
    final loanId = saved!.linkedLoanId!;
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 100,
        walletId: walletId,
        repaymentDate: '2026-11-10',
        createdAt: DateTime(2026, 11, 10).toIso8601String(),
      ),
    );

    await expectLater(
      assets.updateAsset(saved.copyWith(purchasePrice: 600)),
      throwsA(isA<Exception>()),
    );

    final unchangedAsset = await assets.getAssetById(assetId);
    final unchangedLoan = await LoansService.getLoanById(loanId);
    expect(unchangedAsset!.purchasePrice, 500);
    expect(unchangedLoan!.amount, 500);
    expect(unchangedLoan.remainingAmount, 400);
    expect(await LoansService.getRepayments(loanId), hasLength(1));
  });


  test('cross-currency asset sale credits and reverses the saved wallet amount', () async {
    final purchaseWalletId = await createWallet(1000);
    final receivingWalletId = await FinanceDB.instance.addWallet(
      name: 'USD Asset Sale Wallet',
      type: 'Bank',
      currency: 'USD',
      openingBalance: 10,
      iconCode: 1,
      excludeTotal: false,
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Cross Currency Sale Asset', price: 400, walletId: purchaseWalletId),
      const [],
    );

    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: receivingWalletId,
      paymentType: 'Wallet',
      walletAmount: 1,
      walletCurrency: 'USD',
      exchangeRate: 0.002,
    );

    expect(
      (await FinanceDB.instance.getWallet(purchaseWalletId))!['balance'],
      600,
    );
    expect(
      (await FinanceDB.instance.getWallet(receivingWalletId))!['balance'],
      11,
    );

    final sold = await assets.getAssetById(assetId);
    expect(sold!.saleWalletAmount, 1);
    expect(sold.saleWalletCurrency, 'USD');
    expect(sold.saleExchangeRate, 0.002);

    await assets.deleteAsset(assetId);

    expect(
      (await FinanceDB.instance.getWallet(purchaseWalletId))!['balance'],
      1000,
    );
    expect(
      (await FinanceDB.instance.getWallet(receivingWalletId))!['balance'],
      10,
    );
    expect(await assets.getAssetById(assetId), isNull);
  });

  test('consolidated balance includes current value only while asset is unsold', () async {
    final walletId = await createWallet(1000);
    final assetId = await assets.addAssetWithAttachments(
      asset(name: 'Consolidated Balance Asset', price: 400, walletId: walletId),
      const [],
    );

    var included = await assets.getConsolidatedIncludedCurrentValueByCurrency();
    expect(included, isEmpty);

    final saved = await assets.getAssetById(assetId);
    await assets.updateAsset(saved!.copyWith(
      currentValue: 450,
      includeInConsolidatedBalance: true,
    ));

    included = await assets.getConsolidatedIncludedCurrentValueByCurrency();
    expect(included['PKR'], 450);

    await assets.sellAsset(
      assetId: assetId,
      salePrice: 500,
      saleDate: DateTime(2026, 11, 10),
      saleWalletId: walletId,
      paymentType: 'Wallet',
      walletAmount: 500,
      walletCurrency: 'PKR',
    );

    included = await assets.getConsolidatedIncludedCurrentValueByCurrency();
    expect(included, isEmpty);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 1100);
  });

  test('deleting a loan-funded asset is blocked when repayments do not reconcile', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Mismatch Asset Seller',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(
        name: 'Mismatch Credit Asset',
        price: 500,
        walletId: 0,
        paymentType: 'Loan',
        partyId: partyId,
      ),
      const [],
    );
    final saved = await assets.getAssetById(assetId);
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: saved!.linkedLoanId!,
        amount: 100,
        walletId: walletId,
        repaymentDate: '2026-11-10',
        createdAt: DateTime(2026, 11, 10).toIso8601String(),
      ),
    );
    await DatabaseManager.instance.database.update(
      'loans',
      {'remaining_amount': 450},
      where: 'id = ?',
      whereArgs: [saved.linkedLoanId],
    );

    await expectLater(
      assets.deleteAsset(assetId),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('does not reconcile with its repayment history'),
      )),
    );
    expect(await assets.getAssetById(assetId), isNotNull);
    expect(await LoansService.getLoanById(saved.linkedLoanId!), isNotNull);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 900);
  });

  test('restoring an asset is blocked when archived loan repayments do not reconcile', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Archived Mismatch Seller',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(
        name: 'Archived Mismatch Asset',
        price: 500,
        walletId: 0,
        paymentType: 'Loan',
        partyId: partyId,
      ),
      const [],
    );
    final saved = await assets.getAssetById(assetId);
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: saved!.linkedLoanId!,
        amount: 100,
        walletId: walletId,
        repaymentDate: '2026-11-10',
        createdAt: DateTime(2026, 11, 10).toIso8601String(),
      ),
    );
    await assets.deleteAsset(assetId);

    final archive = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'assets' &&
          item['source_id'].toString() == assetId.toString(),
    );
    final related = jsonDecode(archive['related_payload'] as String) as List;
    final loanSnapshot = Map<String, dynamic>.from(related.single['loan'] as Map);
    loanSnapshot['remaining_amount'] = 450;
    related.single['loan'] = loanSnapshot;
    await DatabaseManager.instance.database.update(
      'recycle_bin',
      {'related_payload': jsonEncode(related)},
      where: 'id = ?',
      whereArgs: [archive['id']],
    );

    await expectLater(
      RecycleBinService.restore(archive['id'] as int),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('does not reconcile with its repayment history'),
      )),
    );
    expect(await assets.getAssetById(assetId), isNull);
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 1000);
  });

  test('restoring a party is blocked when its name and type already exist', () async {
    final partyId = await PartyService.addParty(
      name: 'Duplicate Restore Party',
      currency: 'PKR',
      partyType: 'Individual',
    );
    await PartyService.deleteParty(partyId);

    final replacementId = await PartyService.addParty(
      name: 'Duplicate Restore Party',
      currency: 'USD',
      partyType: 'Individual',
    );
    expect(replacementId, isNot(partyId));

    final archivedParty = (await RecycleBinService.getItems()).singleWhere(
      (item) => item['source_table'] == 'loan_parties' &&
          item['source_id'].toString() == partyId.toString(),
    );
    await expectLater(
      RecycleBinService.restore(archivedParty['id'] as int),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('A party with this name already exists under Individual type'),
      )),
    );

    final parties = await PartyService.getParties();
    expect(parties.where((party) =>
        (party['name'] as String) == 'Duplicate Restore Party'), hasLength(1));
    expect(parties.single['id'], replacementId);
  });

  test('updating a loan-funded asset is blocked when repayments do not reconcile', () async {
    final walletId = await createWallet(1000);
    final partyId = await PartyService.addParty(
      name: 'Asset Update Repayment Reconciliation Party',
      currency: 'PKR',
    );
    final assetId = await assets.addAssetWithAttachments(
      asset(
        name: 'Asset With Repayment History',
        price: 500,
        walletId: 0,
        paymentType: 'Loan',
        partyId: partyId,
      ),
      const [],
    );
    final savedAsset = await assets.getAssetById(assetId);
    final loanId = savedAsset!.linkedLoanId!;
    await LoansService.addRepayment(
      RepaymentModel(
        loanId: loanId,
        amount: 100,
        walletId: walletId,
        repaymentDate: '2026-11-21',
        createdAt: DateTime(2026, 11, 21).toIso8601String(),
      ),
    );
    await DatabaseManager.instance.database.update(
      'loans',
      {'remaining_amount': 350},
      where: 'id = ?',
      whereArgs: [loanId],
    );

    await expectLater(
      assets.updateAsset(savedAsset.copyWith(currentValue: 450)),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('does not reconcile with its repayment history'),
      )),
    );

    final unchangedAsset = await assets.getAssetById(assetId);
    final unchangedLoan = await LoansService.getLoanById(loanId);
    expect(unchangedAsset!.currentValue, 500);
    expect(unchangedLoan!.remainingAmount, 350);
    expect(await LoansService.getRepayments(loanId), hasLength(1));
    expect(
      (await FinanceDB.instance.getWallet(walletId))!['balance'],
      900,
    );
  });
  test('adding repayment is blocked when existing loan history does not reconcile', () async {
    final ids = await createLoanWithRepayment();
    final walletBefore =
        (await FinanceDB.instance.getWallet(ids['walletId']!))!['balance'];
    await expectLater(
      LoansService.addRepayment(
        RepaymentModel(
          loanId: ids['loanId']!,
          amount: 50,
          walletId: ids['walletId']!,
          repaymentDate: '2026-11-03',
          createdAt: DateTime(2026, 11, 3).toIso8601String(),
        ),
      ),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('does not reconcile with its repayment history'),
      )),
    );
    expect(await LoansService.getRepayments(ids['loanId']!), hasLength(1));
    expect((await LoansService.getLoanById(ids['loanId']!))!.remainingAmount, 350);
    expect((await FinanceDB.instance.getWallet(ids['walletId']!))!['balance'], walletBefore);
  });

  test('updating repayment is blocked when existing loan history does not reconcile', () async {
    final ids = await createLoanWithRepayment();
    final walletBefore =
        (await FinanceDB.instance.getWallet(ids['walletId']!))!['balance'];
    await expectLater(
      LoansService.updateRepayment(
        RepaymentModel(
          id: ids['repaymentId']!,
          loanId: ids['loanId']!,
          amount: 120,
          walletId: ids['walletId']!,
          repaymentDate: '2026-11-03',
          createdAt: DateTime(2026, 11, 3).toIso8601String(),
        ),
      ),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('does not reconcile with its repayment history'),
      )),
    );
    expect(await LoansService.getRepayments(ids['loanId']!), hasLength(1));
    expect((await LoansService.getLoanById(ids['loanId']!))!.remainingAmount, 350);
    expect((await FinanceDB.instance.getWallet(ids['walletId']!))!['balance'], walletBefore);
  });

  test('deleting repayment is blocked when existing loan history does not reconcile', () async {
    final ids = await createLoanWithRepayment();
    final walletBefore =
        (await FinanceDB.instance.getWallet(ids['walletId']!))!['balance'];
    await expectLater(
      LoansService.deleteRepayment(ids['repaymentId']!),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('does not reconcile with its repayment history'),
      )),
    );
    expect(await LoansService.getRepayments(ids['loanId']!), hasLength(1));
    expect((await LoansService.getLoanById(ids['loanId']!))!.remainingAmount, 350);
    expect((await FinanceDB.instance.getWallet(ids['walletId']!))!['balance'], walletBefore);
  });

}
