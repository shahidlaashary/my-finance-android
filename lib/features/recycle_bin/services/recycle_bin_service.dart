import 'package:my_finance/modules/finance/services/assets_service.dart';
import 'package:my_finance/modules/installments/services/installment_service.dart';
import 'package:my_finance/modules/partners/services/my_partners_service.dart';
import 'package:my_finance/modules/committee/services/committee_service.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
import 'package:my_finance/core/database/database_manager.dart';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/files/attachment_service.dart';
import 'package:my_finance/features/notifications/services/reminder_service.dart';
import 'package:my_finance/modules/space/services/my_space_service.dart';
import 'package:my_finance/modules/space/services/space_documents_service.dart';
import 'package:my_finance/modules/parties/services/party_service.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';
import 'package:my_finance/modules/finance/services/goals_service.dart';
import 'package:my_finance/modules/finance/services/category_service.dart';

class RecycleBinService {
  static Future<void> ensureTable() async {
    await DatabaseManager.instance.database.execute('''CREATE TABLE IF NOT EXISTS recycle_bin (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL, entity_title TEXT NOT NULL,
      source_table TEXT NOT NULL, source_id TEXT NOT NULL,
      payload TEXT NOT NULL, related_payload TEXT,
      deleted_at TEXT NOT NULL, expires_at TEXT)''');
  }

  static const int retentionDays = 30;

  static Future<void> _applyWalletDelta(
    Transaction txn, {
    required int walletId,
    required double amount,
  }) async {
    if (!amount.isFinite) {
      throw Exception('Wallet balance change must be a valid number.');
    }
    final changed = await txn.rawUpdate(
      'UPDATE wallets SET balance = balance + ? WHERE id = ?',
      [amount, walletId],
    );
    if (changed != 1) {
      throw Exception('The linked wallet no longer exists. Restore the wallet first.');
    }
  }

  static Future<int> archive({
    required String type, required String title, required String table,
    required Object id, required Map<String, dynamic> record,
    List<Map<String, dynamic>> related = const [],
  }) async {
    await ensureTable();
    return DatabaseManager.instance.database.insert('recycle_bin', {
      'entity_type': type, 'entity_title': title, 'source_table': table,
      'source_id': id.toString(), 'payload': jsonEncode(record),
      'related_payload': related.isEmpty ? null : jsonEncode(related),
      'deleted_at': DateTime.now().toIso8601String(),
      'expires_at': DateTime.now().add(const Duration(days: retentionDays)).toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getItems() async {
    await ensureTable();
    final db = DatabaseManager.instance.database;
    final expired = await db.query('recycle_bin', where: 'expires_at IS NOT NULL AND expires_at <= ?', whereArgs: [DateTime.now().toIso8601String()], columns: ['id']);
    for (final row in expired) {
      await permanentlyDelete((row['id'] as num).toInt());
    }
    return db.query('recycle_bin', orderBy: 'deleted_at DESC, id DESC');
  }

  static Future<void> restore(int recycleId) async {
    await ensureTable();
    final db = DatabaseManager.instance.database;

    // Space Documents live in space.db; only the app-wide archive envelope
    // remains in the central Recycle Bin database.
    final archivedRows = await db.query(
      'recycle_bin',
      where: 'id = ?',
      whereArgs: [recycleId],
      limit: 1,
    );
    if (archivedRows.isEmpty) throw Exception('Recycle Bin item not found.');
    if (archivedRows.first['source_table']?.toString() == 'space_documents_records') {
      final record = Map<String, dynamic>.from(
        jsonDecode(archivedRows.first['payload'].toString()) as Map,
      );
      await SpaceDocumentsService.instance.restoreArchivedRecord(record);
      await db.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
      AppRefreshController.notifyChanged();
      return;
    }

    await db.transaction((txn) async {
      final rows = await txn.query('recycle_bin', where: 'id = ?', whereArgs: [recycleId], limit: 1);
      if (rows.isEmpty) throw Exception('Recycle Bin item not found.');
      final item = rows.first;
      final table = item['source_table'].toString();
      final record = Map<String, dynamic>.from(
        jsonDecode(item['payload'].toString()) as Map,
      );
      if (table == 'loan_parties') {
        await PartyService.restoreArchivedParty(txn, record);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'loan_repayments') {
        await LoansService.restoreArchivedRepayment(txn, record);
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'loans') {
        await LoansService.restoreArchivedLoan(
          txn,
          record: record,
          relatedPayload: item['related_payload']?.toString(),
        );
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'goals') {
        final relatedRaw = item['related_payload']?.toString() ?? '[]';
        final history = (jsonDecode(relatedRaw) as List)
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
        await GoalsService.restoreArchivedGoal(
          txn,
          record: record,
          history: history,
        );
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'assets') {
        await AssetsService.restoreArchivedAsset(
          txn,
          record: record,
          relatedPayload: item['related_payload']?.toString(),
        );
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'transactions') {
        await TransactionsService.restoreArchivedTransaction(
          txn,
          record: record,
          relatedPayload: item['related_payload']?.toString(),
        );
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'income_categories' || table == 'expense_categories') {
        await CategoryService.restoreArchivedCategory(
          txn,
          settingKey: table,
          record: record,
        );
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
        await CommitteeService.restoreArchivedCommittee(
          txn,
          record: record,
          relatedPayload: item['related_payload']?.toString(),
        );
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'partners') {
        await MyPartnersService.instance.restoreArchivedPartner(
          txn,
          record: record,
          relatedPayload: item['related_payload']?.toString(),
        );
        await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [recycleId]);
        return;
      }
      if (table == 'installment_contracts') {
        await InstallmentService.restoreArchivedContract(
          txn,
          record: record,
          relatedPayload: item['related_payload']?.toString(),
        );
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
        await MySpaceService.instance.restoreArchivedSpaceItem(record);
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
    await DatabaseManager.instance.database.delete('recycle_bin', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> permanentlyDelete(int id) async {
    await ensureTable();
    final db = DatabaseManager.instance.database;
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
