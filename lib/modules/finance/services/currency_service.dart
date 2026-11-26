import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

/// Shared my_finance.db connection par base currency aur exchange rates ke data operations manage karta hai.
/// Database connection ki ownership DatabaseManager ke paas hi rehti hai.
class CurrencyService {
  CurrencyService._();

  static Database get _db => DatabaseManager.instance.database;

  static Future<double?> getExchangeRate(String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == 'PKR') return 1.0;
    final rows = await _db.query(
      'exchange_rates',
      columns: ['rate'],
      where: 'UPPER(currency) = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final rate = (rows.first['rate'] as num).toDouble();
    return rate.isFinite && rate > 0 ? rate : null;
  }

  static Future<String> getBaseCurrency() async {
    final rows = await _db.query(
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

  static Future<void> setBaseCurrency(String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized.isEmpty) throw Exception('Base currency select karein.');
    if (normalized != 'PKR' && await getExchangeRate(normalized) == null) {
      throw Exception('Is currency ka exchange rate pehle set karein.');
    }
    await _db.insert(
      'app_settings',
      {'setting_key': 'main_currency', 'setting_value': normalized},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppRefreshController.notifyChanged();
  }

  static Future<List<Map<String, dynamic>>> getExchangeRates() =>
      _db.query('exchange_rates', orderBy: 'currency COLLATE NOCASE ASC');

  static Future<void> saveExchangeRate(
    String currency,
    double rate, {
    String source = 'manual',
  }) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == 'PKR' ||
        normalized.isEmpty ||
        !rate.isFinite ||
        rate <= 0) {
      throw Exception('Exchange rate durust nahi hai.');
    }
    await _db.insert(
      'exchange_rates',
      {
        'currency': normalized,
        'rate': rate,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppRefreshController.notifyChanged();
  }

  static Future<bool> refreshMissingExchangeRatesOnline({
    required List<String> currencies,
  }) async {
    final required = currencies
        .map((code) => code.trim().toUpperCase())
        .where((code) => code.isNotEmpty && code != 'PKR')
        .toSet();
    final missing = <String>[];
    for (final currency in required) {
      if (await getExchangeRate(currency) == null) missing.add(currency);
    }
    if (missing.isEmpty) return true;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .getUrl(Uri.parse('https://open.er-api.com/v6/latest/PKR'))
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) return false;
      final body = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 20));
      final payload = jsonDecode(body) as Map<String, dynamic>;
      if (payload['result'] != 'success') return false;
      final rates = payload['rates'] as Map<String, dynamic>?;
      if (rates == null) return false;

      for (final currency in missing) {
        final providerRate = rates[currency];
        if (providerRate is! num || providerRate <= 0) continue;
        final pkrPerUnit = 1 / providerRate.toDouble();
        if (pkrPerUnit.isFinite && pkrPerUnit > 0) {
          await saveExchangeRate(currency, pkrPerUnit, source: 'automatic');
        }
      }
      for (final currency in missing) {
        if (await getExchangeRate(currency) == null) return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<double> getTotalBalanceInBaseCurrency() async {
    final baseCurrency = await getBaseCurrency();
    final baseRate = await getExchangeRate(baseCurrency);
    if (baseRate == null || baseRate <= 0) {
      throw Exception('Base currency ka exchange rate available nahi.');
    }
    final wallets = await _db.query('wallets', where: 'exclude_total = 0');
    double total = 0;
    for (final wallet in wallets) {
      final currency = (wallet['currency'] as String).toUpperCase();
      final balance = (wallet['balance'] as num).toDouble();
      final rate = await getExchangeRate(currency);
      if (rate == null) {
        throw Exception('Exchange rate for $currency is missing.');
      }
      total += balance * rate / baseRate;
    }
    return total;
  }
}
