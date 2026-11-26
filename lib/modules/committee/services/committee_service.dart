import 'dart:convert';
import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
import 'package:my_finance/modules/finance/services/currency_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/services/recycle_bin_archive_service.dart';

/// Committee funds are maintained in a private ledger. Personal wallets are
/// touched only when the user explicitly chooses one for an installment/payout.
class CommitteeService {
  /// Converts committee entry wallet snapshots for a wallet currency change.
  static Future<void> convertWalletAmounts(
    Transaction txn,
    int walletId,
    double factor,
    String currency,
  ) async {
    final table = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'committee_entries'",
    );
    if (table.isEmpty) return;
    await txn.rawUpdate('''
      UPDATE committee_entries
      SET wallet_amount = wallet_amount * ?,
          wallet_currency = ?
      WHERE wallet_id = ?
    ''', [factor, currency, walletId]);
  }

  static Future<void> _ensureSchema() async {
    final db = DatabaseManager.instance.database;
    await db.execute('''CREATE TABLE IF NOT EXISTS committees (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      frequency TEXT NOT NULL, installment_amount REAL NOT NULL,
      member_count INTEGER NOT NULL, currency TEXT NOT NULL DEFAULT 'PKR', start_date TEXT NOT NULL,
      first_due_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'Upcoming',
      created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS committee_members (
      id INTEGER PRIMARY KEY AUTOINCREMENT, committee_id INTEGER NOT NULL,
      name TEXT NOT NULL, phone TEXT, turn_no INTEGER NOT NULL,
      created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS committee_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT, committee_id INTEGER NOT NULL,
      member_id INTEGER NOT NULL, entry_type TEXT NOT NULL,
      amount REAL NOT NULL, wallet_amount REAL NOT NULL DEFAULT 0,
      committee_currency TEXT NOT NULL DEFAULT 'PKR', wallet_currency TEXT NOT NULL DEFAULT '',
      payment_method TEXT NOT NULL DEFAULT 'None', wallet_id INTEGER NOT NULL DEFAULT -1,
      transaction_id INTEGER, entry_date TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_committee_members_committee ON committee_members(committee_id, turn_no)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_committee_entries_committee ON committee_entries(committee_id, entry_date DESC)');
  }


  static Future<List<Map<String, dynamic>>> getCommittees() async {
    await _ensureSchema();
    return DatabaseManager.instance.database.rawQuery('''
      SELECT c.*,
        (SELECT COUNT(*) FROM committee_members m WHERE m.committee_id=c.id) AS actual_members,
        COALESCE((SELECT SUM(e.amount) FROM committee_entries e WHERE e.committee_id=c.id AND e.entry_type='Installment'),0) AS collected,
        COALESCE((SELECT SUM(e.amount) FROM committee_entries e WHERE e.committee_id=c.id AND e.entry_type='Payout'),0) AS paid_out,
        COALESCE((SELECT SUM(CASE WHEN e.entry_type='Installment' THEN e.amount ELSE -e.amount END)
          FROM committee_entries e WHERE e.committee_id=c.id),0) AS available_balance
      FROM committees c ORDER BY c.created_at DESC, c.id DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getMembers(int committeeId) async {
    await _ensureSchema();
    return DatabaseManager.instance.database.rawQuery('''
      SELECT m.*,
        COALESCE((SELECT SUM(e.amount) FROM committee_entries e WHERE e.member_id=m.id AND e.entry_type='Installment'),0) AS paid,
        COALESCE((SELECT SUM(e.amount) FROM committee_entries e WHERE e.member_id=m.id AND e.entry_type='Payout'),0) AS received
      FROM committee_members m WHERE m.committee_id=? ORDER BY m.turn_no, m.id
    ''', [committeeId]);
  }

  static Future<List<Map<String, dynamic>>> getEntries(int committeeId) async {
    await _ensureSchema();
    return DatabaseManager.instance.database.rawQuery('''
      SELECT e.*, m.name AS member_name, w.name AS wallet_name,
        COALESCE(NULLIF(e.wallet_currency,''), w.currency) AS wallet_currency
      FROM committee_entries e
      LEFT JOIN committee_members m ON m.id=e.member_id
      LEFT JOIN wallets w ON w.id=e.wallet_id
      WHERE e.committee_id=? ORDER BY e.entry_date DESC, e.id DESC
    ''', [committeeId]);
  }

  static Future<int> createCommittee({
    required String name, required String frequency,
    required double installmentAmount, required List<Map<String, String>> members,
    required DateTime startDate, required DateTime firstDueDate,
  }) async {
    await _ensureSchema();
    if (name.trim().isEmpty || installmentAmount <= 0 || !installmentAmount.isFinite ||
        members.length < 2 || !['Daily', 'Weekly', 'Monthly'].contains(frequency) ||
        firstDueDate.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) {
      throw Exception('Enter a name, valid installment and at least two members.');
    }
    final db = DatabaseManager.instance.database;
    final currency = await CurrencyService.getBaseCurrency();
    final now = DateTime.now().toIso8601String();
    final id = await db.transaction((txn) async {
      final committeeId = await txn.insert('committees', {
        'name': name.trim(), 'frequency': frequency, 'installment_amount': installmentAmount,
        'member_count': members.length, 'currency': currency,
        'start_date': startDate.toIso8601String(), 'first_due_date': firstDueDate.toIso8601String(),
        'status': startDate.isAfter(DateTime.now()) ? 'Upcoming' : 'Active', 'created_at': now,
      });
      for (var i = 0; i < members.length; i++) {
        await txn.insert('committee_members', {
          'committee_id': committeeId, 'name': members[i]['name']!.trim(),
          'phone': members[i]['phone']?.trim(), 'turn_no': i + 1, 'created_at': now,
        });
      }
      return committeeId;
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  static Future<void> addMember(int committeeId, String name, String phone) async {
    await _ensureSchema();
    if (name.trim().isEmpty) throw Exception('Enter member name.');
    final db = DatabaseManager.instance.database;
    final entryCount = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM committee_entries WHERE committee_id=?', [committeeId])) ?? 0;
    if (entryCount > 0) throw Exception('Members cannot be added after committee transactions have started.');
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM committee_members WHERE committee_id=?', [committeeId])) ?? 0;
    await db.insert('committee_members', {
      'committee_id': committeeId, 'name': name.trim(), 'phone': phone.trim(),
      'turn_no': count + 1, 'created_at': DateTime.now().toIso8601String(),
    });
    await db.update('committees', {'member_count': count + 1}, where: 'id=?', whereArgs: [committeeId]);
    AppRefreshController.notifyChanged();
  }

  static Future<void> reorderMembers(int committeeId, List<int> orderedMemberIds) async {
    await _ensureSchema();
    final db = DatabaseManager.instance.database;
    await db.transaction((txn) async {
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM committee_entries WHERE committee_id=?', [committeeId])) ?? 0;
      if (count > 0) throw Exception('Turn order is locked after committee activity starts.');
      final rows = await txn.query('committee_members', columns: ['id'],
        where: 'committee_id=?', whereArgs: [committeeId]);
      final existing = rows.map((r) => (r['id'] as num).toInt()).toSet();
      if (orderedMemberIds.length != existing.length || orderedMemberIds.toSet().length != existing.length ||
          !orderedMemberIds.toSet().containsAll(existing)) throw Exception('Invalid member turn order.');
      for (var i = 0; i < orderedMemberIds.length; i++) {
        await txn.update('committee_members', {'turn_no': i + 1},
          where: 'id=? AND committee_id=?', whereArgs: [orderedMemberIds[i], committeeId]);
      }
    });
    AppRefreshController.notifyChanged();
  }

  static Future<int> recordEntry({
    required int committeeId, required int memberId, required String entryType,
    required double amount, int? walletId, required DateTime date, String note = '',
  }) async {
    await _ensureSchema();
    if (!amount.isFinite || amount <= 0 || !['Installment', 'Payout'].contains(entryType)) {
      throw Exception('Enter a valid amount.');
    }
    final db = DatabaseManager.instance.database;
    final result = await db.transaction((txn) async {
      final committeeRows = await txn.query('committees', where: 'id=?', whereArgs: [committeeId], limit: 1);
      final memberRows = await txn.query('committee_members',
        where: 'id=? AND committee_id=?', whereArgs: [memberId, committeeId], limit: 1);
      if (committeeRows.isEmpty || memberRows.isEmpty) throw Exception('Committee or member not found.');
      final committee = committeeRows.first;
      final member = memberRows.first;
      final committeeCurrency = (committee['currency'] ?? 'PKR').toString().toUpperCase();
      final selectedWalletRows = walletId == null ? <Map<String, Object?>>[] :
        await txn.query('wallets', where: 'id=?', whereArgs: [walletId], limit: 1);
      if (walletId != null && selectedWalletRows.isEmpty) throw Exception('Selected wallet was not found.');
      final wallet = selectedWalletRows.isEmpty ? null : selectedWalletRows.first;
      final walletCurrency = (wallet?['currency'] ?? '').toString().toUpperCase();
      double walletAmount = 0;
      if (wallet != null) {
        final currencies = await txn.query('exchange_rates',
          where: 'currency IN (?, ?)', whereArgs: [committeeCurrency, walletCurrency]);
        double? rateFor(String currency) {
          if (currency == 'PKR') return 1;
          for (final row in currencies) {
            if (row['currency'] == currency) return (row['rate'] as num).toDouble();
          }
          return null;
        }
        final committeeRate = rateFor(committeeCurrency);
        final walletRate = rateFor(walletCurrency);
        if (committeeRate == null || walletRate == null || committeeRate <= 0 || walletRate <= 0) {
          throw Exception('Exchange rate is not available for the selected wallet currency.');
        }
        walletAmount = amount * committeeRate / walletRate;
      }

      final pot = (committee['installment_amount'] as num).toDouble() *
        (committee['member_count'] as num).toInt();
      final previousRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS total FROM committee_entries WHERE committee_id=? AND member_id=? AND entry_type=?',
        [committeeId, memberId, entryType]);
      final previous = (previousRows.first['total'] as num).toDouble();
      if (previous + amount > pot + 0.000001) {
        throw Exception(entryType == 'Installment'
          ? 'This member has already paid the full committee contribution.'
          : 'Payout cannot exceed this member\'s scheduled committee amount.');
      }

      if (entryType == 'Payout') {
        final balanceRows = await txn.rawQuery('''
          SELECT COALESCE(SUM(CASE WHEN entry_type='Installment' THEN amount ELSE -amount END),0) AS balance
          FROM committee_entries WHERE committee_id=?
        ''', [committeeId]);
        final available = (balanceRows.first['balance'] as num).toDouble();
        if (available + 0.000001 < amount) {
          throw Exception('Insufficient committee balance. Available: $committeeCurrency ${available.toStringAsFixed(2)}');
        }
        final ordered = await txn.query('committee_members',
          where: 'committee_id=?', whereArgs: [committeeId], orderBy: 'turn_no ASC');
        int? nextMember;
        for (final candidate in ordered) {
          final paidRows = await txn.rawQuery(
            "SELECT COALESCE(SUM(amount),0) AS total FROM committee_entries WHERE committee_id=? AND member_id=? AND entry_type='Payout'",
            [committeeId, candidate['id']]);
          if ((paidRows.first['total'] as num).toDouble() < pot - 0.000001) {
            nextMember = (candidate['id'] as num).toInt();
            break;
          }
        }
        if (nextMember != memberId) throw Exception('Payout must follow the fixed turn order. Complete the current member\'s payout first.');
      }

      if (wallet != null) {
        final current = (wallet['balance'] as num).toDouble();
        if (entryType == 'Installment' && current + 0.000001 < walletAmount) {
          throw Exception('Insufficient wallet balance. Available: $walletCurrency ${current.toStringAsFixed(2)}');
        }
        await txn.update('wallets', {'balance': current + (entryType == 'Installment' ? -walletAmount : walletAmount)},
          where: 'id=?', whereArgs: [walletId]);
      }

      final now = DateTime.now().toIso8601String();
      int? transactionId;
      if (wallet != null) {
        final delta = entryType == 'Installment' ? -walletAmount : walletAmount;
        transactionId = await TransactionsService.insertLedgerEntry(txn, {
          'type': 'Transfer', 'amount': walletAmount, 'wallet_id': walletId,
          'to_wallet_id': null, 'to_amount': null, 'exchange_rate': null,
          'balance_delta': delta, 'category': 'Committee Transfer',
          'note': '${committee['name']} • ${member['name']} • $entryType',
          'date': date.toIso8601String(), 'created_at': now,
        });
      }
      final entryId = await txn.insert('committee_entries', {
        'committee_id': committeeId, 'member_id': memberId, 'entry_type': entryType,
        'amount': amount, 'wallet_amount': walletAmount, 'committee_currency': committeeCurrency,
        'wallet_id': walletId ?? -1, 'wallet_currency': walletCurrency,
        'payment_method': wallet == null ? 'None' : 'Wallet',
        'transaction_id': transactionId, 'entry_date': date.toIso8601String(),
        'note': note.trim(), 'created_at': now,
      });
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM committee_entries WHERE committee_id=?', [committeeId])) ?? 0;
      if (count > 0) await txn.update('committees', {'status': 'Active'}, where: 'id=?', whereArgs: [committeeId]);
      final completed = Sqflite.firstIntValue(await txn.rawQuery('''
        SELECT COUNT(*) FROM committee_members m
        WHERE m.committee_id=? AND COALESCE((SELECT SUM(e.amount) FROM committee_entries e
          WHERE e.member_id=m.id AND e.entry_type='Payout'),0) >= ?
      ''', [committeeId, pot - 0.000001])) ?? 0;
      if (completed >= (committee['member_count'] as num).toInt()) {
        await txn.update('committees', {'status': 'Completed'}, where: 'id=?', whereArgs: [committeeId]);
      }
      return entryId;
    });
    AppRefreshController.notifyChanged();
    return result;
  }

  static Future<void> deleteCommittee(int committeeId) async {
    await _ensureSchema();
    final db = DatabaseManager.instance.database;
    final committees = await db.query('committees', where: 'id=?', whereArgs: [committeeId], limit: 1);
    if (committees.isEmpty) return;
    final committee = Map<String,dynamic>.from(committees.first);
    final members = await db.query('committee_members', where: 'committee_id=?', whereArgs: [committeeId]);
    final entries = await db.query('committee_entries', where: 'committee_id=?', whereArgs: [committeeId]);
    final txIds = entries.map((e) => e['transaction_id']).whereType<int>().toList();
    final finance = await TransactionsService.getLedgerEntriesByIds(db, txIds);
    await RecycleBinArchiveService.archive(
      type: 'Committee', title: committee['name']?.toString() ?? 'Committee',
      table: 'committees', id: committeeId, record: committee,
      related: [
        ...members.map((e) => {'_related_table':'committee_members', ...Map<String,dynamic>.from(e)}),
        ...entries.map((e) => {'_related_table':'committee_entries', ...Map<String,dynamic>.from(e)}),
        ...finance.map((e) => {'_related_table':'transactions', ...Map<String,dynamic>.from(e)}),
      ],
    );
    await db.transaction((txn) async {
      await TransactionsService.deleteCommitteeLedgerEntries(
        txn,
        finance.map((row) => Map<String, dynamic>.from(row)).toList(),
      );
      await txn.delete('committee_entries', where: 'committee_id=?', whereArgs: [committeeId]);
      await txn.delete('committee_members', where: 'committee_id=?', whereArgs: [committeeId]);
      await txn.delete('committees', where: 'id=?', whereArgs: [committeeId]);
    });
    AppRefreshController.notifyChanged();
  }

  static Future<void> updateStatus(int committeeId, String status) async {
    await _ensureSchema();
    if (!['Upcoming', 'Active', 'Completed'].contains(status)) throw Exception('Invalid status.');
    await DatabaseManager.instance.database.update('committees', {'status': status}, where: 'id=?', whereArgs: [committeeId]);
    AppRefreshController.notifyChanged();
  }
  /// Restores the archived committees record and related ledger entries atomically.
  static Future<void> restoreArchivedCommittee(
    Transaction txn, {
    required Map<String, dynamic> record,
    String? relatedPayload,
  }) async {
        await txn.execute("""CREATE TABLE IF NOT EXISTS committees (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          frequency TEXT NOT NULL, installment_amount REAL NOT NULL,
          member_count INTEGER NOT NULL, currency TEXT NOT NULL DEFAULT 'PKR',
          start_date TEXT NOT NULL, first_due_date TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'Upcoming', created_at TEXT NOT NULL)""");
        await txn.execute("""CREATE TABLE IF NOT EXISTS committee_members (
          id INTEGER PRIMARY KEY AUTOINCREMENT, committee_id INTEGER NOT NULL,
          name TEXT NOT NULL, phone TEXT, turn_no INTEGER NOT NULL, created_at TEXT NOT NULL)""");
        await txn.execute("""CREATE TABLE IF NOT EXISTS committee_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT, committee_id INTEGER NOT NULL,
          member_id INTEGER NOT NULL, entry_type TEXT NOT NULL, amount REAL NOT NULL,
          wallet_amount REAL NOT NULL DEFAULT 0, committee_currency TEXT NOT NULL DEFAULT 'PKR',
          wallet_currency TEXT NOT NULL DEFAULT '', payment_method TEXT NOT NULL DEFAULT 'None',
          wallet_id INTEGER NOT NULL DEFAULT -1, transaction_id INTEGER,
          entry_date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)""");
        final duplicate = await txn.query('committees', columns: ['id'],
          where: 'id=?', whereArgs: [record['id']], limit: 1);
        if (duplicate.isNotEmpty) throw Exception('This committee already exists.');
        final related = (jsonDecode(relatedPayload ?? '[]') as List)
          .whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
        final members = related.where((e) => e['_related_table']=='committee_members').toList();
        final entries = related.where((e) => e['_related_table']=='committee_entries').toList();
        final finance = related.where((e) => e['_related_table']=='transactions').toList();
        await TransactionsService.restoreCommitteeLedgerEntries(txn, finance);
        await txn.insert('committees', record);
        for (final row in members) { row.remove('_related_table'); await txn.insert('committee_members', row); }

        for (final row in entries) { row.remove('_related_table'); await txn.insert('committee_entries', row); }
        return;
  }

}
