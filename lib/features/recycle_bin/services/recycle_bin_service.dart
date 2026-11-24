import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/notifications/services/reminder_service.dart';
import 'package:my_finance/features/space/services/my_space_service.dart';

class RecycleBinService {
  static Future<void> ensureTable() async {
    await FinanceDB.instance.db.execute('''CREATE TABLE IF NOT EXISTS recycle_bin (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL, entity_title TEXT NOT NULL,
      source_table TEXT NOT NULL, source_id TEXT NOT NULL,
      payload TEXT NOT NULL, related_payload TEXT,
      deleted_at TEXT NOT NULL, expires_at TEXT)''');
  }

  static const int retentionDays = 30;

  static Future<int> archive({
    required String type, required String title, required String table,
    required Object id, required Map<String, dynamic> record,
    List<Map<String, dynamic>> related = const [],
  }) async {
    await ensureTable();
    return FinanceDB.instance.db.insert('recycle_bin', {
      'entity_type': type, 'entity_title': title, 'source_table': table,
      'source_id': id.toString(), 'payload': jsonEncode(record),
      'related_payload': related.isEmpty ? null : jsonEncode(related),
      'deleted_at': DateTime.now().toIso8601String(),
      'expires_at': DateTime.now().add(const Duration(days: retentionDays)).toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getItems() async {
    await ensureTable();
    final db = FinanceDB.instance.db;
    final expired = await db.query('recycle_bin', where: 'expires_at IS NOT NULL AND expires_at <= ?', whereArgs: [DateTime.now().toIso8601String()], columns: ['id']);
    for (final row in expired) {
      await permanentlyDelete((row['id'] as num).toInt());
    }
    return db.query('recycle_bin', orderBy: 'deleted_at DESC, id DESC');
  }

  static Future<void> restore(int recycleId) async {
    await ensureTable();
    final db = FinanceDB.instance.db;
    await db.transaction((txn) async {
      final rows = await txn.query('recycle_bin', where: 'id = ?', whereArgs: [recycleId], limit: 1);
      if (rows.isEmpty) throw Exception('Recycle Bin item not found.');
      final item = rows.first;
      final table = item['source_table'].toString();
      final record = Map<String, dynamic>.from(jsonDecode(item['payload'].toString()) as Map);
      if (table == 'loan_repayments') {
        final loanId = (record['loan_id'] as num).toInt();
        final amount = (record['amount'] as num).toDouble();
        final walletAmount = (record['wallet_amount'] as num?)?.toDouble() ?? amount;
        final walletId = (record['wallet_id'] as num).toInt();
        final loans = await txn.query('loans', where: 'id = ?', whereArgs: [loanId], limit: 1);
        if (loans.isEmpty) throw Exception('Restore the related loan first.');
        final wallet = await txn.query('wallets', columns: ['id', 'balance'], where: 'id = ?', whereArgs: [walletId], limit: 1);
        if (wallet.isEmpty) throw Exception('The repayment wallet no longer exists.');
        final loan = loans.first;
        final remaining = (loan['remaining_amount'] as num).toDouble();
        if (remaining + 0.000001 < amount) throw Exception('Loan balance is not sufficient to restore this repayment.');
        final isGiven = (loan['loan_type']?.toString() ?? 'given') == 'given';
        final walletDelta = isGiven ? walletAmount : -walletAmount;
        final walletBalance = (wallet.first['balance'] as num).toDouble();
        if (walletDelta < 0 && walletBalance + 0.000001 < walletAmount) {
          throw Exception('Insufficient wallet balance to restore this repayment.');
        }
        await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id = ?', [walletDelta, walletId]);
        final next = (remaining - amount).clamp(0.0, (loan['amount'] as num).toDouble()).toDouble();
        await txn.update('loans', {'remaining_amount':next,'status':next <= 0 ? 'paid' : 'active'}, where: 'id = ?', whereArgs: [loanId]);
        await txn.insert('loan_repayments', record);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'loans') {
        final linkedSource = record['source_type']?.toString();
        if (const {'asset_purchase', 'asset_sale'}.contains(linkedSource)) {
          throw Exception('Restore the related Asset first. Its linked loan and repayment history are restored together.');
        }
        await txn.execute('''CREATE TABLE IF NOT EXISTS loans (
          id INTEGER PRIMARY KEY AUTOINCREMENT, party_id INTEGER,
          loan_type TEXT NOT NULL DEFAULT 'given', amount REAL NOT NULL,
          remaining_amount REAL NOT NULL, wallet_id INTEGER NOT NULL,
          lending_date TEXT NOT NULL, due_date TEXT,
          notes TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active',
          created_at TEXT NOT NULL)''');
        await txn.execute('''CREATE TABLE IF NOT EXISTS loan_repayments (
          id INTEGER PRIMARY KEY AUTOINCREMENT, loan_id INTEGER NOT NULL,
          amount REAL NOT NULL, wallet_id INTEGER NOT NULL, repayment_date TEXT NOT NULL,
          payment_method TEXT NOT NULL DEFAULT 'cash', notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL, FOREIGN KEY(loan_id) REFERENCES loans(id) ON DELETE CASCADE)''');
        final relatedRaw = item['related_payload']?.toString() ?? '[]';
        final repayments = (jsonDecode(relatedRaw) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final loanType = record['loan_type']?.toString().toLowerCase() ?? 'given';
        final isAssetLinked = const {'asset_purchase', 'asset_sale'}
            .contains(record['source_type']?.toString());
        final loanAmount = (record['amount'] as num).toDouble();
        final loanWallet = (record['wallet_id'] as num).toInt();

        // Asset-linked loans never move a reference wallet at creation.
        if (!isAssetLinked) {
          final source = await txn.query(
            'wallets', columns: ['balance'], where: 'id = ?',
            whereArgs: [loanWallet], limit: 1,
          );
          if (source.isEmpty) throw Exception('The loan wallet no longer exists.');
          final originalDelta = loanType == 'given' ? -loanAmount : loanAmount;
          final sourceBalance = (source.first['balance'] as num).toDouble();
          if (originalDelta < 0 && sourceBalance + 0.000001 < -originalDelta) {
            throw Exception('Insufficient wallet balance to restore this loan.');
          }
          await txn.rawUpdate(
            'UPDATE wallets SET balance = balance + ? WHERE id = ?',
            [originalDelta, loanWallet],
          );
        }

        // Reapply each repayment using its wallet-side converted amount.
        for (final repayment in repayments) {
          final walletId = (repayment['wallet_id'] as num).toInt();
          final walletAmount = (repayment['wallet_amount'] as num?)?.toDouble()
              ?? (repayment['amount'] as num).toDouble();
          final walletRows = await txn.query(
            'wallets', columns: ['balance'], where: 'id = ?',
            whereArgs: [walletId], limit: 1,
          );
          if (walletRows.isEmpty) throw Exception('A repayment wallet no longer exists.');
          final delta = loanType == 'given' ? walletAmount : -walletAmount;
          final balance = (walletRows.first['balance'] as num).toDouble();
          if (delta < 0 && balance + 0.000001 < -delta) {
            throw Exception('Insufficient wallet balance to restore a loan repayment.');
          }
          await txn.rawUpdate(
            'UPDATE wallets SET balance = balance + ? WHERE id = ?',
            [delta, walletId],
          );
        }

        record.remove('borrower_name');
        record.remove('borrower_phone');
        await txn.insert('loans', record);
        for (final repayment in repayments) {
          await txn.insert('loan_repayments', repayment);
        }
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'goals') {
        await txn.execute('''CREATE TABLE IF NOT EXISTS goals (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          target_amount REAL NOT NULL, saved_amount REAL NOT NULL DEFAULT 0,
          start_date TEXT, target_date TEXT, wallet_id INTEGER,
          notes TEXT NOT NULL DEFAULT '', is_completed INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL)''');
        await txn.execute('''CREATE TABLE IF NOT EXISTS goal_contributions (
          id INTEGER PRIMARY KEY AUTOINCREMENT, goal_id INTEGER NOT NULL,
          wallet_id INTEGER NOT NULL, amount REAL NOT NULL,
          type TEXT NOT NULL DEFAULT 'contribution', date TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
        final relatedRaw = item['related_payload']?.toString() ?? '[]';
        final history = (jsonDecode(relatedRaw) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        for (final entry in history) {
          final walletId = (entry['wallet_id'] as num).toInt();
          final amount = (entry['amount'] as num).toDouble();
          final isWithdrawal = entry['type']?.toString() == 'withdrawal';
          final wallets = await txn.query('wallets', columns: ['balance'], where: 'id = ?', whereArgs: [walletId], limit: 1);
          if (wallets.isEmpty) throw Exception('A linked wallet for this goal no longer exists.');
          if (!isWithdrawal && (wallets.first['balance'] as num).toDouble() < amount) throw Exception('Insufficient wallet balance to restore this savings goal.');
          await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id = ?', [isWithdrawal ? amount : -amount, walletId]);
        }
        await txn.insert('goals', record);
        for (final entry in history) { await txn.insert('goal_contributions', entry); }
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'assets') {
        await txn.execute('''CREATE TABLE IF NOT EXISTS assets (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'Other', purchase_price REAL NOT NULL,
          current_value REAL NOT NULL, purchase_date TEXT NOT NULL, wallet_id INTEGER NOT NULL,
          notes TEXT NOT NULL DEFAULT '', is_sold INTEGER NOT NULL DEFAULT 0,
          sale_date TEXT, sale_price REAL, sale_wallet_id INTEGER, created_at TEXT NOT NULL)''');
        final isLoanPurchase =
            (record['payment_type']?.toString().toLowerCase() ?? 'wallet') == 'loan';
        final walletId = (record['wallet_id'] as num?)?.toInt() ?? 0;
        if (!isLoanPurchase) {
          final purchase = (record['purchase_price'] as num).toDouble();
          final walletRows = await txn.query(
            'wallets', columns: ['balance'], where: 'id = ?',
            whereArgs: [walletId], limit: 1,
          );
          if (walletRows.isEmpty) throw Exception('The asset purchase wallet no longer exists.');
          if ((walletRows.first['balance'] as num).toDouble() < purchase) {
            throw Exception('Insufficient wallet balance to restore this asset.');
          }
          await txn.rawUpdate(
            'UPDATE wallets SET balance = balance - ? WHERE id = ?',
            [purchase, walletId],
          );
        }
        if ((record['is_sold'] as num?)?.toInt() == 1 &&
            record['sale_price'] != null &&
            (record['sale_payment_type']?.toString().toLowerCase() ?? 'wallet') != 'loan') {
          final saleWalletId = (record['sale_wallet_id'] as num?)?.toInt() ?? walletId;
          final saleExists = await txn.query(
            'wallets', columns: ['id'], where: 'id = ?',
            whereArgs: [saleWalletId], limit: 1,
          );
          if (saleExists.isEmpty) throw Exception('The asset sale wallet no longer exists.');
          await txn.rawUpdate(
            'UPDATE wallets SET balance = balance + ? WHERE id = ?',
            [((record['sale_wallet_amount'] as num?)?.toDouble() ?? (record['sale_price'] as num).toDouble()), saleWalletId],
          );
        }
        // Restore the linked purchase/sale loans and their repayment history
        // from the asset's grouped snapshot. Their base wallet effect is not
        // replayed because asset-linked loans never move a wallet on creation.
        final linkedRaw = item['related_payload']?.toString();
        if (linkedRaw != null && linkedRaw.isNotEmpty) {
          final linkedSnapshots = (jsonDecode(linkedRaw) as List)
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();
          for (final snapshot in linkedSnapshots) {
            final loan = Map<String, dynamic>.from(snapshot['loan'] as Map);
            final repayments = (snapshot['repayments'] as List? ?? const [])
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList();
            final loanId = (loan['id'] as num).toInt();
            final alreadyExists = await txn.query(
              'loans', columns: ['id'], where: 'id = ?', whereArgs: [loanId], limit: 1,
            );
            if (alreadyExists.isNotEmpty) {
              throw Exception('A linked asset loan already exists. Resolve it before restoring this asset.');
            }
            final loanType = (loan['loan_type']?.toString() ?? 'given').toLowerCase();
            for (final repayment in repayments) {
              final repaymentWalletId = (repayment['wallet_id'] as num).toInt();
              final walletAmount = (repayment['wallet_amount'] as num?)?.toDouble()
                  ?? (repayment['amount'] as num).toDouble();
              final wallets = await txn.query(
                'wallets', columns: ['balance'], where: 'id = ?',
                whereArgs: [repaymentWalletId], limit: 1,
              );
              if (wallets.isEmpty) {
                throw Exception('A linked loan repayment wallet no longer exists.');
              }
              final delta = loanType == 'given' ? walletAmount : -walletAmount;
              final balance = (wallets.first['balance'] as num).toDouble();
              if (delta < 0 && balance + 0.000001 < -delta) {
                throw Exception('Insufficient wallet balance to restore linked loan repayments.');
              }
              await txn.rawUpdate(
                'UPDATE wallets SET balance = balance + ? WHERE id = ?',
                [delta, repaymentWalletId],
              );
            }
            await txn.insert('loans', loan);
            for (final repayment in repayments) {
              await txn.insert('loan_repayments', repayment);
            }
            await txn.delete(
              'recycle_bin',
              where: "source_table = 'loans' AND source_id = ?",
              whereArgs: [loanId.toString()],
            );
          }
        }
        await txn.insert('assets', record);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'transactions') {
        final type = (record['type'] ?? '').toString().toLowerCase();
        final amount = (record['amount'] as num).toDouble();
        final walletId = (record['wallet_id'] as num).toInt();
        final fee = (record.remove('_transfer_fee') as num?)?.toDouble() ?? 0.0;
        Future<void> change(int id, double delta) async {
          final changed = await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id = ?', [delta, id]);
          if (changed == 0) throw Exception('A linked wallet no longer exists. Restore the wallet first.');
        }
        if (type == 'income') {
          await change(walletId, amount);
        } else if (type == 'expense') {
          final wallets = await txn.query('wallets', columns: ['balance'], where: 'id = ?', whereArgs: [walletId], limit: 1);
          if (wallets.isEmpty) throw Exception('The linked wallet no longer exists.');
          if ((wallets.first['balance'] as num).toDouble() < amount) throw Exception('Insufficient wallet balance to restore this expense.');
          await change(walletId, -amount);
        } else if (type == 'transfer') {
          final toId = (record['to_wallet_id'] as num?)?.toInt();
          if (toId == null) throw Exception('Transfer destination is missing.');
          final received = (record['to_amount'] as num?)?.toDouble() ?? amount;
          final wallets = await txn.query('wallets', columns: ['id','balance'], where: 'id = ? OR id = ?', whereArgs: [walletId,toId]);
          if (wallets.length < 2) throw Exception('Both linked wallets must exist before restoring this transfer.');
          final source = wallets.firstWhere((w) => w['id'] == walletId);
          if ((source['balance'] as num).toDouble() < amount + fee) throw Exception('Insufficient source wallet balance to restore this transfer.');
          await change(walletId, -(amount + fee));
          await change(toId, received);
        } else if (type == 'adjustment') {
          final delta = (record['balance_delta'] as num?)?.toDouble();
          if (delta == null) throw Exception('Adjustment balance change is missing.');
          await change(walletId, delta);
        } else {
          throw Exception('Unknown transaction type.');
        }
        await txn.insert('transactions', record);
        final salaryRaw = item['related_payload']?.toString();
        if (salaryRaw != null && salaryRaw.isNotEmpty) {
          await txn.execute('''CREATE TABLE IF NOT EXISTS staff_salaries (
            id INTEGER PRIMARY KEY AUTOINCREMENT, staff_id INTEGER NOT NULL,
            amount REAL NOT NULL, wallet_id INTEGER NOT NULL, paid_at TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '', transaction_id INTEGER)''');
          final salaryRows = (jsonDecode(salaryRaw) as List).whereType<Map>();
          for (final row in salaryRows) {
            final salary = Map<String, dynamic>.from(row);
            final staffId = (salary['staff_id'] as num).toInt();
            final staff = await txn.query('staff', columns: ['id'], where: 'id = ?', whereArgs: [staffId], limit: 1);
            if (staff.isEmpty) throw Exception('Restore the related staff member before restoring this salary transaction.');
            await txn.insert('staff_salaries', salary);
          }
        }
        if (fee > 0) {
          await txn.insert('app_settings', {'setting_key':'transaction_transfer_fee_${record['id']}','setting_value':fee.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'income_categories' || table == 'expense_categories') {
        final settings = await txn.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: [table], limit: 1);
        final current = settings.isEmpty ? <Map<String, dynamic>>[] : (jsonDecode(settings.first['setting_value']?.toString() ?? '[]') as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (current.any((e) => (e['name'] ?? '').toString().toLowerCase() == (record['name'] ?? '').toString().toLowerCase())) throw Exception('A category with this name already exists.');
        final index = (record.remove('_index') as num?)?.toInt() ?? current.length;
        final position = index.clamp(0, current.length).toInt();
        current.insert(position, record);
        await txn.insert('app_settings', {'setting_key':table,'setting_value':jsonEncode(current)}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table.startsWith('vehicle_manager_data_v1:')) {
        final arrayName = table.substring('vehicle_manager_data_v1:'.length);
        const vehicleKeys = {'vehicles','fuel_logs','expenses','reminders'};
        if (!vehicleKeys.contains(arrayName)) throw Exception('Unsupported vehicle record type.');
        final settings = await txn.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: ['vehicle_manager_data_v1'], limit: 1);
        final data = settings.isEmpty ? <String, dynamic>{'vehicles': [], 'fuel_logs': [], 'expenses': [], 'reminders': []} : Map<String, dynamic>.from(jsonDecode(settings.first['setting_value']?.toString() ?? '{}') as Map);
        final current = (data[arrayName] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (current.any((e) => e['id'].toString() == item['source_id'].toString())) throw Exception('A record with this ID already exists.');
        current.add(record);
        data[arrayName] = current;
        await txn.insert('app_settings', {'setting_key':'vehicle_manager_data_v1','setting_value':jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }

      if (table == 'committees') {
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
        final related = (jsonDecode(item['related_payload']?.toString() ?? '[]') as List)
          .whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
        final members = related.where((e) => e['_related_table']=='committee_members').toList();
        final entries = related.where((e) => e['_related_table']=='committee_entries').toList();
        final finance = related.where((e) => e['_related_table']=='transactions').toList();
        for (final row in finance) {
          final walletId = (row['wallet_id'] as num?)?.toInt();
          final delta = (row['balance_delta'] as num?)?.toDouble() ?? 0;
          if (walletId != null && delta != 0) {
            final wallet = await txn.query('wallets', columns: ['balance'],
              where: 'id=?', whereArgs: [walletId], limit: 1);
            if (wallet.isEmpty) throw Exception('A committee wallet no longer exists.');
            if (delta < 0 && (wallet.first['balance'] as num).toDouble() < -delta) {
              throw Exception('Insufficient wallet balance to restore committee activity.');
            }
            await txn.rawUpdate('UPDATE wallets SET balance=balance+? WHERE id=?', [delta,walletId]);
          }
        }
        await txn.insert('committees', record);
        for (final row in members) { row.remove('_related_table'); await txn.insert('committee_members', row); }
        for (final row in finance) { row.remove('_related_table'); await txn.insert('transactions', row); }
        for (final row in entries) { row.remove('_related_table'); await txn.insert('committee_entries', row); }
        await txn.delete('recycle_bin', where: 'id=?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'partners') {
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
        final related = (jsonDecode(item['related_payload']?.toString() ?? '[]') as List)
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
        await txn.delete('recycle_bin', where: 'id=?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'installment_contracts') {
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
        final relatedRaw = item['related_payload']?.toString() ?? '[]';
        final related = (jsonDecode(relatedRaw) as List)
            .whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
        final payments = related.where((e) => e['_related_table'] == 'installment_payments').toList();
        final transactions = related.where((e) => e['_related_table'] == 'transactions').toList();
        final walletId = (record['wallet_id'] as num).toInt();
        final totalPaid = payments.fold<double>(0, (sum, row) => sum + (row['amount'] as num).toDouble());
        final walletRows = await txn.query('wallets', columns: ['balance'],
          where: 'id = ?', whereArgs: [walletId], limit: 1);
        if (walletRows.isEmpty) throw Exception('The installment wallet no longer exists.');
        final direction = record['direction']?.toString();
        final delta = direction == 'sell' ? totalPaid : -totalPaid;
        if (delta < 0 && (walletRows.first['balance'] as num).toDouble() < -delta) {
          throw Exception('Insufficient wallet balance to restore this installment contract.');
        }
        final duplicate = await txn.query('installment_contracts',
          columns: ['id'], where: 'id = ?', whereArgs: [record['id']], limit: 1);
        if (duplicate.isNotEmpty) throw Exception('This installment contract already exists.');
        await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id = ?', [delta, walletId]);
        await txn.insert('installment_contracts', record);
        for (final payment in payments) {
          payment.remove('_related_table');
          await txn.insert('installment_payments', payment);
        }
        for (final transaction in transactions) {
          transaction.remove('_related_table');
          await txn.insert('transactions', transaction);
        }
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'space_playlists' || table == 'space_collections') {
        final related = (jsonDecode(item['related_payload']?.toString() ?? '[]') as List)
          .whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
        await MySpaceService.instance.restoreArchivedSpaceGroup(table, record, related);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'finance_reminders_v1') {
        await ReminderService.instance.restoreReminder(record);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'space_items') {
        final spaceDir = await getApplicationDocumentsDirectory();
        final spaceDb = await openDatabase(p.join(spaceDir.path, 'my_space', 'space.db'));
        try {
          final existing = await spaceDb.query('space_items', where: 'id = ?', whereArgs: [record['id']], limit: 1);
          if (existing.isNotEmpty) throw Exception('This Space item already exists.');
          await spaceDb.insert('space_items', record);
        } finally { await spaceDb.close(); }
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'space_documents_records') {
        final settings = await txn.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: ['space_documents_records'], limit: 1);
        final current = settings.isEmpty ? <Map<String, dynamic>>[] : (jsonDecode(settings.first['setting_value']?.toString() ?? '[]') as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (current.any((e) => e['id'].toString() == item['source_id'].toString())) throw Exception('A document with this ID already exists.');
        current.add(record);
        await txn.insert('app_settings', {'setting_key':'space_documents_records','setting_value':jsonEncode(current)}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      const allowed = {'wallets','budgets','recurring_transactions','stock_items','staff'};
      if (!allowed.contains(table)) throw Exception('Restore for this record type is not available yet.');
      await txn.insert(table, record);
      final rawRelated = item['related_payload']?.toString();
      if (rawRelated != null && rawRelated.isNotEmpty) {
        final related = (jsonDecode(rawRelated) as List).whereType<Map>();
        final relatedTable = table == 'stock_items' ? 'stock_movements' : null;
        if (relatedTable != null) {
          for (final row in related) {
            await txn.insert(relatedTable, Map<String, dynamic>.from(row));
          }
        } else if (table == 'staff') {
          for (final row in related) {
            final restored = Map<String, dynamic>.from(row);
            final relatedType = restored.remove('_related_table')?.toString() ?? 'staff_attendance';
            if (!{'staff_salaries','staff_attendance'}.contains(relatedType)) throw Exception('Unsupported staff history record.');
            await txn.insert(relatedType, restored);
          }
        }
      }
      await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
    });
    AppRefreshController.notifyChanged();
  }

  static Future<void> discardArchive(int id) async {
    await ensureTable();
    await FinanceDB.instance.db.delete('recycle_bin', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> permanentlyDelete(int id) async {
    await ensureTable();
    final db = FinanceDB.instance.db;
    final rows = await db.query('recycle_bin', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final item = rows.first;
    final table = item['source_table']?.toString() ?? '';
    final sourceId = int.tryParse(item['source_id']?.toString() ?? '');
    final ownerTypes = <String, String>{
      'transactions':'transaction', 'assets':'asset', 'loans':'loan',
      'goals':'goal', 'loan_repayments':'repayment', 'space_documents_records':'document',
    };
    String? ownerType = ownerTypes[table];
    if (table.startsWith('vehicle_manager_data_v1:')) {
      final key = table.substring('vehicle_manager_data_v1:'.length);
      ownerType = key == 'vehicles' ? 'vehicle' : key == 'fuel_logs' ? 'vehicle_fuel' : key == 'expenses' ? 'vehicle_expense' : null;
    }
    if (table == 'space_items') {
      try {
        final record = Map<String, dynamic>.from(jsonDecode(item['payload']?.toString() ?? '{}') as Map);
        final path = record['file_path']?.toString();
        if (path != null && path.isNotEmpty) { final file = File(path); if (await file.exists()) await file.delete(); }
      } on FileSystemException { /* best effort cleanup */ }
    }
    if (ownerType != null && sourceId != null) {
      await AttachmentService.deleteOwnerAttachments(ownerType: ownerType, ownerId: sourceId);
    }
    if (table == 'assets') {
      final raw = item['related_payload']?.toString();
      if (raw != null && raw.isNotEmpty) {
        final snapshots = (jsonDecode(raw) as List).whereType<Map>();
        for (final snapshot in snapshots) {
          final loan = snapshot['loan'];
          if (loan is! Map) continue;
          final loanId = (loan['id'] as num?)?.toInt();
          if (loanId == null) continue;
          await AttachmentService.deleteOwnerAttachments(
            ownerType: 'loan',
            ownerId: loanId,
          );
          final repayments = (snapshot['repayments'] as List? ?? const [])
              .whereType<Map>();
          for (final repayment in repayments) {
            final repaymentId = (repayment['id'] as num?)?.toInt();
            if (repaymentId != null) {
              await AttachmentService.deleteOwnerAttachments(
                ownerType: 'repayment',
                ownerId: repaymentId,
              );
            }
          }
          // Grouped asset deletion owns these child loan archive records.
          await db.delete(
            'recycle_bin',
            where: "source_table = 'loans' AND source_id = ?",
            whereArgs: [loanId.toString()],
          );
        }
      }
    }
    if (table == 'loans' || table == 'goals') {
      final raw = item['related_payload']?.toString();
      if (raw != null && raw.isNotEmpty) {
        final related = (jsonDecode(raw) as List).whereType<Map>();
        final childOwner = table == 'loans' ? 'repayment' : null;
        if (childOwner != null) {
          for (final child in related) {
            final childId = (child['id'] as num?)?.toInt();
            if (childId != null) await AttachmentService.deleteOwnerAttachments(ownerType: childOwner, ownerId: childId);
          }
        }
      }
    }
    if (['partners','committees','installment_contracts'].contains(table)) {
      final raw = item['related_payload']?.toString();
      if (raw != null && raw.isNotEmpty) {
        final related = (jsonDecode(raw) as List).whereType<Map>();
        for (final row in related) {
          if (row['_related_table'] == 'transactions') {
            final transactionId = (row['id'] as num?)?.toInt();
            if (transactionId != null) {
              await AttachmentService.deleteOwnerAttachments(
                ownerType: 'transaction', ownerId: transactionId,
              );
            }
          }
        }
      }
    }
    await db.delete('recycle_bin', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }
}
