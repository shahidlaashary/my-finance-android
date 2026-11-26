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
    if (normalized == await getBaseCurrency()) return 1.0;
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
    final currentBase = await getBaseCurrency();
    if (normalized == currentBase) return;

    // Agar selected currency ka cached rate mojood ho to existing rates
    // ko naye base ke mutabiq rebase karein. Offline aur missing-rate ki
    // surat mein purane reference ke rates ko ghalat samajhne ke bajaye
    // unhein clear karein; online refresh baad mein fresh rates la sakta hai.
    final newBaseRate = await getExchangeRate(normalized);
    final canRebase = newBaseRate != null && newBaseRate.isFinite &&
        newBaseRate > 0;

    await _db.transaction((txn) async {
      if (canRebase) {
        final rows = await txn.query('exchange_rates');
        for (final row in rows) {
          final code = row['currency'].toString().toUpperCase();
          final oldRate = (row['rate'] as num).toDouble();
          final rebasedRate = oldRate / newBaseRate!;
          if (!rebasedRate.isFinite || rebasedRate <= 0) continue;
          await txn.update(
            'exchange_rates',
            {
              'rate': code == normalized ? 1.0 : rebasedRate,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'UPPER(currency) = ?',
            whereArgs: [code],
          );
        }
      } else {
        // Old rates purani base currency ke reference mein thay; unhein
        // naye base ke rates ke taur par reuse karna incorrect conversion dega.
        await txn.delete('exchange_rates');
      }
      await txn.insert(
        'exchange_rates',
        {
          'currency': normalized,
          'rate': 1.0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'app_settings',
        {'setting_key': 'main_currency', 'setting_value': normalized},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    AppRefreshController.notifyChanged();
  }

  static Future<List<Map<String, dynamic>>> getExchangeRates() =>
      _db.query('exchange_rates', orderBy: 'currency COLLATE NOCASE ASC');

  /// Manual currency pairs Base Currency se independent save hote hain.
  static Future<List<Map<String, dynamic>>> getManualCurrencyPairs() =>
      _db.query('manual_currency_pairs',
          orderBy: 'from_currency COLLATE NOCASE ASC, to_currency COLLATE NOCASE ASC');

  static Future<void> saveManualCurrencyPair(
    String fromCurrency,
    String toCurrency,
    double rate,
  ) async {
    final from = fromCurrency.trim().toUpperCase();
    final to = toCurrency.trim().toUpperCase();
    if (from.isEmpty || to.isEmpty || from == to ||
        !rate.isFinite || rate <= 0) {
      throw Exception('Currency pair ya exchange rate durust nahi hai.');
    }
    await _db.insert(
      'manual_currency_pairs',
      {
        'from_currency': from,
        'to_currency': to,
        'rate': rate,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteManualCurrencyPair(int id) async {
    await _db.delete('manual_currency_pairs', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }

  /// Direct pair ko priority deta hai; reverse pair ho to reciprocal use karta hai.
  static Future<double?> getManualPairRate(String fromCurrency, String toCurrency) async {
    final from = fromCurrency.trim().toUpperCase();
    final to = toCurrency.trim().toUpperCase();
    if (from == to) return 1.0;
    final direct = await _db.query('manual_currency_pairs',
        columns: ['rate'], where: 'from_currency = ? AND to_currency = ?',
        whereArgs: [from, to], limit: 1);
    if (direct.isNotEmpty) {
      final value = (direct.first['rate'] as num).toDouble();
      return value.isFinite && value > 0 ? value : null;
    }
    final reverse = await _db.query('manual_currency_pairs',
        columns: ['rate'], where: 'from_currency = ? AND to_currency = ?',
        whereArgs: [to, from], limit: 1);
    if (reverse.isNotEmpty) {
      final value = (reverse.first['rate'] as num).toDouble();
      return value.isFinite && value > 0 ? 1 / value : null;
    }
    return null;
  }


  static Future<void> saveExchangeRate(
    String currency,
    double rate, {
    String source = 'manual',
  }) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == await getBaseCurrency() ||
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
    final baseCurrency = await getBaseCurrency();
    final required = currencies
        .map((code) => code.trim().toUpperCase())
        .where((code) => code.isNotEmpty && code != baseCurrency)
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

      final baseProviderRate = baseCurrency == 'PKR' ? 1.0 : rates[baseCurrency];
      if (baseProviderRate is! num || baseProviderRate <= 0) return false;
      for (final currency in missing) {
        final providerRate = rates[currency];
        if (providerRate is! num || providerRate <= 0) continue;
        // Provider PKR reference deta hai; isay app ki Base Currency mein badlein.
        final basePerUnit = baseProviderRate.toDouble() / providerRate.toDouble();
        if (basePerUnit.isFinite && basePerUnit > 0) {
          await saveExchangeRate(currency, basePerUnit, source: 'automatic');
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

  /// Network state ke mutabiq conversion source select karta hai.
  static Future<bool> isOnline() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(const Duration(seconds: 4));
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Online Automatic rate; offline saved Manual currency-pair rate.
  static Future<double?> getEffectivePairRate(
    String fromCurrency,
    String toCurrency, {
    bool? online,
  }) async {
    final from = fromCurrency.trim().toUpperCase();
    final to = toCurrency.trim().toUpperCase();
    if (from.isEmpty || to.isEmpty) return null;
    if (from == to) return 1.0;
    final useAutomatic = online ?? await isOnline();
    if (!useAutomatic) return getManualPairRate(from, to);
    final fromRate = await getExchangeRate(from);
    final toRate = await getExchangeRate(to);
    if (fromRate == null || toRate == null || toRate <= 0) return null;
    final pairRate = fromRate / toRate;
    return pairRate.isFinite && pairRate > 0 ? pairRate : null;
  }

  static Future<double> getTotalBalanceInBaseCurrency() async {
    final baseCurrency = await getBaseCurrency();
    final online = await isOnline();
    final wallets = await _db.query('wallets', where: 'exclude_total = 0');
    double total = 0;
    for (final wallet in wallets) {
      final currency = (wallet['currency'] as String).toUpperCase();
      final balance = (wallet['balance'] as num).toDouble();
      final rate = await getEffectivePairRate(currency, baseCurrency, online: online);
      if (rate == null) {
        throw Exception('Manual/automatic rate for $currency → $baseCurrency is missing.');
      }
      total += balance * rate;
    }
    return total;
  }ort 'dart:convert';
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
    if (normalized == await getBaseCurrency()) return 1.0;
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
    final currentBase = await getBaseCurrency();
    if (normalized == currentBase) return;

    // Agar selected currency ka cached rate mojood ho to existing rates
    // ko naye base ke mutabiq rebase karein. Offline aur missing-rate ki
    // surat mein purane reference ke rates ko ghalat samajhne ke bajaye
    // unhein clear karein; online refresh baad mein fresh rates la sakta hai.
    final newBaseRate = await getExchangeRate(normalized);
    final canRebase = newBaseRate != null && newBaseRate.isFinite &&
        newBaseRate > 0;

    await _db.transaction((txn) async {
      if (canRebase) {
        final rows = await txn.query('exchange_rates');
        for (final row in rows) {
          final code = row['currency'].toString().toUpperCase();
          final oldRate = (row['rate'] as num).toDouble();
          final rebasedRate = oldRate / newBaseRate!;
          if (!rebasedRate.isFinite || rebasedRate <= 0) continue;
          await txn.update(
            'exchange_rates',
            {
              'rate': code == normalized ? 1.0 : rebasedRate,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'UPPER(currency) = ?',
            whereArgs: [code],
          );
        }
      } else {
        // Old rates purani base currency ke reference mein thay; unhein
        // naye base ke rates ke taur par reuse karna incorrect conversion dega.
        await txn.delete('exchange_rates');
      }
      await txn.insert(
        'exchange_rates',
        {
          'currency': normalized,
          'rate': 1.0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'app_settings',
        {'setting_key': 'main_currency', 'setting_value': normalized},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    AppRefreshController.notifyChanged();
  }

  static Future<List<Map<String, dynamic>>> getExchangeRates() =>
      _db.query('exchange_rates', orderBy: 'currency COLLATE NOCASE ASC');

  /// Manual currency pairs Base Currency se independent save hote hain.
  static Future<List<Map<String, dynamic>>> getManualCurrencyPairs() =>
      _db.query('manual_currency_pairs',
          orderBy: 'from_currency COLLATE NOCASE ASC, to_currency COLLATE NOCASE ASC');

  static Future<void> saveManualCurrencyPair(
    String fromCurrency,
    String toCurrency,
    double rate,
  ) async {
    final from = fromCurrency.trim().toUpperCase();
    final to = toCurrency.trim().toUpperCase();
    if (from.isEmpty || to.isEmpty || from == to ||
        !rate.isFinite || rate <= 0) {
      throw Exception('Currency pair ya exchange rate durust nahi hai.');
    }
    await _db.insert(
      'manual_currency_pairs',
      {
        'from_currency': from,
        'to_currency': to,
        'rate': rate,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteManualCurrencyPair(int id) async {
    await _db.delete('manual_currency_pairs', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }

  /// Direct pair ko priority deta hai; reverse pair ho to reciprocal use karta hai.
  static Future<double?> getManualPairRate(String fromCurrency, String toCurrency) async {
    final from = fromCurrency.trim().toUpperCase();
    final to = toCurrency.trim().toUpperCase();
    if (from == to) return 1.0;
    final direct = await _db.query('manual_currency_pairs',
        columns: ['rate'], where: 'from_currency = ? AND to_currency = ?',
        whereArgs: [from, to], limit: 1);
    if (direct.isNotEmpty) {
      final value = (direct.first['rate'] as num).toDouble();
      return value.isFinite && value > 0 ? value : null;
    }
    final reverse = await _db.query('manual_currency_pairs',
        columns: ['rate'], where: 'from_currency = ? AND to_currency = ?',
        whereArgs: [to, from], limit: 1);
    if (reverse.isNotEmpty) {
      final value = (reverse.first['rate'] as num).toDouble();
      return value.isFinite && value > 0 ? 1 / value : null;
    }
    return null;
  }


  static Future<void> saveExchangeRate(
    String currency,
    double rate, {
    String source = 'manual',
  }) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == await getBaseCurrency() ||
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
    final baseCurrency = await getBaseCurrency();
    final required = currencies
        .map((code) => code.trim().toUpperCase())
        .where((code) => code.isNotEmpty && code != baseCurrency)
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

      final baseProviderRate = baseCurrency == 'PKR' ? 1.0 : rates[baseCurrency];
      if (baseProviderRate is! num || baseProviderRate <= 0) return false;
      for (final currency in missing) {
        final providerRate = rates[currency];
        if (providerRate is! num || providerRate <= 0) continue;
        // Provider PKR reference deta hai; isay app ki Base Currency mein badlein.
        final basePerUnit = baseProviderRate.toDouble() / providerRate.toDouble();
        if (basePerUnit.isFinite && basePerUnit > 0) {
          await saveExchangeRate(currency, basePerUnit, source: 'automatic');
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

  /// Network state ke mutabiq conversion source select karta hai.
  static Future<bool> isOnline() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(const Duration(seconds: 4));
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Online Automatic rate; offline saved Manual currency-pair rate.
  static Future<double?> getEffectivePairRate(
    String fromCurrency,
    String toCurrency, {
    bool? online,
  }) async {
    final from = fromCurrency.trim().toUpperCase();
    final to = toCurrency.trim().toUpperCase();
    if (from.isEmpty || to.isEmpty) return null;
    if (from == to) return 1.0;
    final useAutomatic = online ?? await isOnline();
    if (!useAutomatic) return getManualPairRate(from, to);
    final fromRate = await getExchangeRate(from);
    final toRate = await getExchangeRate(to);
    if (fromRate == null || toRate == null || toRate <= 0) return null;
    final pairRate = fromRate / toRate;
    return pairRate.isFinite && pairRate > 0 ? pairRate : null;
  }

  static Future<double> getTotalBalanceInBaseCurrency() async {
    final baseCurrency = await getBaseCurrency();
    final online = await isOnline();
    final wallets = await _db.query('wallets', where: 'exclude_total = 0');
    double total = 0;
    for (final wallet in wallets) {
      final currency = (wallet['currency'] as String).toUpperCase();
      final balance = (wallet['balance'] as num).toDouble();
      final rate = await getEffectivePairRate(currency, baseCurrency, online: online);
      if (rate == null) {
        throw Exception('Manual/automatic rate for $currency → $baseCurrency is missing.');
      }
      total += balance * rate;
    }
    return total;
  }
}
