import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

/// Property, tenant, contract aur property-document records manage karta hai.
class PropertiesService {
  PropertiesService._();

  static Future<List<Map<String, dynamic>>> properties() async {
    return DatabaseManager.instance.database.query('properties', orderBy: 'name COLLATE NOCASE');
  }

  static Future<List<Map<String, dynamic>>> tenants() async {
    return DatabaseManager.instance.database.query('properties_tenants', orderBy: 'name COLLATE NOCASE');
  }

  static Future<List<Map<String, dynamic>>> contracts() async {
    return DatabaseManager.instance.database.rawQuery('''
      SELECT c.*, p.name AS property_name, t.name AS tenant_name
      FROM properties_contracts c
      LEFT JOIN properties p ON p.id = c.property_id
      LEFT JOIN properties_tenants t ON t.id = c.tenant_id
      ORDER BY c.start_date DESC, c.id DESC
    ''');
  }


  static Future<List<Map<String, dynamic>>> maintenance({int? propertyId, String? status}) async {
    final clauses=<String>[],args=<Object?>[];
    if(propertyId!=null){clauses.add('m.property_id = ?');args.add(propertyId);}
    if(status!=null){clauses.add('m.status = ?');args.add(status);}
    return DatabaseManager.instance.database.rawQuery('''
      SELECT m.*, p.name AS property_name
      FROM properties_maintenance m
      LEFT JOIN properties p ON p.id = m.property_id
      ${clauses.isEmpty?'':'WHERE ${clauses.join(' AND ')}'}
      ORDER BY CASE m.priority WHEN 'Urgent' THEN 0 WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END,
        CASE WHEN m.due_date = '' THEN 1 ELSE 0 END, m.due_date ASC, m.id DESC
    ''',args);
  }

  static Future<int> saveMaintenance({
    int? id,
    required int propertyId,
    required String title,
    required String description,
    required String category,
    required String priority,
    required String assignedTo,
    required double estimatedCost,
    required double actualCost,
    required String status,
    required String dueDate,
    required String completedDate,
    required String photoPath,
  }) async {
    if(title.trim().isEmpty || !estimatedCost.isFinite || estimatedCost<0 ||
       !actualCost.isFinite || actualCost<0) {
      throw ArgumentError('Enter valid maintenance details.');
    }
    final db=DatabaseManager.instance.database;
    final property=await db.query('properties',columns:['id'],where:'id = ?',whereArgs:[propertyId],limit:1);
    if(property.isEmpty)throw StateError('Select a valid property.');
    final values=<String,Object?>{
      'property_id':propertyId,'title':title.trim(),'description':description.trim(),
      'category':category,'priority':priority,'assigned_to':assignedTo.trim(),
      'estimated_cost':estimatedCost,'actual_cost':actualCost,'status':status,
      'due_date':dueDate,'completed_date':completedDate,'photo_path':photoPath,
    };
    final result=id==null
      ? await db.insert('properties_maintenance',{...values,'created_at':DateTime.now().toIso8601String()})
      : await db.update('properties_maintenance',values,where:'id = ?',whereArgs:[id]);
    if(id!=null&&result==0)throw StateError('Maintenance record not found.');
    AppRefreshController.notifyChanged();
    return id??result;
  }

  static Future<void> deleteMaintenance(int id) async {
    await DatabaseManager.instance.database.delete('properties_maintenance',where:'id = ?',whereArgs:[id]);
    AppRefreshController.notifyChanged();
  }

  static Future<List<Map<String, dynamic>>> documents(int propertyId) async {
    return DatabaseManager.instance.database.query(
      'properties_documents',
      where: 'property_id = ?',
      whereArgs: [propertyId],
      orderBy: 'created_at DESC, id DESC',
    );
  }

  static Future<int> saveProperty({
    int? id,
    required String name,
    required String type,
    required String address,
    required String ownership,
    required String area,
    required double purchasePrice,
    required String purchaseDate,
    required double currentValue,
    required String status,
    required String notes,
  }) async {
    if (name.trim().isEmpty || !purchasePrice.isFinite || purchasePrice < 0 ||
        !currentValue.isFinite || currentValue < 0) {
      throw ArgumentError('Enter valid property details.');
    }
    final values = <String, Object?>{
      'name': name.trim(), 'type': type, 'address': address.trim(),
      'ownership': ownership, 'area': area.trim(),
      'purchase_price': purchasePrice, 'purchase_date': purchaseDate,
      'current_value': currentValue, 'status': status, 'notes': notes.trim(),
    };
    final db = DatabaseManager.instance.database;
    final result = id == null
        ? await db.insert('properties', {...values, 'created_at': DateTime.now().toIso8601String()})
        : await db.update('properties', values, where: 'id = ?', whereArgs: [id]);
    if (id != null && result == 0) throw StateError('Property not found.');
    AppRefreshController.notifyChanged();
    return id ?? result;
  }

  static Future<int> saveTenant({
    int? id,
    required String name,
    required String phone,
    required String email,
    required String identityNumber,
    required String notes,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Tenant name is required.');
    final values = <String, Object?>{
      'name': name.trim(), 'phone': phone.trim(), 'email': email.trim(),
      'identity_number': identityNumber.trim(), 'notes': notes.trim(),
    };
    final db = DatabaseManager.instance.database;
    final result = id == null
        ? await db.insert('properties_tenants', {...values, 'created_at': DateTime.now().toIso8601String()})
        : await db.update('properties_tenants', values, where: 'id = ?', whereArgs: [id]);
    if (id != null && result == 0) throw StateError('Tenant not found.');
    AppRefreshController.notifyChanged();
    return id ?? result;
  }

  static Future<int> saveContract({
    int? id,
    required int propertyId,
    required int tenantId,
    required String contractType,
    required String startDate,
    required String endDate,
    required double rent,
    required String frequency,
    required double deposit,
    required String status,
    required String notes,
  }) async {
    if (!rent.isFinite || rent < 0 || !deposit.isFinite || deposit < 0) {
      throw ArgumentError('Enter valid contract amounts.');
    }
    final db = DatabaseManager.instance.database;
    final property = await db.query('properties', columns: ['id'], where: 'id = ?', whereArgs: [propertyId], limit: 1);
    final tenant = await db.query('properties_tenants', columns: ['id'], where: 'id = ?', whereArgs: [tenantId], limit: 1);
    if (property.isEmpty || tenant.isEmpty) throw StateError('Select a valid property and tenant.');
    final values = <String, Object?>{
      'property_id': propertyId, 'tenant_id': tenantId,
      'contract_type': contractType, 'start_date': startDate,
      'end_date': endDate, 'rent': rent, 'frequency': frequency,
      'deposit': deposit, 'status': status, 'notes': notes.trim(),
    };
    final result = id == null
        ? await db.insert('properties_contracts', {
            ...values,
            'created_at': DateTime.now().toIso8601String(),
          })
        : await db.update('properties_contracts', values, where: 'id = ?', whereArgs: [id]);
    if (id != null && result == 0) throw StateError('Contract not found.');
    AppRefreshController.notifyChanged();
    return id ?? result;
  }

  static Future<int> addDocument({
    required int propertyId,
    required String title,
    required String fileName,
    required String filePath,
    required String mimeType,
  }) async {
    final id = await DatabaseManager.instance.database.insert('properties_documents', {
      'property_id': propertyId, 'title': title.trim(), 'file_name': fileName,
      'file_path': filePath, 'mime_type': mimeType,
      'created_at': DateTime.now().toIso8601String(),
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  static Future<void> updateDocument(
    int id, {
    String? title,
    String? fileName,
    String? filePath,
    String? mimeType,
  }) async {
    final values = <String, Object?>{};
    if (title != null) values['title'] = title.trim();
    if (fileName != null) values['file_name'] = fileName;
    if (filePath != null) values['file_path'] = filePath;
    if (mimeType != null) values['mime_type'] = mimeType;
    if (values.isEmpty) return;
    final changed = await DatabaseManager.instance.database.update(
      'properties_documents', values, where: 'id = ?', whereArgs: [id],
    );
    if (changed == 0) throw StateError('Property document not found.');
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteDocument(int id) async {
    await DatabaseManager.instance.database.delete('properties_documents', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteTenant(int id) async {
    final db = DatabaseManager.instance.database;
    final linked = await db.query('properties_contracts', columns: ['id'], where: 'tenant_id = ?', whereArgs: [id], limit: 1);
    if (linked.isNotEmpty) throw StateError('Remove this tenant\'s contracts before deleting the tenant.');
    await db.delete('properties_tenants', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }


  static Future<List<Map<String, dynamic>>> owners() async {
    return DatabaseManager.instance.database.query('properties_owners', orderBy: 'name COLLATE NOCASE');
  }

  static Future<List<Map<String, dynamic>>> ownersForProperty(int propertyId) async {
    return DatabaseManager.instance.database.rawQuery('''
      SELECT o.*, l.ownership_share, l.id AS link_id
      FROM properties_owner_links l
      JOIN properties_owners o ON o.id = l.owner_id
      WHERE l.property_id = ?
      ORDER BY o.name COLLATE NOCASE
    ''', [propertyId]);
  }

  static Future<int> saveOwner({
    int? id,
    required String name,
    required String phone,
    required String email,
    required String identityNumber,
    required String address,
    required String notes,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Owner name is required.');
    final db = DatabaseManager.instance.database;
    final values = <String, Object?>{
      'name': name.trim(), 'phone': phone.trim(), 'email': email.trim(),
      'identity_number': identityNumber.trim(), 'address': address.trim(),
      'notes': notes.trim(),
    };
    final result = id == null
        ? await db.insert('properties_owners', {...values, 'created_at': DateTime.now().toIso8601String()})
        : await db.update('properties_owners', values, where: 'id = ?', whereArgs: [id]);
    if (id != null && result == 0) throw StateError('Owner not found.');
    AppRefreshController.notifyChanged();
    return id ?? result;
  }

  static Future<void> linkOwner({
    required int propertyId,
    required int ownerId,
    double ownershipShare = 100,
  }) async {
    if (!ownershipShare.isFinite || ownershipShare <= 0 || ownershipShare > 100) {
      throw ArgumentError('Ownership share must be between 0 and 100.');
    }
    final db = DatabaseManager.instance.database;
    await db.transaction((txn) async {
      final property = await txn.query('properties', columns: ['id'], where: 'id = ?', whereArgs: [propertyId], limit: 1);
      final owner = await txn.query('properties_owners', columns: ['id'], where: 'id = ?', whereArgs: [ownerId], limit: 1);
      if (property.isEmpty || owner.isEmpty) throw StateError('Select a valid property and owner.');
      await txn.insert('properties_owner_links', {
        'property_id': propertyId, 'owner_id': ownerId,
        'ownership_share': ownershipShare, 'created_at': DateTime.now().toIso8601String(),
      });
    });
    AppRefreshController.notifyChanged();
  }

  static Future<void> unlinkOwner(int linkId) async {
    await DatabaseManager.instance.database.delete('properties_owner_links', where: 'id = ?', whereArgs: [linkId]);
    AppRefreshController.notifyChanged();
  }

  static Future<List<Map<String, dynamic>>> rentSchedules({int? contractId}) async {
    return DatabaseManager.instance.database.query(
      'properties_rent_schedules',
      where: contractId == null ? null : 'contract_id = ?',
      whereArgs: contractId == null ? null : [contractId],
      orderBy: 'next_due_date ASC, id DESC',
    );
  }

  static Future<int> saveRentSchedule({
    int? id,
    required int contractId,
    required double amount,
    required String frequency,
    required String startDate,
    required String endDate,
    required String nextDueDate,
    required String status,
    required String notes,
  }) async {
    if (!amount.isFinite || amount <= 0) throw ArgumentError('Rent amount must be greater than zero.');
    final db = DatabaseManager.instance.database;
    final contract = await db.query('properties_contracts', columns: ['id'], where: 'id = ?', whereArgs: [contractId], limit: 1);
    if (contract.isEmpty) throw StateError('Select a valid contract.');
    final values = <String, Object?>{
      'contract_id': contractId, 'amount': amount, 'frequency': frequency,
      'start_date': startDate, 'end_date': endDate,
      'next_due_date': nextDueDate, 'status': status, 'notes': notes.trim(),
    };
    final result = id == null
        ? await db.insert('properties_rent_schedules', {...values, 'created_at': DateTime.now().toIso8601String()})
        : await db.update('properties_rent_schedules', values, where: 'id = ?', whereArgs: [id]);
    if (id != null && result == 0) throw StateError('Rent schedule not found.');
    AppRefreshController.notifyChanged();
    return id ?? result;
  }


  static DateTime _nextRentDate(DateTime date, String frequency) {
    switch (frequency) {
      case 'Weekly': return date.add(const Duration(days: 7));
      case 'Quarterly': return _addMonthsClamped(date, 3);
      case 'Yearly': return _addMonthsClamped(date, 12);
      case 'Monthly': return _addMonthsClamped(date, 1);
      case 'One-time': return date;
      default: throw ArgumentError('Unsupported rent frequency: $frequency');
    }
  }

  static DateTime _addMonthsClamped(DateTime date, int months) {
    final monthIndex = date.year * 12 + date.month - 1 + months;
    final year = monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
  }

  /// Idempotently creates payment entries for active schedules through the
  /// selected horizon, then advances each schedule's next due date.
  static Future<int> generateScheduledRentPayments({DateTime? throughDate}) async {
    final db = DatabaseManager.instance.database;
    final horizon = throughDate ?? DateTime.now().add(const Duration(days: 30));
    final horizonDate = DateTime(horizon.year, horizon.month, horizon.day);
    var created = 0;
    await db.transaction((txn) async {
      final schedules = await txn.query('properties_rent_schedules', where: "status = 'Active'");
      for (final schedule in schedules) {
        final contractId = schedule['contract_id'] as int;
        final scheduleId = schedule['id'] as int;
        final amount = (schedule['amount'] as num).toDouble();
        final frequency = schedule['frequency'] as String;
        final end = DateTime.tryParse(schedule['end_date']?.toString() ?? '');
        final endDate = end == null ? null : DateTime(end.year, end.month, end.day);
        final next = DateTime.tryParse(schedule['next_due_date']?.toString() ?? '');
        if (next == null) continue;
        var due = DateTime(next.year, next.month, next.day);
        while (!due.isAfter(horizonDate) && (endDate == null || !due.isAfter(endDate))) {
          final dueKey = '${due.year.toString().padLeft(4, '0')}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
          final existing = await txn.query(
            'properties_rent_payments',
            columns: ['id'],
            where: 'schedule_id = ? AND substr(due_date, 1, 10) = ?',
            whereArgs: [scheduleId, dueKey],
            limit: 1,
          );
          if (existing.isEmpty) {
            await txn.insert('properties_rent_payments', {
              'contract_id': contractId,
              'schedule_id': scheduleId,
              'due_date': dueKey,
              'amount_due': amount,
              'amount_paid': 0,
              'paid_date': '',
              'status': due.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)) ? 'Overdue' : 'Pending',
              'payment_method': '',
              'reference': '',
              'notes': '',
              'created_at': DateTime.now().toIso8601String(),
            });
            created++;
          }
          if (frequency == 'One-time') {
            due = DateTime(9999);
            break;
          }
          final following = _nextRentDate(due, frequency);
          if (!following.isAfter(due)) throw StateError('Rent schedule frequency did not advance its due date.');
          due = following;
        }
        await txn.update(
          'properties_rent_schedules',
          {'next_due_date': due.toIso8601String()},
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
      }
    });
    if (created > 0) AppRefreshController.notifyChanged();
    return created;
  }

  static Future<List<Map<String, dynamic>>> rentPayments({int? contractId, String? status}) async {
    final db = DatabaseManager.instance.database;
    final today = DateTime.now();
    final todayKey = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await db.rawUpdate('''
      UPDATE properties_rent_payments
      SET status = CASE WHEN amount_paid > 0 THEN 'Partial' ELSE 'Pending' END
      WHERE status = 'Overdue' AND substr(due_date, 1, 10) >= ?
    ''', [todayKey]);
    await db.rawUpdate('''
      UPDATE properties_rent_payments SET status = 'Overdue'
      WHERE status IN ('Pending', 'Partial')
        AND amount_paid < amount_due
        AND substr(due_date, 1, 10) < ?
    ''', [todayKey]);
    final clauses = <String>[];
    final args = <Object?>[];
    if (contractId != null) { clauses.add('contract_id = ?'); args.add(contractId); }
    if (status != null) { clauses.add('status = ?'); args.add(status); }
    return db.query(
      'properties_rent_payments',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'due_date ASC, id DESC',
    );
  }

  static Future<int> saveRentPayment({
    int? id,
    required int contractId,
    int? scheduleId,
    required String dueDate,
    required double amountDue,
    required double amountPaid,
    required String paidDate,
    required String paymentMethod,
    required String reference,
    required String notes,
  }) async {
    if (!amountDue.isFinite || amountDue <= 0 || !amountPaid.isFinite || amountPaid < 0 || amountPaid > amountDue) {
      throw ArgumentError('Enter a valid rent due and paid amount.');
    }
    final db = DatabaseManager.instance.database;
    final contract = await db.query('properties_contracts', columns: ['id'], where: 'id = ?', whereArgs: [contractId], limit: 1);
    if (contract.isEmpty) throw StateError('Select a valid contract.');
    if (scheduleId != null) {
      final schedule = await db.query('properties_rent_schedules', columns: ['id'], where: 'id = ? AND contract_id = ?', whereArgs: [scheduleId, contractId], limit: 1);
      if (schedule.isEmpty) throw StateError('Rent schedule does not belong to this contract.');
    }
    final parsedDue = DateTime.tryParse(dueDate);
    final today = DateTime.now();
    final isPastDue = parsedDue != null && DateTime(parsedDue.year, parsedDue.month, parsedDue.day).isBefore(DateTime(today.year, today.month, today.day));
    final status = amountPaid >= amountDue ? 'Paid' : isPastDue ? 'Overdue' : amountPaid > 0 ? 'Partial' : 'Pending';
    final values = <String, Object?>{
      'contract_id': contractId, 'schedule_id': scheduleId,
      'due_date': dueDate, 'amount_due': amountDue,
      'amount_paid': amountPaid, 'paid_date': paidDate,
      'status': status, 'payment_method': paymentMethod.trim(),
      'reference': reference.trim(), 'notes': notes.trim(),
    };
    final result = id == null
        ? await db.insert('properties_rent_payments', {...values, 'created_at': DateTime.now().toIso8601String()})
        : await db.update('properties_rent_payments', values, where: 'id = ?', whereArgs: [id]);
    if (id != null && result == 0) throw StateError('Rent payment not found.');
    AppRefreshController.notifyChanged();
    return id ?? result;
  }

  static Future<void> deleteRentPayment(int id) async {
    await DatabaseManager.instance.database.delete('properties_rent_payments', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteContract(int id) async {
    final db = DatabaseManager.instance.database;
    final schedule = await db.query('properties_rent_schedules', columns: ['id'], where: 'contract_id = ?', whereArgs: [id], limit: 1);
    final payment = await db.query('properties_rent_payments', columns: ['id'], where: 'contract_id = ?', whereArgs: [id], limit: 1);
    if (schedule.isNotEmpty || payment.isNotEmpty) {
      throw StateError('Delete this contract\'s rent schedules and payments before deleting the contract.');
    }
    await db.delete('properties_contracts', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }
}
