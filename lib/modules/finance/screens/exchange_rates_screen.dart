import 'dart:convert';
import 'dart:io';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/modules/finance/services/currency_service.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';

/// Supported currencies ke exchange rates dekhne aur update karne ki screen.
class ExchangeRatesScreen extends StatefulWidget {
  const ExchangeRatesScreen({super.key});

  @override
  State<ExchangeRatesScreen> createState() => _ExchangeRatesScreenState();
}

class _ExchangeRatesScreenState extends State<ExchangeRatesScreen> {
  List<String> get _currencies => CurrencyCatalog.supported.where((code) => code != _baseCurrency).toList();
  String _baseCurrency = 'PKR';
  final NumberFormat _numberFormat = NumberFormat('#,##0.0000');
  List<Map<String, dynamic>> _rates = [];
  bool _loading = true;
  bool _updating = false;
  String? _message;
  bool _messageIsError = false;
  final TextEditingController _convertAmount = TextEditingController(text: '1');
  String _convertFrom = 'USD';
  String _convertTo = 'PKR';

  @override
  void dispose() {
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    _convertAmount.dispose();
    super.dispose();
  }

  double? get _convertedAmount {
    final amount = double.tryParse(_convertAmount.text.trim());
    final fromRate = _rateFor(_convertFrom);
    final toRate = _rateFor(_convertTo);
    if (amount == null || !amount.isFinite || amount < 0 ||
        fromRate == null || toRate == null || toRate <= 0) return null;
    return amount * fromRate / toRate;
  }

  @override
  void initState() {
    super.initState();
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _loadData(autoUpdateIfStale: true);
  }

  void _onAppDataChanged() {
    if (mounted) _loadData();
  }

  Future<void> _loadData({bool autoUpdateIfStale = false}) async {
    try {
      final results = await Future.wait([
        CurrencyService.getExchangeRates(),
        CurrencyService.getBaseCurrency(),
      ]);
      final rates = results[0] as List<Map<String, dynamic>>;
      final baseCurrency = results[1] as String;
      if (!mounted) return;
      setState(() {
        _baseCurrency = baseCurrency;
        _rates = rates;
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
    if (currency == _baseCurrency) return 1.0;
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
      final baseCurrency = await CurrencyService.getBaseCurrency();
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

      final baseProviderRate = baseCurrency == 'PKR' ? 1.0 : rates[baseCurrency];
      if (baseProviderRate is! num || baseProviderRate <= 0) {
        throw const FormatException('Selected Base Currency ka rate missing hai.');
      }
      var saved = 0;
      for (final currency in _currencies) {
        final rawRate = rates[currency];
        if (rawRate is! num || rawRate <= 0) continue;
        // Provider PKR reference deta hai; app ke selected Base Currency mein convert karein.
        final basePerUnit = baseProviderRate.toDouble() / rawRate.toDouble();
        if (!basePerUnit.isFinite || basePerUnit <= 0) continue;
        await CurrencyService.saveExchangeRate(
          currency,
          basePerUnit,
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
        title: Text('1 $currency ki $_baseCurrency value'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '$_baseCurrency exchange rate',
            hintText: 'Enter rate in $_baseCurrency',
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
      await CurrencyService.saveExchangeRate(currency, value);
      await _loadData();
      if (!mounted) return;
      setState(() {
        _message = '1 $currency = $_baseCurrency ${_numberFormat.format(value)} save ho gaya.';
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                : Icon(Icons.sync_rounded),
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
                          Text('Currency Converter',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          SizedBox(height: 12),
                          TextField(
                            controller: _convertAmount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
                            onChanged: (_) => setState(() {}),
                          ),
                          SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: DropdownButtonFormField<String>(
                              value: _convertFrom,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'From'),
                              items: CurrencyCatalog.supported.map((code) =>
                                DropdownMenuItem(value: code, child: Text(code))).toList(),
                              onChanged: (value) => setState(() => _convertFrom = value ?? _baseCurrency),
                            )),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.swap_horiz_rounded)),
                            Expanded(child: DropdownButtonFormField<String>(
                              value: _convertTo,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'To'),
                              items: CurrencyCatalog.supported.map((code) =>
                                DropdownMenuItem(value: code, child: Text(code))).toList(),
                              onChanged: (value) => setState(() => _convertTo = value ?? _baseCurrency),
                            )),
                          ]),
                          SizedBox(height: 12),
                          Text(
                            _convertedAmount == null
                                ? 'Rate unavailable. Update exchange rates first.'
                                : _convertTo + ' ' + NumberFormat('#,##0.####').format(_convertedAmount),
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                              color: _convertedAmount == null ? Theme.of(context).hintColor : Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(height: 4),
                          Text('Rates are shown relative to $_baseCurrency.',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  if (_message != null) ...[
                    SizedBox(height: 8),
                    Material(
                      color: _messageIsError
                          ? Colors.red.withValues(alpha: 0.08)
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_message!,
                            style: TextStyle(
                              color: _messageIsError ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
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
                          leading: CircleAvatar(child: Text(_baseCurrency)),
                          title: Text('$_baseCurrency',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('Base currency'),
                          trailing: Text('1.0000 $_baseCurrency',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        const Divider(height: 1),
                        for (final currency in _currencies)
                          Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                                  child: Text(currency,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                                ),
                                title: Text('1 $currency',
                                    style: TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(_rateFor(currency) == null
                                    ? 'Rate not set'
                                    : 'Updated: ${_dateLabel(_rates.firstWhere((r) => r['currency'].toString().toUpperCase() == currency)['updated_at'])}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _rateFor(currency) == null
                                          ? '—'
                                          : '$_baseCurrency ${_numberFormat.format(_rateFor(currency)!)}',
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit rate',
                                      onPressed: () => _editRate(currency),
                                      icon: Icon(Icons.edit_outlined, size: 19),
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

                ],
              ),
            ),
    );
  }
}
