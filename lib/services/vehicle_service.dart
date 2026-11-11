import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_refresh_service.dart';
import 'transactions_service.dart';

/// Vehicle data uses the existing app_settings key-value table.
/// No database schema changes or migrations are required.
class VehicleService {
  VehicleService._();
  static const String _storageKey = 'vehicle_manager_data_v1';

  static Future<Map<String, dynamic>> _read() async {
    final db = await TransactionsService.database;
    final rows = await db.query('app_settings',
      columns: ['setting_value'], where: 'setting_key = ?',
      whereArgs: [_storageKey], limit: 1);
    if (rows.isEmpty) {
      return {'vehicles': [], 'fuel_logs': [], 'expenses': [], 'reminders': []};
    }
    final decoded = jsonDecode(rows.first['setting_value']?.toString() ?? '');
    if (decoded is! Map) throw Exception('Vehicle data format is not valid.');
    final data = Map<String, dynamic>.from(decoded);
    for (final key in ['vehicles', 'fuel_logs', 'expenses', 'reminders']) {
      if (data[key] is! List) data[key] = <dynamic>[];
    }
    return data;
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    final db = await TransactionsService.database;
    await db.insert('app_settings',
      {'setting_key': _storageKey, 'setting_value': jsonEncode(data)},
      conflictAlgorithm: ConflictAlgorithm.replace);
    AppRefreshController.notifyChanged();
  }

  static int newId() => DateTime.now().microsecondsSinceEpoch;
  static Future<List<Map<String, dynamic>>> getVehicles() async {
    final data = await _read();
    final rows = (data['vehicles'] as List).whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e)).toList();
    rows.sort((a,b) => (a['name'] ?? '').toString().toLowerCase()
      .compareTo((b['name'] ?? '').toString().toLowerCase()));
    return rows;
  }

  static Future<List<Map<String, dynamic>>> _getRows(String key, int? vehicleId) async {
    final data = await _read();
    final rows = (data[key] as List).whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((e) => vehicleId == null || e['vehicle_id'] == vehicleId).toList();
    final dateKey = key == 'reminders' ? 'due_date' : 'date';
    rows.sort((a,b) => (b[dateKey] ?? '').toString().compareTo((a[dateKey] ?? '').toString()));
    return rows;
  }
  static Future<List<Map<String, dynamic>>> getFuelLogs({int? vehicleId}) => _getRows('fuel_logs', vehicleId);
  static Future<List<Map<String, dynamic>>> getExpenses({int? vehicleId}) => _getRows('expenses', vehicleId);
  static Future<List<Map<String, dynamic>>> getReminders({int? vehicleId}) => _getRows('reminders', vehicleId);
  static Future<List<Map<String, dynamic>>> getWallets() => TransactionsService.getAccounts();

  static Future<void> saveVehicle(Map<String, dynamic> vehicle) async {
    final data = await _read();
    final rows = (data['vehicles'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final id = vehicle['id'] as int?;
    if (id == null) {
      vehicle['id'] = newId();
      vehicle['created_at'] = DateTime.now().toIso8601String();
      rows.add(vehicle);
    } else {
      final index = rows.indexWhere((e) => e['id'] == id);
      if (index < 0) throw Exception('Vehicle not found.');
      rows[index] = vehicle;
    }
    data['vehicles'] = rows;
    await _write(data);
  }

  static Future<void> deleteVehicle(int id) async {
    final data = await _read();
    bool linked(String key) => (data[key] as List).any((e) => e is Map && e['vehicle_id'] == id);
    if (linked('fuel_logs') || linked('expenses') || linked('reminders')) {
      throw Exception('This vehicle has records. Manage its linked records first.');
    }
    data['vehicles'] = (data['vehicles'] as List).where((e) => e is Map && e['id'] != id).toList();
    await _write(data);
  }

  static Future<void> _validateOdometer(int vehicleId, double reading) async {
    if (!reading.isFinite || reading < 0) throw Exception('Enter a valid odometer reading.');
    final data = await _read();
    final readings = <double>[];
    for (final key in ['fuel_logs', 'expenses']) {
      for (final row in data[key] as List) {
        if (row is Map && row['vehicle_id'] == vehicleId && row['odometer'] is num) {
          readings.add((row['odometer'] as num).toDouble());
        }
      }
    }
    if (readings.isNotEmpty && reading < readings.reduce((a,b) => a > b ? a : b)) {
      throw Exception('Odometer reading cannot be lower than a previous vehicle record.');
    }
  }

  static Future<int> addFuel({
    required int vehicleId, required String vehicleName, required DateTime date,
    required double odometer, required double quantity, required double unitPrice,
    required bool fullTank, required int walletId, required String station,
    required String notes, required String unit,
  }) async {
    if (!quantity.isFinite || quantity <= 0 || !unitPrice.isFinite || unitPrice <= 0) {
      throw Exception('Enter valid quantity and unit price.');
    }
    await _validateOdometer(vehicleId, odometer);
    final total = quantity * unitPrice;
    final txId = await TransactionsService.addTransaction(type: 'Expense',
      amount: total, walletId: walletId, category: 'Vehicle Fuel',
      note: 'Fuel • $vehicleName • ${quantity.toStringAsFixed(2)} $unit • ${odometer.toStringAsFixed(0)} km${station.isEmpty ? '' : ' • $station'}',
      date: date.toIso8601String());
    try {
      final data = await _read();
      final id = newId();
      (data['fuel_logs'] as List).add({
        'id': id, 'vehicle_id': vehicleId, 'date': date.toIso8601String(),
        'odometer': odometer, 'quantity': quantity, 'unit_price': unitPrice,
        'total': total, 'full_tank': fullTank, 'wallet_id': walletId,
        'station': station, 'notes': notes, 'unit': unit, 'transaction_id': txId,
      });
      await _write(data);
      return id;
    } catch (_) {
      await TransactionsService.deleteTransaction(txId);
      rethrow;
    }
  }

  static Future<int> addExpense({
    required int vehicleId, required String vehicleName, required DateTime date,
    required double amount, required double odometer, required int walletId,
    required String category, required String vendor, required String notes,
  }) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Enter a valid amount.');
    await _validateOdometer(vehicleId, odometer);
    final txId = await TransactionsService.addTransaction(type: 'Expense',
      amount: amount, walletId: walletId, category: 'Vehicle • $category',
      note: 'Vehicle • $vehicleName • $category${vendor.isEmpty ? '' : ' • $vendor'}${notes.isEmpty ? '' : ' • $notes'}',
      date: date.toIso8601String());
    try {
      final data = await _read();
      final id = newId();
      (data['expenses'] as List).add({
        'id': id, 'vehicle_id': vehicleId, 'date': date.toIso8601String(),
        'amount': amount, 'odometer': odometer, 'wallet_id': walletId,
        'category': category, 'vendor': vendor, 'notes': notes, 'transaction_id': txId,
      });
      await _write(data);
      return id;
    } catch (_) {
      await TransactionsService.deleteTransaction(txId);
      rethrow;
    }
  }

  static Future<void> _deleteLinked(String key, int id) async {
    final data = await _read();
    final rows = (data[key] as List).whereType<Map>().toList();
    Map? record;
    for (final row in rows) { if (row['id'] == id) { record = row; break; } }
    if (record == null) return;
    final previous = data[key];
    data[key] = rows.where((e) => e['id'] != id).toList();
    await _write(data);
    try {
      final txId = record['transaction_id'];
      if (txId is int) await TransactionsService.deleteTransaction(txId);
    } catch (_) {
      data[key] = previous;
      await _write(data);
      rethrow;
    }
  }
  static Future<void> deleteFuel(int id) => _deleteLinked('fuel_logs', id);
  static Future<void> deleteExpense(int id) => _deleteLinked('expenses', id);

  static Future<void> saveReminder(Map<String, dynamic> reminder) async {
    final data = await _read();
    final rows = (data['reminders'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final id = reminder['id'] as int?;
    if (id == null) {
      reminder['id'] = newId();
      reminder['created_at'] = DateTime.now().toIso8601String();
      rows.add(reminder);
    } else {
      final index = rows.indexWhere((e) => e['id'] == id);
      if (index < 0) throw Exception('Reminder not found.');
      rows[index] = reminder;
    }
    data['reminders'] = rows;
    await _write(data);
  }
  static Future<void> deleteReminder(int id) async {
    final data = await _read();
    data['reminders'] = (data['reminders'] as List).where((e) => e is Map && e['id'] != id).toList();
    await _write(data);
  }
}
