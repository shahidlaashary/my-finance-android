import 'dart:convert';
import 'dart:io';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/theme/app_colors.dart';

class ExchangeRatesScreen extends StatefulWidget {
  const ExchangeRatesScreen({super.key});

  @override
  State<ExchangeRatesScreen> createState() => _ExchangeRatesScreenState();
}

class _ExchangeRatesScreenState extends State<ExchangeRatesScreen> {
  static const List<String> _currencies = ['USD', 'GBP', 'EUR', 'AED', 'SAR', 'INR'];
  final FinanceDB _database = FinanceDB.instance;
  final NumberFormat _numberFormat = NumberFormat('#,##0.0000');
  List<Map<String, dynamic>> _rates = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _updating = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadData(autoUpdateIfStale: true);
  }

  Future<void> _loadData({bool autoUpdateIfStale = false}) async {
    try {
      final rates = await _database.getExchangeRates();
      final history = await _database.getExchangeRateHistory(limit: 30);
      if (!mounted) return;
      setState(() {
        _rates = rates;
        _history = history;
        _loading = false;
      });

      if (autoUpdateIfStale) {
        final now = DateTime.now();
        final isStale = _currencies.any((currency) {
          final matching = rates.where(
            (row) => row['currency'].toString().toUpperCase() == currency,
          );
          if (matching.isEmpty) return true;
          final updatedAt = DateTime.tryParse(
            matching.first['updated_at']?.toString() ?? '',
          );
          return updatedAt == null ||
              now.difference(updatedAt) >= const Duration(hours: 24);
        });
        if (isStale) await _refreshRates(showSuccess: false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Exchange rates load nahi ho sake: $error';
        _messageIsError = true;
      });
    }
  }

  double? _rateFor(String currency) {
    for (final row in _rates) {
      if (row['currency'].toString().toUpperCase() == currency) {
        return (row['rate'] as num).toDouble();
      }
    }
    return null;
  }

  Future<void> _refreshRates({bool showSuccess = true}) async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _message = null;
    });

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
      final rates = payload['rates'] as Map<String, dynamic>?;
      if (rates == null) throw const FormatException('Currency rates missing hain.');

      var saved = 0;
      for (final currency in _currencies) {
        final rawRate = rates[currency];
        if (rawRate is! num || rawRate <= 0) continue;
        // Provider PKR ke muqable mein foreign currency deta hai.
        // App ko 1 foreign currency ki PKR value chahiye.
        final pkrPerUnit = 1 / rawRate.toDouble();
        if (!pkrPerUnit.isFinite || pkrPerUnit <= 0) continue;
        await _database.saveExchangeRate(
          currency,
          pkrPerUnit,
          source: 'automatic',
        );
        saved++;
      }
      if (saved == 0) throw const FormatException('Koi supported rate receive nahi hua.');
      await _loadData();
      if (!mounted) return;
      setState(() {
        _message = showSuccess
            ? '$saved currency rates update ho gaye.'
            : 'Exchange rates automatically refresh ho gaye.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Automatic update nahi ho saka. Internet check karein. ($error)';
        _messageIsError = true;
      });
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _editRate(String currency) async {
    final controller = TextEditingController(
      text: _rateFor(currency)?.toString() ?? '',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('1 $currency ki PKR value'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'PKR exchange rate',
            hintText: 'e.g. 278.50',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || !parsed.isFinite || parsed <= 0) return;
              Navigator.pop(dialogContext, parsed);
            },
            child: Text(appText(context, 'Save', 'محفوظ کریں')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await _database.saveExchangeRate(currency, value);
      await _loadData();
      if (!mounted) return;
      setState(() {
        _message = '1 $currency = PKR ${_numberFormat.format(value)} save ho gaya.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Rate save nahi ho saka: $error';
        _messageIsError = true;
      });
    }
  }

  String _dateLabel(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Not updated';
    return DateFormat('dd MMM yyyy, hh:mm a').format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(appText(context, 'Exchange Rates', 'زرِ مبادلہ کی شرحیں'),
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Update rates',
            onPressed: _updating ? null : () => _refreshRates(),
            icon: _updating
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadData(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(appText(context, 'Base Currency: PKR', 'بنیادی کرنسی: PKR'),
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          SizedBox(height: 6),
                          const Text('Har rate 1 foreign currency unit ki PKR value hai.'),
                          SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _updating ? null : () => _refreshRates(),
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: Text(_updating ? 'Updating rates...' : 'Update Rates Online'),
                            ),
                          ),
                          SizedBox(height: 6),
                          const Text(
                            'Rates open.er-api.com se milte hain. Screen khulne par 24 ghantay se puranay rates auto-refresh hotay hain.',
                            style: TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_message != null) ...[
                    SizedBox(height: 8),
                    Material(
                      color: _messageIsError
                          ? Colors.red.withValues(alpha: 0.08)
                          : AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_message!,
                            style: TextStyle(
                              color: _messageIsError ? Colors.red.shade700 : AppColors.primary,
                            )),
                      ),
                    ),
                  ],
                  SizedBox(height: 18),
                  Text(appText(context, 'Current Rates', 'موجودہ شرحیں'),
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(child: Text('PKR')),
                          title: Text(appText(context, 'Pakistani Rupee', 'پاکستانی روپیہ'),
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('Base currency'),
                          trailing: const Text('1.0000 PKR',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        const Divider(height: 1),
                        for (final currency in _currencies)
                          Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                                  child: Text(currency,
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                                ),
                                title: Text('1 $currency',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(_rateFor(currency) == null
                                    ? 'Rate not set'
                                    : 'Updated: ${_dateLabel(_rates.firstWhere((r) => r['currency'].toString().toUpperCase() == currency)['updated_at'])}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _rateFor(currency) == null
                                          ? '—'
                                          : 'PKR ${_numberFormat.format(_rateFor(currency)!)}',
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit rate',
                                      onPressed: () => _editRate(currency),
                                      icon: const Icon(Icons.edit_outlined, size: 19),
                                    ),
                                  ],
                                ),
                              ),
                              if (currency != _currencies.last) const Divider(height: 1),
                            ],
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(appText(context, 'Rate History', 'شرحوں کی تاریخ'),
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  if (_history.isEmpty)
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Abhi rate history available nahi. Rate save ya online update karein.'),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < _history.length; i++) ...[
                            ListTile(
                              dense: true,
                              title: Text(
                                '1 ${_history[i]['currency']} = PKR ${_numberFormat.format((_history[i]['rate'] as num).toDouble())}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                '${_dateLabel(_history[i]['recorded_at'])} • ${_history[i]['source'] == 'automatic' ? 'Online update' : _history[i]['source'] == 'migration' ? 'Existing rate' : 'Manual update'}',
                              ),
                            ),
                            if (i != _history.length - 1) const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
