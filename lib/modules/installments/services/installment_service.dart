import 'dart:convert';
import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/services/recycle_bin_archive_service.dart';

/// Installment contracts, payments aur unke finance ledger records manage karta hai.
class InstallmentService {
  static Future<Database> get _db async {
    final db = DatabaseManager.instance.database;
    await db.execute("""
      CREATE TABLE IF NOT EXISTS installment_contracts (
        id INTEGER PRIMARY KEY AUTOINCREMENT, direction TEXT NOT NULL,
        item_name TEXT NOT NULL, party_name TEXT NOT NULL, phone TEXT,
        total_amount REAL NOT NULL, paid_amount REAL NOT NULL DEFAULT 0,
        wallet_id INTEGER NOT NULL, installment_amount REAL NOT NULL,
        frequency TEXT NOT NULL DEFAULT 'Monthly', start_date TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL
      )
    """);
    await db.execute("""
      CREATE TABLE IF NOT EXISTS installment_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT, contract_id INTEGER NOT NULL,
        amount REAL NOT NULL, payment_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL
      )
    """);
    return db;
  }

  /// Optional direction filter ke saath installment contracts load karta hai.
  static Future<List<Map<String, dynamic>>> getContracts({String? direction}) async {
    final db = await _db;
    return db.query('installment_contracts',
      where: direction == null ? null : 'direction = ?',
      whereArgs: direction == null ? null : [direction],
      orderBy: 'created_at DESC, id DESC');
  }

  /// Contract ki payment history newest-first return karta hai.
  static Future<List<Map<String, dynamic>>> getPayments(int id) async {
    final db = await _db;
    return db.query('installment_payments', where: 'contract_id = ?',
      whereArgs: [id], orderBy: 'payment_date DESC, id DESC');
  }

  /// Naya installment contract aur optional advance payment aik transaction mein save karta hai.
  static Future<int> addContract({
    required String direction, required String itemName, required String partyName,
    String? phone, required double totalAmount, required double advance,
    required int walletId, required double installmentAmount, required String frequency,
    required String startDate, required String notes,
  }) async {
    if (!['sell', 'buy'].contains(direction) || itemName.trim().isEmpty || partyName.trim().isEmpty ||
        !totalAmount.isFinite || totalAmount <= 0 || !advance.isFinite || advance < 0 ||
        advance > totalAmount || !installmentAmount.isFinite || installmentAmount <= 0 || walletId <= 0) {
      throw Exception('Please enter valid installment details.');
    }
    final db = await _db;
    final id = await db.transaction((txn) async {
      final wallets = await txn.query('wallets', where: 'id = ?', whereArgs: [walletId], limit: 1);
      if (wallets.isEmpty) throw Exception('Selected wallet was not found.');
      final balance = (wallets.first['balance'] as num).toDouble();
      if (direction == 'buy' && balance < advance) throw Exception('Insufficient wallet balance for advance.');
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('installment_contracts', {
        'direction': direction, 'item_name': itemName.trim(), 'party_name': partyName.trim(),
        'phone': phone?.trim(), 'total_amount': totalAmount, 'paid_amount': advance,
        'wallet_id': walletId, 'installment_amount': installmentAmount,
        'frequency': frequency, 'start_date': startDate, 'notes': notes.trim(),
        'status': advance >= totalAmount ? 'completed' : 'active', 'created_at': now,
      });
      if (advance > 0) await _applyPayment(txn, id, advance, walletId, startDate, 'Advance payment', direction, now);
      return id;
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  /// Contract, payments aur linked ledger records archive karke delete karta hai.
  static Future<void> deleteContract(int contractId) async {
    final db = await _db;
    final contracts = await db.query('installment_contracts',
      where: 'id = ?', whereArgs: [contractId], limit: 1);
    if (contracts.isEmpty) return;
    final contract = Map<String, dynamic>.from(contracts.first);
    final payments = await db.query('installment_payments',
      where: 'contract_id = ?', whereArgs: [contractId], orderBy: 'id');
    final transactions = await db.query('transactions',
      where: "category IN ('Installment Received','Installment Paid') AND note LIKE ?",
      whereArgs: ['Installment #$contractId%']);
    await RecycleBinArchiveService.archive(
      type: 'Installment Contract',
      title: contract['item_name']?.toString() ?? 'Installment',
      table: 'installment_contracts',
      id: contractId,
      record: contract,
      related: [
        ...payments.map((row) => {'_related_table':'installment_payments', ...Map<String,dynamic>.from(row)}),
        ...transactions.map((row) => {'_related_table':'transactions', ...Map<String,dynamic>.from(row)}),
      ],
    );
    await db.transaction((txn) async {
      await TransactionsService.deleteModuleLedgerEntries(
        txn, transactions.map((row) => Map<String, dynamic>.from(row)).toList());
      await txn.delete('installment_payments', where: 'contract_id = ?', whereArgs: [contractId]);
      await txn.delete('installment_contracts', where: 'id = ?', whereArgs: [contractId]);
    });
    AppRefreshController.notifyChanged();
  }

  /// Qist record aur wallet balance aik hi database transaction mein update hote hain.
  /// Payment fail ho to wallet aur qist dono changes rollback ho jate hain.
  /// Remaining amount aur wallet balance validate karke payment save karta hai.
  static Future<void> addPayment({
    required int contractId, required double amount, required String date, required String note,
  }) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Enter a valid payment amount.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('installment_contracts', where: 'id = ?', whereArgs: [contractId], limit: 1);
      if (rows.isEmpty) throw Exception('Installment plan not found.');
      final c = rows.first;
      final total = (c['total_amount'] as num).toDouble();
      final paid = (c['paid_amount'] as num).toDouble();
      if (amount > total - paid + 0.000001) throw Exception('Payment cannot exceed remaining balance.');
      final walletId = c['wallet_id'] as int;
      final direction = c['direction'] as String;
      final w = await txn.query('wallets', where: 'id = ?', whereArgs: [walletId], limit: 1);
      if (w.isEmpty) throw Exception('Linked wallet was not found.');
      if (direction == 'buy' && (w.first['balance'] as num).toDouble() < amount) {
        throw Exception('Insufficient wallet balance.');
      }
      final now = DateTime.now().toIso8601String();
      await _applyPayment(txn, contractId, amount, walletId, date, note, direction, now);
      final nextPaid = paid + amount;
      await txn.update('installment_contracts', {
        'paid_amount': nextPaid, 'status': nextPaid >= total - 0.000001 ? 'completed' : 'active',
      }, where: 'id = ?', whereArgs: [contractId]);
    });
    AppRefreshController.notifyChanged();
  }

  /// Payment ki direction ke mutabiq wallet balance update karke ledger entry banata hai.
  static Future<void> _applyPayment(Transaction txn, int id, double amount, int walletId,
      String date, String note, String direction, String now) async {
    await txn.insert('installment_payments', {
      'contract_id': id, 'amount': amount, 'payment_date': date, 'note': note, 'created_at': now,
    });
    await TransactionsService.createModuleLedgerEntry(
      txn,
      type: direction == 'sell' ? 'Income' : 'Expense',
      amount: amount, walletId: walletId,
      category: direction == 'sell' ? 'Installment Received' : 'Installment Paid',
      note: 'Installment #$id' + (note.isEmpty ? '' : ' • $note'),
      date: date,
    );
  }
  /// Archived installment contract, payments aur related ledger entries aik transaction mein restore karta hai.
  /// Archived contract, payment history aur finance ledger entries restore karta hai.
  static Future<void> restoreArchivedContract(
    Transaction txn, {
    required Map<String, dynamic> record,
    String? relatedPayload,
  }) async {
        await txn.execute("""CREATE TABLE IF NOT EXISTS installment_contracts (
          id INTEGER PRIMARY KEY AUTOINCREMENT, direction TEXT NOT NULL,
          item_name TEXT NOT NULL, party_name TEXT NOT NULL, phone TEXT,
          total_amount REAL NOT NULL, paid_amount REAL NOT NULL DEFAULT 0,
          wallet_id INTEGER NOT NULL, installment_amount REAL NOT NULL,
          frequency TEXT NOT NULL DEFAULT 'Monthly', start_date TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active',
          created_at TEXT NOT NULL)""");
        await txn.execute("""CREATE TABLE IF NOT EXISTS installment_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT, contract_id INTEGER NOT NULL,
          amount REAL NOT NULL, payment_date TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)""");
        final relatedRaw = relatedPayload ?? '[]';
        final related = (jsonDecode(relatedRaw) as List)
            .whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
        final payments = related.where((e) => e['_related_table'] == 'installment_payments').toList();
        final transactions = related.where((e) => e['_related_table'] == 'transactions').toList();
        final duplicate = await txn.query('installment_contracts',
          columns: ['id'], where: 'id = ?', whereArgs: [record['id']], limit: 1);
        if (duplicate.isNotEmpty) throw Exception('This installment contract already exists.');
        await txn.insert('installment_contracts', record);
        for (final payment in payments) {
          payment.remove('_related_table');
          await txn.insert('installment_payments', payment);
        }
        await TransactionsService.restoreModuleLedgerEntries(txn, transactions);
        return;
  }

}
