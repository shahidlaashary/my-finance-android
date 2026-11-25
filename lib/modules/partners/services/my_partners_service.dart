import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

class MyPartnersService {
  MyPartnersService._();
  static final MyPartnersService instance = MyPartnersService._();

  Future<void> _ensureTables() async {
    final db = DatabaseManager.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS partners (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('Business', 'Personal')),
        phone TEXT,
        notes TEXT NOT NULL DEFAULT '',
        profit_share REAL NOT NULL DEFAULT 50,
        opening_balance REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS partners_wallet_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        partner_id INTEGER NOT NULL,
        wallet_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(partner_id, wallet_id),
        FOREIGN KEY(partner_id) REFERENCES partners(id) ON DELETE CASCADE,
        FOREIGN KEY(wallet_id) REFERENCES wallets(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS partners_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        partner_id INTEGER NOT NULL,
        wallet_id INTEGER,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        balance_delta REAL NOT NULL DEFAULT 0,
        category TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(partner_id) REFERENCES partners(id),
        FOREIGN KEY(wallet_id) REFERENCES wallets(id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_partners_tx_partner_date ON partners_transactions(partner_id, date DESC)');
    // Repair legacy ledger rows created with the old reversed sign mapping.
    // Transfer entries are intentionally excluded because their signs are already correct.
    await db.execute("""
      UPDATE partners_transactions
      SET balance_delta = CASE type
        WHEN 'Money Given' THEN -amount
        WHEN 'Money Received' THEN amount
        WHEN 'Partner Contribution' THEN -amount
        WHEN 'Shared Expense' THEN amount
        WHEN 'Partner Withdrawal' THEN amount
        WHEN 'Profit Received' THEN -amount
        WHEN 'Profit Paid' THEN amount
        ELSE balance_delta
      END
      WHERE type IN ('Money Given','Money Received','Partner Contribution',
        'Shared Expense','Partner Withdrawal','Profit Received','Profit Paid')
    """);

  }

  Future<List<Map<String, dynamic>>> getWallets() {
    return WalletService.getWallets();
  }

  Future<List<Map<String, dynamic>>> getPartners() async {
    await _ensureTables();
    return DatabaseManager.instance.database.rawQuery('''
      SELECT p.*,
        COALESCE((SELECT SUM(t.balance_delta) FROM partners_transactions t WHERE t.partner_id = p.id), 0) AS ledger_balance,
        p.opening_balance + COALESCE((SELECT SUM(t.balance_delta) FROM partners_transactions t WHERE t.partner_id = p.id), 0) AS current_balance,
        (SELECT COUNT(*) FROM partners_transactions t WHERE t.partner_id = p.id) AS transaction_count
      FROM partners p
      ORDER BY p.is_active DESC, p.name COLLATE NOCASE
    ''');
  }

  Future<int> savePartner({
    int? id,
    required String name,
    required String type,
    String? phone,
    required String notes,
    required double profitShare,
    required double openingBalance,
  }) async {
    await _ensureTables();
    if (name.trim().isEmpty) throw Exception('Partner name is required.');
    if (!profitShare.isFinite || profitShare < 0 || profitShare > 100) {
      throw Exception('Profit share must be between 0 and 100%.');
    }
    final values = {
      'name': name.trim(),
      'type': type,
      'phone': phone?.trim(),
      'notes': notes.trim(),
      'profit_share': profitShare,
      'opening_balance': openingBalance,
    };
    final db = DatabaseManager.instance.database;
    int result;
    if (id == null) {
      result = await db.insert('partners', {
        ...values,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      await db.update('partners', values, where: 'id = ?', whereArgs: [id]);
      result = id;
    }
    AppRefreshController.notifyChanged();
    return result;
  }

  Future<void> setActive(int id, bool active) async {
    await _ensureTables();
    await DatabaseManager.instance.database.update(
      'partners', {'is_active': active ? 1 : 0},
      where: 'id = ?', whereArgs: [id],
    );
    AppRefreshController.notifyChanged();
  }

  Future<List<Map<String, dynamic>>> getWalletLinks(int partnerId) async {
    await _ensureTables();
    return DatabaseManager.instance.database.rawQuery('''
      SELECT w.*, l.id AS link_id FROM partners_wallet_links l
      INNER JOIN wallets w ON w.id = l.wallet_id
      WHERE l.partner_id = ? ORDER BY w.name COLLATE NOCASE
    ''', [partnerId]);
  }

  Future<void> setWalletLinks(int partnerId, List<int> walletIds) async {
    await _ensureTables();
    final db = DatabaseManager.instance.database;
    await db.transaction((txn) async {
      await txn.delete('partners_wallet_links', where: 'partner_id = ?', whereArgs: [partnerId]);
      for (final walletId in walletIds.toSet()) {
        await txn.insert('partners_wallet_links', {
          'partner_id': partnerId,
          'wallet_id': walletId,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm:  ConflictAlgorithm.ignore);
      }
    });
    AppRefreshController.notifyChanged();
  }

  Future<List<Map<String, dynamic>>> getTransactions(int partnerId) async {
    await _ensureTables();
    return DatabaseManager.instance.database.rawQuery('''
      SELECT t.*, w.name AS wallet_name, w.currency AS currency
      FROM partners_transactions t
      LEFT JOIN wallets w ON w.id = t.wallet_id
      WHERE t.partner_id = ? ORDER BY t.date DESC, t.id DESC
    ''', [partnerId]);
  }

  Future<void> deletePartner(int partnerId) async {
    await _ensureTables();
    final db = DatabaseManager.instance.database;
    final partners = await db.query('partners', where: 'id=?', whereArgs: [partnerId], limit: 1);
    if (partners.isEmpty) return;
    final partner = Map<String,dynamic>.from(partners.first);
    final links = await db.query('partners_wallet_links', where: 'partner_id=?', whereArgs: [partnerId]);
    final history = await db.query('partners_transactions', where: 'partner_id=?', whereArgs: [partnerId]);
    final financeRows = await db.query('transactions',
      where: "category LIKE 'My Partner%' AND note IN (SELECT note FROM partners_transactions WHERE partner_id=?)",
      whereArgs: [partnerId]);
    await RecycleBinService.archive(
      type: 'Partner', title: partner['name']?.toString() ?? 'Partner',
      table: 'partners', id: partnerId, record: partner,
      related: [
        ...links.map((e) => {'_related_table':'partners_wallet_links', ...Map<String,dynamic>.from(e)}),
        ...history.map((e) => {'_related_table':'partners_transactions', ...Map<String,dynamic>.from(e)}),
        ...financeRows.map((e) => {'_related_table':'transactions', ...Map<String,dynamic>.from(e)}),
      ],
    );
    await db.transaction((txn) async {
      for (final row in financeRows) {
        final amount = (row['amount'] as num).toDouble();
        final delta = row['type']?.toString().toLowerCase() == 'income' ? -amount : amount;
        await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id=?', [delta, row['wallet_id']]);
      }
      await txn.delete('transactions',
        where: "category LIKE 'My Partner%' AND note IN (SELECT note FROM partners_transactions WHERE partner_id=?)",
        whereArgs: [partnerId]);
      await txn.delete('partners_transactions', where: 'partner_id=?', whereArgs: [partnerId]);
      await txn.delete('partners_wallet_links', where: 'partner_id=?', whereArgs: [partnerId]);
      await txn.delete('partners', where: 'id=?', whereArgs: [partnerId]);
    });
    AppRefreshController.notifyChanged();
  }

  Future<void> transferWithPartner({
    required int partnerId,
    required int walletId,
    required double amount,
    required bool walletToPartner,
    required String note,
    required DateTime date,
  }) async {
    await _ensureTables();
    if (!amount.isFinite || amount <= 0) throw Exception('Enter a valid transfer amount.');
    final db = DatabaseManager.instance.database;
    await db.transaction((txn) async {
      final walletRows = await txn.query('wallets', where: 'id = ?', whereArgs: [walletId], limit: 1);
      if (walletRows.isEmpty) throw Exception('Selected wallet not found.');
      final walletBalance = (walletRows.first['balance'] as num).toDouble();
      final walletDelta = walletToPartner ? -amount : amount;
      if (walletDelta < 0 && walletBalance + walletDelta < -0.000001) {
        throw Exception('Insufficient wallet balance.');
      }
      await txn.update('wallets', {'balance': walletBalance + walletDelta}, where: 'id = ?', whereArgs: [walletId]);
      await txn.insert('transactions', {
        'type': walletToPartner ? 'Expense' : 'Income',
        'amount': amount,
        'wallet_id': walletId,
        'to_wallet_id': null,
        'to_amount': null,
        'exchange_rate': null,
        'balance_delta': null,
        'category': walletToPartner ? 'My Partner Transfer Out' : 'My Partner Transfer In',
        'note': note.trim(),
        'date': date.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.insert('partners_transactions', {
        'partner_id': partnerId,
        'wallet_id': walletId,
        'type': walletToPartner ? 'Wallet Transfer In' : 'Wallet Transfer Out',
        'amount': amount,
        'balance_delta': walletToPartner ? amount : -amount,
        'category': 'Wallet Transfer',
        'note': note.trim(),
        'date': date.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    AppRefreshController.notifyChanged();
  }

  Future<void> addTransaction({
    required int partnerId,
    required String type,
    required double amount,
    required int? walletId,
    required String category,
    required String note,
    required DateTime date,
  }) async {
    await _ensureTables();
    if (!amount.isFinite || amount <= 0) throw Exception('Enter a valid amount.');
    // Types are named from the PARTNER's perspective:
    // Money Given = partner gives us (wallet IN); Money Received = partner
    // receives from us (wallet OUT). Positive ledger = partner owes us.
    final partnerDeltaByType = <String, double Function(double)>{
      'Money Given': (v) => -v,
      'Money Received': (v) => v,
      'Partner Contribution': (v) => -v,
      'Shared Expense': (v) => v,
      'Partner Withdrawal': (v) => v,
      'Profit Received': (v) => -v,
      'Profit Paid': (v) => v,
    };
    const walletInTypes = <String>{'Money Given', 'Partner Contribution', 'Profit Received'};
    const walletOutTypes = <String>{'Money Received', 'Shared Expense', 'Partner Withdrawal', 'Profit Paid'};
    final deltaFn = partnerDeltaByType[type];
    if (deltaFn == null) throw Exception('Invalid transaction type.');
    final delta = deltaFn(amount);
    final db = DatabaseManager.instance.database;
    await db.transaction((txn) async {
      if (walletId != null) {
        final rows = await txn.query('wallets', where: 'id = ?', whereArgs: [walletId], limit: 1);
        if (rows.isEmpty) throw Exception('Selected wallet not found.');
        final current = (rows.first['balance'] as num).toDouble();
        final walletIn = walletInTypes.contains(type);
        if (!walletIn && !walletOutTypes.contains(type)) throw Exception('Invalid wallet transaction type.');
        final walletDelta = walletIn ? amount : -amount;
        if (walletDelta < 0 && current + walletDelta < -0.000001) {
          throw Exception('Insufficient wallet balance.');
        }
        await txn.update('wallets', {'balance': current + walletDelta}, where: 'id = ?', whereArgs: [walletId]);
        await txn.insert('transactions', {
          'type': walletIn ? 'Income' : 'Expense',
          'amount': amount,
          'wallet_id': walletId,
          'to_wallet_id': null,
          'to_amount': null,
          'exchange_rate': null,
          'balance_delta': null,
          'category': 'My Partner - ' + type,
          'note': note.trim(),
          'date': date.toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      await txn.insert('partners_transactions', {
        'partner_id': partnerId,
        'wallet_id': walletId,
        'type': type,
        'amount': amount,
        'balance_delta': delta,
        'category': category,
        'note': note,
        'date': date.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    AppRefreshController.notifyChanged();
  }
  /// Restores the archived partners record and related ledger entries atomically.
  static Future<void> restoreArchivedPartner(
    Transaction txn, {
    required Map<String, dynamic> record,
    String? relatedPayload,
  }) async {
        await txn.execute("""CREATE TABLE IF NOT EXISTS partners (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          type TEXT NOT NULL CHECK(type IN ('Business','Personal')),
          phone TEXT, notes TEXT NOT NULL DEFAULT '', profit_share REAL NOT NULL DEFAULT 50,
          opening_balance REAL NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL)""");
        await txn.execute("""CREATE TABLE IF NOT EXISTS partners_wallet_links (
          id INTEGER PRIMARY KEY AUTOINCREMENT, partner_id INTEGER NOT NULL,
          wallet_id INTEGER NOT NULL, created_at TEXT NOT NULL,
          UNIQUE(partner_id,wallet_id))""");
        await txn.execute("""CREATE TABLE IF NOT EXISTS partners_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT, partner_id INTEGER NOT NULL,
          wallet_id INTEGER, type TEXT NOT NULL, amount REAL NOT NULL,
          balance_delta REAL NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '', date TEXT NOT NULL, created_at TEXT NOT NULL)""");
        final duplicate = await txn.query('partners', columns: ['id'],
          where: 'id=?', whereArgs: [record['id']], limit: 1);
        if (duplicate.isNotEmpty) throw Exception('This partner already exists.');
        final related = (jsonDecode(relatedPayload ?? '[]') as List)
          .whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
        final links = related.where((e) => e['_related_table']=='partners_wallet_links' || e['_related_table']=='partner_wallet_links').toList();
        final ledger = related.where((e) => e['_related_table']=='partners_transactions' || e['_related_table']=='partner_transactions').toList();
        final finance = related.where((e) => e['_related_table']=='transactions').toList();
        for (final row in finance) {
          final walletId = (row['wallet_id'] as num?)?.toInt();
          if (walletId == null) continue;
          final amount = (row['amount'] as num).toDouble();
          final delta = row['type']?.toString().toLowerCase() == 'income' ? amount : -amount;
          final wallet = await txn.query('wallets', columns: ['balance'],
            where: 'id=?', whereArgs: [walletId], limit: 1);
          if (wallet.isEmpty) throw Exception('A linked partner wallet no longer exists.');
          if (delta < 0 && (wallet.first['balance'] as num).toDouble() < -delta) {
            throw Exception('Insufficient wallet balance to restore partner transactions.');
          }
          await txn.rawUpdate('UPDATE wallets SET balance=balance+? WHERE id=?', [delta,walletId]);
        }
        await txn.insert('partners', record);
        for (final row in links) { row.remove('_related_table'); await txn.insert('partners_wallet_links', row); }
        for (final row in ledger) { row.remove('_related_table'); await txn.insert('partners_transactions', row); }
        for (final row in finance) { row.remove('_related_table'); await txn.insert('transactions', row); }
        return;
  }

}
