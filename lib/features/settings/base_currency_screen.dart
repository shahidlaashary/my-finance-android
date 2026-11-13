import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/database/finance_database.dart';

class BaseCurrencyScreen extends StatefulWidget {
  const BaseCurrencyScreen({super.key});

  @override
  State<BaseCurrencyScreen> createState() => _BaseCurrencyScreenState();
}

class _BaseCurrencyScreenState extends State<BaseCurrencyScreen> {
  final FinanceDB _database = FinanceDB.instance;
  bool _loading = true;
  bool _saving = false;
  String _selected = 'PKR';
  static const List<String> _available = ['PKR', 'USD', 'GBP', 'EUR', 'AED', 'SAR', 'INR'];
  Map<String, double> _rates = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _database.getBaseCurrency(),
        _database.getExchangeRates(),
      ]);
      final selected = values[0] as String;
      var rows = values[1] as List<Map<String, dynamic>>;
      var rates = _parseRates(rows);

      // Missing ya 24 ghantay se puranay rates ko online refresh karein.
      final now = DateTime.now();
      final needsRefresh = _available.where((code) => code != 'PKR').any((code) {
        final row = rows.where(
          (item) => item['currency'].toString().toUpperCase() == code,
        );
        if (row.isEmpty) return true;
        final updatedAt = DateTime.tryParse(row.first['updated_at']?.toString() ?? '');
        return updatedAt == null ||
            now.difference(updatedAt) >= const Duration(hours: 24);
      });
      if (needsRefresh) {
        try {
          await _refreshRatesOnline();
          rows = await _database.getExchangeRates();
          rates = _parseRates(rows);
        } catch (_) {
          // Offline honay par pehle se saved rates available rehte hain.
        }
      }

      if (!mounted) return;
      setState(() {
        _selected = selected;
        _rates = rates;
        if (!_available.contains(_selected) ||
            (_selected != 'PKR' && !_rates.containsKey(_selected))) {
          _selected = 'PKR';
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Base currency load nahi ho saki: $error')),
      );
    }
  }

  Map<String, double> _parseRates(List<Map<String, dynamic>> rows) {
    final rates = <String, double>{'PKR': 1};
    for (final row in rows) {
      final code = row['currency'].toString().toUpperCase();
      final rawRate = row['rate'];
      if (rawRate is num) {
        final rate = rawRate.toDouble();
        if (rate.isFinite && rate > 0) rates[code] = rate;
      }
    }
    return rates;
  }

  Future<void> _refreshRatesOnline() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .getUrl(Uri.parse('https://open.er-api.com/v6/latest/PKR'))
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Rate provider returned HTTP ${response.statusCode}.');
      }
      final body = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 20));
      final payload = jsonDecode(body) as Map<String, dynamic>;
      if (payload['result'] != 'success') {
        throw const FormatException('Rate provider response invalid hai.');
      }
      final latestRates = payload['rates'] as Map<String, dynamic>?;
      if (latestRates == null) {
        throw const FormatException('Currency rates missing hain.');
      }

      for (final currency in _available.where((code) => code != 'PKR')) {
        final rawRate = latestRates[currency];
        if (rawRate is! num || rawRate <= 0) continue;
        // Provider 1 PKR ki foreign currency value deta hai;
        // app ko 1 foreign currency ki PKR value chahiye.
        final pkrPerUnit = 1 / rawRate.toDouble();
        if (pkrPerUnit.isFinite && pkrPerUnit > 0) {
          await _database.saveExchangeRate(
            currency,
            pkrPerUnit,
            source: 'automatic',
          );
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _database.setBaseCurrency(_selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Base currency $_selected set ho gayi.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Currency save nahi ho saki: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Base Currency',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Choose your main currency',
                            style: TextStyle(fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 6),
                        const Text(
                          'Dashboard totals and consolidated wallet values will be shown in this currency. Existing wallet currencies and records will not be changed.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text('Selected: $_selected',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: _available.map((currency) {
                      final rate = _rates[currency] ?? 1;
                      return RadioListTile<String>(
                        value: currency,
                        groupValue: _selected,
                        onChanged: _saving || (currency != 'PKR' && !_rates.containsKey(currency))
                            ? null
                            : (value) => setState(() => _selected = value!),
                        title: Text(currency,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(currency == 'PKR'
                            ? 'Pakistani Rupee • Default'
                            : _rates.containsKey(currency)
                                ? '1 $currency = PKR ${NumberFormat('#,##0.0000').format(rate)}'
                                : 'Rate unavailable • Internet se update karein'),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving || (_selected != 'PKR' && !_rates.containsKey(_selected)) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Saving...' : 'Save Base Currency'),
                  ),
                ),
                if (_rates.length < _available.length)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Kuch rates abhi available nahi. Internet connect karke screen dobara kholein.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }
}
