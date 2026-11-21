import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

class MyPartnersService {
  MyPartnersService._();
  static final MyPartnersService instance = MyPartnersService._();

  Future<void> _migrateLegacyTableNames(Database db) async {
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?, ?, ?)",
        ['partner_wallet_links', 'partners_wallet_links',
         'partner_transactions', 'partners_transactions'],
      );
      final names = rows.map((row) => row['name'] as String).toSet();
      for (final pair in [
        ('partner_wallet_links', 'partners_wallet_links'),
        ('partner_transactions', 'partners_transactions'),
      ]) {
        final oldName = pair.$1;
        final newName = pair.$2;
        if (names.contains(oldName) && !names.contains(newName)) {
          await txn.execute('ALTER TABLE $oldName RENAME TO $newName');
        } else if (names.contains(oldName) && names.contains(newName)) {
          // If a prior interrupted upgrade left both tables, merge without
          // overwriting rows already present in the new table.
          await txn.execute('INSERT OR IGNORE INTO $newName SELECT * FROM $oldName');
          await txn.execute('DROP TABLE $oldName');
        }
      }
    });
  }

  Future<void> _ensureTables() async {
    final db = FinanceDB.instance.db;
    await _migrateLegacyTableNames(db);
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
    await db.execute('DROP INDEX IF EXISTS idx_partner_tx_partner_date');
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

  Future<List<Map<String, dynamic>>> getPartners() async {
    await _ensureTables();
    return FinanceDB.instance.db.rawQuery('''
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
    final db = FinanceDB.instance.db;
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
    await FinanceDB.instance.db.update(
      'partners', {'is_active': active ? 1 : 0},
      where: 'id = ?', whereArgs: [id],
    );
    AppRefreshController.notifyChanged();
  }

  Future<List<Map<String, dynamic>>> getWalletLinks(int partnerId) async {
    await _ensureTables();
    return FinanceDB.instance.db.rawQuery('''
      SELECT w.*, l.id AS link_id FROM partners_wallet_links l
      INNER JOIN wallets w ON w.id = l.wallet_id
      WHERE l.partner_id = ? ORDER BY w.name COLLATE NOCASE
    ''', [partnerId]);
  }

  Future<void> setWalletLinks(int partnerId, List<int> walletIds) async {
    await _ensureTables();
    final db = FinanceDB.instance.db;
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
    return FinanceDB.instance.db.rawQuery('''
      SELECT t.*, w.name AS wallet_name, w.currency AS currency
      FROM partners_transactions t
      LEFT JOIN wallets w ON w.id = t.wallet_id
      WHERE t.partner_id = ? ORDER BY t.date DESC, t.id DESC
    ''', [partnerId]);
  }

  Future<void> deletePartner(int partnerId) async {
    await _ensureTables();
    final db = FinanceDB.instance.db;
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
    final db = FinanceDB.instance.db;
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
    final db = FinanceDB.instance.db;
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
}
