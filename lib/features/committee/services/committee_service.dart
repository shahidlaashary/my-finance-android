import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

/// Committee data and wallet ledger. All cash movements and committee ledger
/// records are committed atomically to the existing finance database.
class CommitteeService {
  static Future<void> _ensureSchema() async {
    final db = FinanceDB.instance.db;
    await db.execute('''CREATE TABLE IF NOT EXISTS committees (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      frequency TEXT NOT NULL, installment_amount REAL NOT NULL,
      member_count INTEGER NOT NULL, start_date TEXT NOT NULL,
      first_due_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'Upcoming',
      created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS committee_members (
      id INTEGER PRIMARY KEY AUTOINCREMENT, committee_id INTEGER NOT NULL,
      name TEXT NOT NULL, phone TEXT, turn_no INTEGER NOT NULL,
      created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS committee_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT, committee_id INTEGER NOT NULL,
      member_id INTEGER NOT NULL, entry_type TEXT NOT NULL,
      amount REAL NOT NULL, wallet_id INTEGER NOT NULL,
      transaction_id INTEGER, entry_date TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_committee_members_committee ON committee_members(committee_id, turn_no)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_committee_entries_committee ON committee_entries(committee_id, entry_date DESC)');
  }

  static Future<int> getSharedWalletId({required bool create}) async {
    await _ensureSchema();
    final db = FinanceDB.instance.db;
    final saved = await db.query('app_settings', columns: ['setting_value'],
      where: 'setting_key = ?', whereArgs: ['committee_shared_wallet_id'], limit: 1);
    if (saved.isNotEmpty) {
      final id = int.tryParse(saved.first['setting_value']?.toString() ?? '');
      if (id != null) {
        final exists = await db.query('wallets', where: 'id = ?', whereArgs: [id], limit: 1);
        if (exists.isNotEmpty) return id;
      }
    }
    if (!create) return -1;
    return db.transaction((txn) async {
      final again = await txn.query('app_settings', columns: ['setting_value'],
        where: 'setting_key = ?', whereArgs: ['committee_shared_wallet_id'], limit: 1);
      if (again.isNotEmpty) {
        final id = int.tryParse(again.first['setting_value']?.toString() ?? '');
        if (id != null) {
          final rows = await txn.query('wallets', where: 'id = ?', whereArgs: [id], limit: 1);
          if (rows.isNotEmpty) return id;
        }
      }
      final currencyRows = await txn.query('app_settings', columns: ['setting_value'],
        where: 'setting_key = ?', whereArgs: ['main_currency'], limit: 1);
      final currency = currencyRows.isEmpty ? 'PKR' : (currencyRows.first['setting_value']?.toString() ?? 'PKR');
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('wallets', {
        'name': 'Committee', 'type': 'Other', 'custom_type': 'Committee',
        'currency': currency, 'balance': 0.0, 'opening_balance': 0.0,
        'wallet_number': null, 'icon_code': Icons.groups_rounded.codePoint,
        'exclude_total': 0, 'created_at': now,
      });
      await txn.insert('app_settings', {
        'setting_key': 'committee_shared_wallet_id', 'setting_value': id.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return id;
    });
  }

  static Future<List<Map<String, dynamic>>> getCommittees() async {
    await _ensureSchema();
    return FinanceDB.instance.db.rawQuery('''
      SELECT c.*,
        (SELECT COUNT(*) FROM committee_members m WHERE m.committee_id=c.id) AS actual_members,
        COALESCE((SELECT SUM(e.amount) FROM committee_entries e WHERE e.committee_id=c.id AND e.entry_type='Installment'),0) AS collected,
        COALESCE((SELECT SUM(e.amount) FROM committee_entries e WHERE e.committee_id=c.id AND e.entry_type='Payout'),0) AS paid_out
      FROM committees c ORDER BY c.created_at DESC, c.id DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getMembers(int committeeId) async {
    await _ensureSchema();
    return FinanceDB.instance.db.rawQuery('''
      SELECT m.*,
        COALESCE((SELECT SUM(e.amount) FROM committee_entries e WHERE e.member_id=m.id AND e.entry_type='Installment'),0) AS paid,
        COALESCE((SELECT SUM(e.amount) FROM committee_entries e WHERE e.member_id=m.id AND e.entry_type='Payout'),0) AS received
      FROM committee_members m WHERE m.committee_id=? ORDER BY m.turn_no, m.id
    ''', [committeeId]);
  }

  static Future<List<Map<String, dynamic>>> getEntries(int committeeId) async {
    await _ensureSchema();
    return FinanceDB.instance.db.rawQuery('''
      SELECT e.*, m.name AS member_name, w.name AS wallet_name, w.currency AS wallet_currency
      FROM committee_entries e
      LEFT JOIN committee_members m ON m.id=e.member_id
      LEFT JOIN wallets w ON w.id=e.wallet_id
      WHERE e.committee_id=? ORDER BY e.entry_date DESC, e.id DESC
    ''', [committeeId]);
  }

  static Future<List<Map<String, dynamic>>> getWallets() async {
    return FinanceDB.instance.getWallets();
  }

  static Future<int> createCommittee({
    required String name, required String frequency,
    required double installmentAmount, required List<Map<String, String>> members,
    required DateTime startDate, required DateTime firstDueDate,
  }) async {
    await _ensureSchema();
    if (name.trim().isEmpty || installmentAmount <= 0 || !installmentAmount.isFinite || members.length < 2) {
      throw Exception('Enter a name, valid installment and at least two members.');
    }
    final db = FinanceDB.instance.db;
    final now = DateTime.now().toIso8601String();
    final id = await db.transaction((txn) async {
      final committeeId = await txn.insert('committees', {
        'name': name.trim(), 'frequency': frequency, 'installment_amount': installmentAmount,
        'member_count': members.length, 'start_date': startDate.toIso8601String(),
        'first_due_date': firstDueDate.toIso8601String(),
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
    await getSharedWalletId(create: true);
    AppRefreshController.notifyChanged();
    return id;
  }

  static Future<void> addMember(int committeeId, String name, String phone) async {
    await _ensureSchema();
    if (name.trim().isEmpty) throw Exception('Enter member name.');
    final db = FinanceDB.instance.db;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM committee_members WHERE committee_id=?', [committeeId])) ?? 0;
    await db.insert('committee_members', {
      'committee_id': committeeId, 'name': name.trim(), 'phone': phone.trim(),
      'turn_no': count + 1, 'created_at': DateTime.now().toIso8601String(),
    });
    await db.update('committees', {'member_count': count + 1}, where: 'id=?', whereArgs: [committeeId]);
    AppRefreshController.notifyChanged();
  }

  static Future<int> recordEntry({
    required int committeeId, required int memberId, required String entryType,
    required double amount, required int walletId, required DateTime date, String note = '',
  }) async {
    await _ensureSchema();
    if (!amount.isFinite || amount <= 0 || !['Installment', 'Payout'].contains(entryType)) {
      throw Exception('Enter a valid amount.');
    }
    final db = FinanceDB.instance.db;
    final result = await db.transaction((txn) async {
      final committee = await txn.query('committees', where: 'id=?', whereArgs: [committeeId], limit: 1);
      final member = await txn.query('committee_members', where: 'id=? AND committee_id=?',
        whereArgs: [memberId, committeeId], limit: 1);
      final wallets = await txn.query('wallets', where: 'id=?', whereArgs: [walletId], limit: 1);
      if (committee.isEmpty || member.isEmpty || wallets.isEmpty) throw Exception('Committee, member or wallet not found.');
      final wallet = wallets.first;
      final balance = (wallet['balance'] as num).toDouble();
      if (entryType == 'Payout' && balance + 0.000001 < amount) {
        throw Exception('Insufficient balance. Available: ${wallet['currency']} ${balance.toStringAsFixed(2)}');
      }
      await txn.update('wallets', {'balance': balance + (entryType == 'Installment' ? amount : -amount)},
        where: 'id=?', whereArgs: [walletId]);
      final now = DateTime.now().toIso8601String();
      final transactionId = await txn.insert('transactions', {
        'type': 'Committee', 'amount': amount, 'wallet_id': walletId,
        'to_wallet_id': null, 'to_amount': null, 'exchange_rate': null, 'balance_delta': null,
        'category': entryType == 'Installment' ? 'Committee Installment' : 'Committee Payout',
        'note': '${committee.first['name']} • ${member.first['name']} • ${entryType == 'Installment' ? 'Installment' : 'Payout'}',
        'date': date.toIso8601String(), 'created_at': now,
      });
      final entryId = await txn.insert('committee_entries', {
        'committee_id': committeeId, 'member_id': memberId, 'entry_type': entryType,
        'amount': amount, 'wallet_id': walletId, 'transaction_id': transactionId,
        'entry_date': date.toIso8601String(), 'note': note.trim(), 'created_at': now,
      });
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM committee_entries WHERE committee_id=?', [committeeId])) ?? 0;
      if (count > 0) {
        await txn.update('committees', {'status': 'Active'}, where: 'id=?', whereArgs: [committeeId]);
      }
      return entryId;
    });
    AppRefreshController.notifyChanged();
    return result;
  }

  static Future<void> updateStatus(int committeeId, String status) async {
    await _ensureSchema();
    if (!['Upcoming', 'Active', 'Completed'].contains(status)) throw Exception('Invalid status.');
    await FinanceDB.instance.db.update('committees', {'status': status}, where: 'id=?', whereArgs: [committeeId]);
    AppRefreshController.notifyChanged();
  }

  static Future<int> sharedWalletId() => getSharedWalletId(create: false);
}
