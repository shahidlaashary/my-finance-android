import 'dart:convert';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

class RecycleBinService {
  static Future<void> ensureTable() async {
    await FinanceDB.instance.db.execute('''CREATE TABLE IF NOT EXISTS recycle_bin (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL, entity_title TEXT NOT NULL,
      source_table TEXT NOT NULL, source_id TEXT NOT NULL,
      payload TEXT NOT NULL, related_payload TEXT,
      deleted_at TEXT NOT NULL)''');
  }

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
    });
  }

  static Future<List<Map<String, dynamic>>> getItems() async {
    await ensureTable();
    return FinanceDB.instance.db.query('recycle_bin', orderBy: 'deleted_at DESC, id DESC');
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
      if (table == 'assets') {
        await txn.execute('''CREATE TABLE IF NOT EXISTS assets (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'Other', purchase_price REAL NOT NULL,
          current_value REAL NOT NULL, purchase_date TEXT NOT NULL, wallet_id INTEGER NOT NULL,
          notes TEXT NOT NULL DEFAULT '', is_sold INTEGER NOT NULL DEFAULT 0,
          sale_date TEXT, sale_price REAL, sale_wallet_id INTEGER, created_at TEXT NOT NULL)''');
        final walletId = (record['wallet_id'] as num).toInt();
        final purchase = (record['purchase_price'] as num).toDouble();
        final walletRows = await txn.query('wallets', columns: ['balance'], where: 'id = ?', whereArgs: [walletId], limit: 1);
        if (walletRows.isEmpty) throw Exception('The asset purchase wallet no longer exists.');
        if ((walletRows.first['balance'] as num).toDouble() < purchase) throw Exception('Insufficient wallet balance to restore this asset.');
        await txn.rawUpdate('UPDATE wallets SET balance = balance - ? WHERE id = ?', [purchase, walletId]);
        if ((record['is_sold'] as num?)?.toInt() == 1 && record['sale_price'] != null) {
          final saleWalletId = (record['sale_wallet_id'] as num?)?.toInt() ?? walletId;
          final saleExists = await txn.query('wallets', columns: ['id'], where: 'id = ?', whereArgs: [saleWalletId], limit: 1);
          if (saleExists.isEmpty) throw Exception('The asset sale wallet no longer exists.');
          await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id = ?', [(record['sale_price'] as num).toDouble(), saleWalletId]);
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
        final position = index.clamp(0, current.length);
        current.insert(position, record);
        await txn.insert('app_settings', {'setting_key':table,'setting_value':jsonEncode(current)}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'vehicle_manager_data_v1:vehicles') {
        final settings = await txn.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: ['vehicle_manager_data_v1'], limit: 1);
        final data = settings.isEmpty ? <String, dynamic>{'vehicles': [], 'fuel_logs': [], 'expenses': [], 'reminders': []} : Map<String, dynamic>.from(jsonDecode(settings.first['setting_value']?.toString() ?? '{}') as Map);
        final vehicles = (data['vehicles'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (vehicles.any((e) => e['id'].toString() == item['source_id'].toString())) throw Exception('A vehicle with this ID already exists.');
        vehicles.add(record);
        data['vehicles'] = vehicles;
        await txn.insert('app_settings', {'setting_key':'vehicle_manager_data_v1','setting_value':jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'my_documents_records') {
        final settings = await txn.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: ['my_documents_records'], limit: 1);
        final current = settings.isEmpty ? <Map<String, dynamic>>[] : (jsonDecode(settings.first['setting_value']?.toString() ?? '[]') as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (current.any((e) => e['id'].toString() == item['source_id'].toString())) throw Exception('A document with this ID already exists.');
        current.add(record);
        await txn.insert('app_settings', {'setting_key':'my_documents_records','setting_value':jsonEncode(current)}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      const allowed = {'wallets','budgets','recurring_transactions','stock_items','staff'};
      if (!allowed.contains(table)) throw Exception('Restore for this record type is not available yet.');
      await txn.insert(table, record);
      final rawRelated = item['related_payload']?.toString();
      if (rawRelated != null && rawRelated.isNotEmpty) {
        final related = (jsonDecode(rawRelated) as List).whereType<Map>();
        final relatedTable = table == 'stock_items' ? 'stock_movements' : table == 'staff' ? 'staff_attendance' : null;
        if (relatedTable != null) {
          for (final row in related) {
            await txn.insert(relatedTable, Map<String, dynamic>.from(row));
          }
        }
      }
      await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
    });
    AppRefreshController.notifyChanged();
  }

  static Future<void> permanentlyDelete(int id) async {
    await ensureTable();
    await FinanceDB.instance.db.delete('recycle_bin', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }
}
