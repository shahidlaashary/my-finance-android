import 'dart:convert';

import 'package:my_finance/modules/finance/models/loans_model.dart';
import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

/// Owns party records shared by Finance, Assets, Loans and future modules.
/// The existing loan database and party table are retained without schema changes.
class PartyService {
  static Future<String> getBaseCurrency() async {
    final db = DatabaseManager.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['main_currency'],
      limit: 1,
    );
    return (rows.isEmpty
            ? 'PKR'
            : rows.first['setting_value']?.toString() ?? 'PKR')
        .toUpperCase();
  }

  static Future<List<Map<String, dynamic>>> getParties({bool includeArchived = false}) async {
    final db = DatabaseManager.instance.database;
    return db.query(
      'loan_parties',
      where: includeArchived ? null : 'COALESCE(is_archived, 0) = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  static Future<void> setPartyArchived(int partyId, {required bool archived}) async {
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
        final linkedLoans = await txn.query(
          'loans',
          columns: ['id'],
          where: 'party_id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (linkedLoans.isNotEmpty) {
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
    final db = DatabaseManager.instance.database;
    await RecycleBinService.ensureTable();

    await db.transaction((txn) async {
      final linkedLoans = await txn.query(
        'loans',
        columns: ['id'],
        where: 'party_id = ?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (linkedLoans.isNotEmpty) {
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
            .add(const Duration(days: RecycleBinService.retentionDays))
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

  static Future<List<LoansModel>> getLoansForParty(int partyId) async {
    final db = DatabaseManager.instance.database;
    final rows = await db.query('loans', where: 'party_id = ?', whereArgs: [partyId], orderBy: 'lending_date DESC, id DESC');
    return rows.map(LoansModel.fromMap).toList();
  }

  static Future<Map<String, dynamic>> getPartySummary(int partyId) async {
    final db = DatabaseManager.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        UPPER(TRIM(COALESCE(loans.currency, wallets.currency, 'PKR'))) AS currency,
        loans.loan_type AS loan_type,
        COALESCE(SUM(loans.remaining_amount), 0) AS outstanding,
        COUNT(*) AS loan_count
      FROM loans
      LEFT JOIN wallets ON wallets.id = loans.wallet_id AND loans.wallet_id > 0
      WHERE loans.party_id = ?
      GROUP BY
        UPPER(TRIM(COALESCE(loans.currency, wallets.currency, 'PKR'))),
        loans.loan_type
      ORDER BY
        UPPER(TRIM(COALESCE(loans.currency, wallets.currency, 'PKR'))),
        loans.loan_type
    ''', [partyId]);
    return {
      'loan_count': rows.fold<int>(0, (sum, row) => sum + ((row['loan_count'] as num?)?.toInt() ?? 0)),
      'balances': rows.map((row) => {
        'currency': row['currency'],
        'loan_type': row['loan_type'],
        'outstanding': row['outstanding'],
      }).toList(),
    };
  }

 }
