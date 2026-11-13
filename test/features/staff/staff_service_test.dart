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
