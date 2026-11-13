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
      if (table == 'my_documents_records') {
        final settings = await txn.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: ['my_documents_records'], limit: 1);
        final current = settings.isEmpty ? <Map<String, dynamic>>[] : (jsonDecode(settings.first['setting_value']?.toString() ?? '[]') as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (current.any((e) => e['id'].toString() == item['source_id'].toString())) throw Exception('A document with this ID already exists.');
        current.add(record);
        await txn.insert('app_settings', {'setting_key':'my_documents_records','setting_value':jsonEncode(current)}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      const allowed = {'wallets','budgets','recurring_transactions','stock_items'};
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
