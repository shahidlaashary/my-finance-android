import 'dart:convert';

import 'package:my_finance/core/database/database_manager.dart';

/// Writes archive envelopes for the shared Recycle Bin.
/// Domain services depend on this small persistence helper, not on the
/// RecycleBinService UI/coordinator implementation.
class RecycleBinArchiveService {
  RecycleBinArchiveService._();

  static const int retentionDays = 30;

  static Future<void> ensureTable() async {
    await DatabaseManager.instance.database.execute('''
      CREATE TABLE IF NOT EXISTS recycle_bin (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_title TEXT NOT NULL,
        source_table TEXT NOT NULL,
        source_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        related_payload TEXT,
        deleted_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');
  }

  static Future<int> archive({
    required String type,
    required String title,
    required String table,
    required Object id,
    required Map<String, dynamic> record,
    List<Map<String, dynamic>> related = const [],
  }) async {
    await ensureTable();
    final now = DateTime.now();
    return DatabaseManager.instance.database.insert('recycle_bin', {
      'entity_type': type,
      'entity_title': title,
      'source_table': table,
      'source_id': id.toString(),
      'payload': jsonEncode(record),
      'related_payload': related.isEmpty ? null : jsonEncode(related),
      'deleted_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(days: retentionDays)).toIso8601String(),
    });
  }
}
