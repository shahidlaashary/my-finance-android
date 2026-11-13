import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

class StaffService {
  static Future<void> ensureTables() async {
    final db = FinanceDB.instance.db;
    await db.execute('''CREATE TABLE IF NOT EXISTS staff (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '', role TEXT NOT NULL DEFAULT '',
      salary REAL NOT NULL DEFAULT 0, joined_at TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '')''');
    await db.execute('''CREATE TABLE IF NOT EXISTS staff_salaries (
      id INTEGER PRIMARY KEY AUTOINCREMENT, staff_id INTEGER NOT NULL,
      amount REAL NOT NULL, wallet_id INTEGER NOT NULL, paid_at TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '', transaction_id INTEGER)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS staff_attendance (
      id INTEGER PRIMARY KEY AUTOINCREMENT, staff_id INTEGER NOT NULL,
      attendance_date TEXT NOT NULL, status TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '', UNIQUE(staff_id, attendance_date))''');
  }

  static Future<List<Map<String, dynamic>>> getStaff() async {
    await ensureTables();
    return FinanceDB.instance.db.query('staff', orderBy: 'name COLLATE NOCASE');
  }

  static Future<List<Map<String, dynamic>>> getSalaries({int? staffId}) async {
    await ensureTables();
    return FinanceDB.instance.db.query('staff_salaries',
      where: staffId == null ? null : 'staff_id = ?',
      whereArgs: staffId == null ? null : [staffId],
      orderBy: 'paid_at DESC, id DESC');
  }

  static Future<List<Map<String, dynamic>>> getAttendance({int? staffId, String? month}) async {
    await ensureTables();
    String? where;
    final args = <Object?>[];
    if (staffId != null) { where = 'staff_id = ?'; args.add(staffId); }
    if (month != null) { where = where == null ? 'attendance_date LIKE ?' : '$where AND attendance_date LIKE ?'; args.add('$month%'); }
    return FinanceDB.instance.db.query('staff_attendance', where: where,
      whereArgs: args.isEmpty ? null : args, orderBy: 'attendance_date DESC, id DESC');
  }

  static Future<int> saveStaff({int? id, required String name, required String phone,
    required String role, required double salary, required DateTime joinedAt, required String notes}) async {
    await ensureTables();
    if (name.trim().isEmpty || !salary.isFinite || salary < 0) throw Exception('Enter valid staff details.');
    final values = {'name': name.trim(), 'phone': phone.trim(), 'role': role.trim(),
      'salary': salary, 'joined_at': joinedAt.toIso8601String(), 'notes': notes.trim()};
    final db = FinanceDB.instance.db;
    final result = id == null ? await db.insert('staff', values)
      : await db.update('staff', values, where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
    return id ?? result;
  }

  static Future<void> deleteStaff(int id) async {
    await ensureTables();
    final db = FinanceDB.instance.db;
    final staffRows = await db.query('staff', where: 'id = ?', whereArgs: [id], limit: 1);
    if (staffRows.isEmpty) return;
    final salaries = await db.query('staff_salaries', where: 'staff_id = ?', whereArgs: [id]);
    final attendance = await db.query('staff_attendance', where: 'staff_id = ?', whereArgs: [id]);
    final related = <Map<String, dynamic>>[
      ...salaries.map((row) => {...row, '_related_table':'staff_salaries'}),
      ...attendance.map((row) => {...row, '_related_table':'staff_attendance'}),
    ];
    await RecycleBinService.archive(type: 'Staff', title: staffRows.first['name']?.toString() ?? 'Staff',
      table: 'staff', id: id, record: staffRows.first, related: related);
    await db.transaction((txn) async {
      await txn.delete('staff_salaries', where: 'staff_id = ?', whereArgs: [id]);
      await txn.delete('staff_attendance', where: 'staff_id = ?', whereArgs: [id]);
      await txn.delete('staff', where: 'id = ?', whereArgs: [id]);
    });
    AppRefreshController.notifyChanged();
  }
  static Future<int> paySalary({required int staffId, required double amount,
    required int walletId, required DateTime date, required String note}) async {
    await ensureTables();
    if (!amount.isFinite || amount <= 0) throw Exception('Enter a valid salary amount.');
    final staff = await FinanceDB.instance.db.query('staff', where: 'id = ?', whereArgs: [staffId], limit: 1);
    if (staff.isEmpty) throw Exception('Staff member not found.');
    final name = staff.first['name'].toString();
    final txId = await TransactionsService.addTransaction(type: 'Expense', amount: amount,
      walletId: walletId, category: 'Staff Salary',
      note: 'Salary • $name${note.trim().isEmpty ? '' : ' • ${note.trim()}'}',
      date: date.toIso8601String());
    try {
      final id = await FinanceDB.instance.db.insert('staff_salaries', {
        'staff_id': staffId, 'amount': amount, 'wallet_id': walletId,
        'paid_at': date.toIso8601String(), 'note': note.trim(), 'transaction_id': txId,
      });
      AppRefreshController.notifyChanged();
      return id;
    } catch (_) {
      await TransactionsService.deleteTransaction(txId);
      rethrow;
    }
  }

  static Future<void> saveAttendance({required int staffId, required DateTime date,
    required String status, required String note}) async {
    await ensureTables();
    const allowed = ['Present', 'Absent', 'Late', 'Leave', 'Half Day'];
    if (!allowed.contains(status)) throw Exception('Select a valid attendance status.');
    await FinanceDB.instance.db.insert('staff_attendance', {
      'staff_id': staffId,
      'attendance_date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'status': status, 'note': note.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    AppRefreshController.notifyChanged();
  }
}
