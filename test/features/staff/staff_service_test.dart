import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';
import 'package:my_finance/features/staff/services/staff_service.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'my_finance_staff_test_',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    await FinanceDB.instance.init();
    await StaffService.ensureTables();
  });

  tearDown(() async {
    await FinanceDB.instance.close();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('salary payment updates wallet and keeps a linked salary record', () async {
    final walletId = await FinanceDB.instance.addWallet(
      name: 'Salary Test Wallet',
      type: 'Cash',
      currency: 'PKR',
      openingBalance: 500,
      iconCode: 1,
      excludeTotal: false,
    );
    final staffId = await StaffService.saveStaff(
      name: 'Test Staff',
      phone: '',
      role: 'Worker',
      salary: 100,
      joinedAt: DateTime(2026, 1, 1),
      notes: '',
    );

    final salaryId = await StaffService.paySalary(
      staffId: staffId,
      amount: 100,
      walletId: walletId,
      date: DateTime(2026, 11, 1),
      note: 'November',
    );

    final wallet = await FinanceDB.instance.getWallet(walletId);
    final salaries = await StaffService.getSalaries(staffId: staffId);
    expect(wallet!['balance'], 400);
    expect(salaries.single['id'], salaryId);
    expect(salaries.single['transaction_id'], isNotNull);
  });

  test('attendance upserts one record per staff member and date', () async {
    final staffId = await StaffService.saveStaff(
      name: 'Attendance Test',
      phone: '',
      role: '',
      salary: 0,
      joinedAt: DateTime(2026, 1, 1),
      notes: '',
    );
    final date = DateTime(2026, 11, 13, 15);

    await StaffService.saveAttendance(
      staffId: staffId,
      date: date,
      status: 'Present',
      note: '',
    );
    await StaffService.saveAttendance(
      staffId: staffId,
      date: date,
      status: 'Late',
      note: 'Arrived late',
    );

    final records = await StaffService.getAttendance(staffId: staffId);
    expect(records, hasLength(1));
    expect(records.single['status'], 'Late');
    expect(records.single['note'], 'Arrived late');
  });

  test('deleting and restoring staff preserves salary and attendance history', () async {
    final walletId = await FinanceDB.instance.addWallet(
      name: 'Restore Test Wallet',
      type: 'Cash',
      currency: 'PKR',
      openingBalance: 1000,
      iconCode: 1,
      excludeTotal: false,
    );
    final staffId = await StaffService.saveStaff(
      name: 'Restore Test Staff',
      phone: '',
      role: '',
      salary: 200,
      joinedAt: DateTime(2026, 1, 1),
      notes: 'Keep this note',
    );
    await StaffService.paySalary(
      staffId: staffId,
      amount: 200,
      walletId: walletId,
      date: DateTime(2026, 11, 1),
      note: '',
    );
    await StaffService.saveAttendance(
      staffId: staffId,
      date: DateTime(2026, 11, 13),
      status: 'Present',
      note: '',
    );

    await StaffService.deleteStaff(staffId);
    expect(await StaffService.getStaff(), isEmpty);
    expect(await StaffService.getSalaries(staffId: staffId), isEmpty);
    expect(await StaffService.getAttendance(staffId: staffId), isEmpty);

    final archived = (await RecycleBinService.getItems())
        .singleWhere((item) => item['source_table'] == 'staff');
    await RecycleBinService.restore(archived['id'] as int);

    final restored = (await StaffService.getStaff()).single;
    expect(restored['id'], staffId);
    expect(restored['notes'], 'Keep this note');
    expect(await StaffService.getSalaries(staffId: staffId), hasLength(1));
    expect(await StaffService.getAttendance(staffId: staffId), hasLength(1));
    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 800);
  });

  test('failed salary record insertion rolls back its transaction cleanly', () async {
    final walletId = await FinanceDB.instance.addWallet(
      name: 'Rollback Test Wallet',
      type: 'Cash',
      currency: 'PKR',
      openingBalance: 500,
      iconCode: 1,
      excludeTotal: false,
    );
    final staffId = await StaffService.saveStaff(
      name: 'Rollback Test Staff',
      phone: '',
      role: '',
      salary: 100,
      joinedAt: DateTime(2026, 1, 1),
      notes: '',
    );
    await FinanceDB.instance.db.execute('''
      CREATE TRIGGER fail_staff_salary_insert
      BEFORE INSERT ON staff_salaries
      BEGIN
        SELECT RAISE(ABORT, 'forced salary insert failure');
      END
    ''');

    await expectLater(
      StaffService.paySalary(
        staffId: staffId,
        amount: 100,
        walletId: walletId,
        date: DateTime(2026, 11, 1),
        note: '',
      ),
      throwsA(isA<Exception>()),
    );

    expect((await FinanceDB.instance.getWallet(walletId))!['balance'], 500);
    expect(await FinanceDB.instance.db.query('transactions'), isEmpty);
    expect(await RecycleBinService.getItems(), isEmpty);
  });

  test('permanently deleting archived staff removes only the archive entry', () async {
    final staffId = await StaffService.saveStaff(
      name: 'Permanent Delete Test',
      phone: '',
      role: '',
      salary: 0,
      joinedAt: DateTime(2026, 1, 1),
      notes: '',
    );

    await StaffService.deleteStaff(staffId);
    final archived = (await RecycleBinService.getItems())
        .singleWhere((item) => item['source_table'] == 'staff');

    await RecycleBinService.permanentlyDelete(archived['id'] as int);

    expect(await RecycleBinService.getItems(), isEmpty);
    expect(await StaffService.getStaff(), isEmpty);
  });

  test('restoring staff with a conflicting ID keeps the archive intact', () async {
    final originalId = await StaffService.saveStaff(
      name: 'Original Staff',
      phone: '',
      role: '',
      salary: 0,
      joinedAt: DateTime(2026, 1, 1),
      notes: '',
    );
    await StaffService.deleteStaff(originalId);
    final archived = (await RecycleBinService.getItems())
        .singleWhere((item) => item['source_table'] == 'staff');

    await FinanceDB.instance.db.insert('staff', {
      'id': originalId,
      'name': 'Replacement Staff',
      'phone': '',
      'role': '',
      'salary': 0,
      'joined_at': DateTime(2026, 2, 1).toIso8601String(),
      'notes': '',
    });

    await expectLater(
      RecycleBinService.restore(archived['id'] as int),
      throwsA(isA<Exception>()),
    );
    expect(await RecycleBinService.getItems(), hasLength(1));
    expect((await StaffService.getStaff()).single['name'], 'Replacement Staff');
  });

  test('attendance rejects a staff ID that does not exist', () async {
    await expectLater(
      StaffService.saveAttendance(
        staffId: 99999,
        date: DateTime(2026, 11, 13),
        status: 'Present',
        note: '',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
