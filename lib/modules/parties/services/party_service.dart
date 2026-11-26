import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/services/recycle_bin_archive_service.dart';
import 'package:my_finance/modules/finance/services/currency_service.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';

/// Owns party records shared by Finance, Assets, Loans and future modules.
/// The existing loan database and party table are retained without schema changes.
class PartyService {
  /// Creates the shared party table. PartyService is its single owner.
  static Future<void> ensureTables() async {
    final db = DatabaseManager.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT NOT NULL DEFAULT '',
        currency TEXT NOT NULL DEFAULT 'PKR',
        notes TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        party_type TEXT NOT NULL DEFAULT 'Individual',
        country TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        postal_code TEXT NOT NULL DEFAULT '',
        opening_balance REAL NOT NULL DEFAULT 0,
        credit_limit REAL NOT NULL DEFAULT 0,
        payment_terms TEXT NOT NULL DEFAULT 'Due on Receipt',
        cnic TEXT NOT NULL DEFAULT '',
        business_name TEXT NOT NULL DEFAULT '',
        tax_number TEXT NOT NULL DEFAULT '',
        reference_person TEXT NOT NULL DEFAULT '',
        profile_image_path TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// Base-currency settings are owned by CurrencyService.
  static Future<String> getBaseCurrency() => CurrencyService.getBaseCurrency();

  static Future<List<Map<String, dynamic>>> getParties({bool includeArchived = false}) async {
    await ensureTables();
    final db = DatabaseManager.instance.database;
    return db.query(
      'loan_parties',
      where: includeArchived ? null : 'COALESCE(is_archived, 0) = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  static Future<void> setPartyArchived(int partyId, {required bool archived}) async {
    await ensureTables();
    final db = DatabaseManager.instance.database;
    final changed = await db.update(
      'loan_parties',
      {'is_archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [partyId],
    );
    if (changed != 1) throw Exception('Party was not found or could not be updated.');
    AppRefreshController.notifyChanged();
  }

  static Future<int> addParty({
    required String name,
    String? phone,
    String address = '',
    String notes = '',
    String currency = 'PKR',
    String email = '',
    String partyType = 'Individual',
    String country = '',
    String city = '',
    String postalCode = '',
    double openingBalance = 0,
    double creditLimit = 0,
    String paymentTerms = 'Due on Receipt',
    String cnic = '',
    String businessName = '',
    String taxNumber = '',
    String referencePerson = '',
    String profileImagePath = '',
  }) async {
    await ensureTables();
    final db = DatabaseManager.instance.database;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw Exception('Party name is required.');
    final normalizedPhone = phone?.trim() ?? '';
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty) throw Exception('Party currency is required.');

    final id = await db.transaction((txn) async {
      final existing = await txn.query(
        'loan_parties',
        columns: ['id'],
        where: 'LOWER(TRIM(name)) = LOWER(?) AND LOWER(TRIM(party_type)) = LOWER(?)',
        whereArgs: [normalizedName, partyType.trim()],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw Exception(
          'A party with this name already exists under $partyType type.',
        );
      }

      return txn.insert('loan_parties', {
        'name': normalizedName,
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'address': address.trim(),
        'currency': normalizedCurrency,
        'notes': notes.trim(),
        'email': email.trim(),
        'party_type': partyType,
        'country': country.trim(),
        'city': city.trim(),
        'postal_code': postalCode.trim(),
        'opening_balance': openingBalance,
        'credit_limit': creditLimit,
        'payment_terms': paymentTerms,
        'cnic': cnic.trim(),
        'business_name': businessName.trim(),
        'tax_number': taxNumber.trim(),
        'reference_person': referencePerson.trim(),
        'profile_image_path': profileImagePath,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  static Future<void> updateParty({
    required int id,
    required String name,
    String? phone,
    String address = '',
    String currency = 'PKR',
    String notes = '',
    String email = '',
    String partyType = 'Individual',
    String country = '',
    String city = '',
    String postalCode = '',
    double openingBalance = 0,
    double creditLimit = 0,
    String paymentTerms = 'Due on Receipt',
    String cnic = '',
    String businessName = '',
    String taxNumber = '',
    String referencePerson = '',
    String profileImagePath = '',
  }) async {
    final db = DatabaseManager.instance.database;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw Exception('Party name is required.');
    final normalizedPhone = phone?.trim() ?? '';
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty) throw Exception('Party currency is required.');

    await db.transaction((txn) async {
      final currentRows = await txn.query(
        'loan_parties',
        columns: ['id', 'currency'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (currentRows.isEmpty) throw Exception('Party was not found.');

      final currentCurrency =
          (currentRows.first['currency']?.toString() ?? 'PKR').toUpperCase();
      if (currentCurrency != normalizedCurrency) {
        final hasLinkedLoans = await LoansService.hasLoansForParty(txn, id);
        if (hasLinkedLoans) {
          throw Exception(
            'Party currency cannot be changed while loan history is linked to this party.',
          );
        }
      }

      final duplicate = await txn.query(
        'loan_parties',
        columns: ['id'],
        where: 'id != ? AND LOWER(TRIM(name)) = LOWER(?) AND LOWER(TRIM(party_type)) = LOWER(?)',
        whereArgs: [id, normalizedName, partyType.trim()],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw Exception(
          'A party with this name already exists under $partyType type.',
        );
      }

      final changed = await txn.update(
        'loan_parties',
        {
          'name': normalizedName,
          'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
          'address': address.trim(),
          'currency': normalizedCurrency,
          'notes': notes.trim(),
          'email': email.trim(),
          'party_type': partyType,
          'country': country.trim(),
          'city': city.trim(),
          'postal_code': postalCode.trim(),
          'opening_balance': openingBalance,
          'credit_limit': creditLimit,
          'payment_terms': paymentTerms,
          'cnic': cnic.trim(),
          'business_name': businessName.trim(),
          'tax_number': taxNumber.trim(),
          'reference_person': referencePerson.trim(),
          'profile_image_path': profileImagePath,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed != 1) throw Exception('Party could not be updated.');
    });
    AppRefreshController.notifyChanged();
  }

  /// Party sirf tab delete hoti hai jab us ke sath koi loan linked na ho.
  static Future<void> deleteParty(int partyId) async {
    await ensureTables();
    final db = DatabaseManager.instance.database;
    await RecycleBinArchiveService.ensureTable();

    await db.transaction((txn) async {
      final hasLinkedLoans = await LoansService.hasLoansForParty(txn, partyId);
      if (hasLinkedLoans) {
        throw Exception(
          'This party has loan history. Delete is blocked to protect linked loans and ledger records.',
        );
      }

      final rows = await txn.query(
        'loan_parties',
        where: 'id = ?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final now = DateTime.now();
      await txn.insert('recycle_bin', {
        'entity_type': 'Loan Party',
        'entity_title': rows.first['name']?.toString() ?? 'Party',
        'source_table': 'loan_parties',
        'source_id': partyId.toString(),
        'payload': jsonEncode(rows.first),
        'deleted_at': now.toIso8601String(),
        'expires_at': now
            .add(const Duration(days: RecycleBinArchiveService.retentionDays))
            .toIso8601String(),
      });
      final deleted = await txn.delete(
        'loan_parties',
        where: 'id = ?',
        whereArgs: [partyId],
      );
      if (deleted != 1) throw Exception('Party could not be deleted.');
    });
    AppRefreshController.notifyChanged();
  }

  /// Restores a deleted loan party inside the caller's active DB transaction.
  /// The caller removes the Recycle Bin envelope in the same transaction.
  static Future<void> restoreArchivedParty(
    Transaction txn,
    Map<String, dynamic> record,
  ) async {
    final partyId = (record['id'] as num?)?.toInt();
    if (partyId == null || partyId <= 0) {
      throw Exception('The archived Loan Party has an invalid ID.');
    }
    final existing = await txn.query(
      'loan_parties',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [partyId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw Exception('This Loan Party already exists.');
    }
    final archivedName = (record['name']?.toString() ?? '').trim();
    final archivedType =
        (record['party_type']?.toString() ?? 'Individual').trim();
    if (archivedName.isEmpty || archivedType.isEmpty) {
      throw Exception('The archived Loan Party has an invalid name or type.');
    }
    final duplicate = await txn.query(
      'loan_parties',
      columns: ['id'],
      where: 'LOWER(TRIM(name)) = LOWER(?) AND LOWER(TRIM(party_type)) = LOWER(?)',
      whereArgs: [archivedName, archivedType],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw Exception(
        'A party with this name already exists under $archivedType type.',
      );
    }
    await txn.insert('loan_parties', record);
  }

  static Future<List<LoansModel>> getLoansForParty(int partyId) =>
      LoansService.getLoansForParty(partyId);

  static Future<Map<String, dynamic>> getPartySummary(int partyId) =>
      LoansService.getPartySummary(partyId);

 }
