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
  List<Map<String, dynamic>> _manualPairs = [];
  bool _online = true;
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

  double? _manualRateFor(String from, String to) {
    if (from == to) return 1.0;
    final direct = _manualPairs.where((row) =>
        row['from_currency'] == from && row['to_currency'] == to);
    if (direct.isNotEmpty) return (direct.first['rate'] as num).toDouble();
    final reverse = _manualPairs.where((row) =>
        row['from_currency'] == to && row['to_currency'] == from);
    if (reverse.isNotEmpty) {
      final rate = (reverse.first['rate'] as num).toDouble();
      return rate > 0 ? 1 / rate : null;
    }
    // Direct/reverse pair na ho to shared currency ke zariye cross-rate.
    for (final pair in _manualPairs) {
      final pivot = pair['to_currency']?.toString() ?? '';
      if (pair['from_currency'] == from && pivot.isNotEmpty) {
        final onward = _manualPairs.where((row) =>
            row['from_currency'] == pivot && row['to_currency'] == to);
        if (onward.isNotEmpty) {
          return (pair['rate'] as num).toDouble() *
              (onward.first['rate'] as num).toDouble();
        }
      }
    }
    return null;
  }

  double? get _convertedAmount {
    final amount = double.tryParse(_convertAmount.text.trim());
    if (amount == null || !amount.isFinite || amount < 0) return null;
    if (!_online) {
      final rate = _manualRateFor(_convertFrom, _convertTo);
      return rate == null ? null : amount * rate;
    }
    final fromRate = _rateFor(_convertFrom);
    final toRate = _rateFor(_convertTo);
    if (fromRate == null || toRate == null || toRate <= 0) return null;
    return amount * fromRate / toRate;
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _addManualPair() async {
    String from = 'USD';
    String to = 'PKR';
    final rateController = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Manual Currency Pair'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: from,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'From currency'),
                items: CurrencyCatalog.supported.map((code) =>
                    DropdownMenuItem(value: code, child: Text(code))).toList(),
                onChanged: (value) => setDialogState(() => from = value ?? from),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: to,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'To currency'),
                items: CurrencyCatalog.supported.map((code) =>
                    DropdownMenuItem(value: code, child: Text(code))).toList(),
                onChanged: (value) => setDialogState(() => to = value ?? to),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: rateController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Exchange rate'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final rate = double.tryParse(rateController.text.trim());
                if (from == to || rate == null || !rate.isFinite || rate <= 0) return;
                Navigator.pop(dialogContext, {'from': from, 'to': to, 'rate': rate});
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    rateController.dispose();
    if (result == null) return;
    await CurrencyService.saveManualCurrencyPair(
        result['from'] as String, result['to'] as String, result['rate'] as double);
    await _loadData();
  }

  Future<void> _removeManualPair(int id) async {
    await CurrencyService.deleteManualCurrencyPair(id);
    await _loadData();
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
        CurrencyService.getManualCurrencyPairs(),
        _hasInternet(),
      ]);
      final rates = results[0] as List<Map<String, dynamic>>;
      final baseCurrency = results[1] as String;
      final manualPairs = results[2] as List<Map<String, dynamic>>;
      final online = results[3] as bool;
      if (!mounted) return;
      setState(() {
        _baseCurrency = baseCurrency;
        _convertTo = baseCurrency;
        _rates = rates;
        _manualPairs = manualPairs;
        _online = online;
        _loading = false;
      });

      if (autoUpdateIfStale && online) {
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
          decoration: InputDecoration(
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
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.currency_exchange_rounded, size: 19,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              const Text('Currency Converter',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (_online ? Colors.green : Colors.orange).withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(_online ? 'Automatic' : 'Manual • Offline',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                      color: _online ? Colors.green.shade700 : Colors.orange.shade800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _convertAmount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            decoration: InputDecoration(
                              labelText: 'Amount',
                              prefixIcon: const Icon(Icons.payments_outlined, size: 19),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: DropdownButtonFormField<String>(
                                value: _convertFrom,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'From',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                items: CurrencyCatalog.supported.map((code) =>
                                  DropdownMenuItem(value: code, child: Text(code,
                                    style: const TextStyle(fontWeight: FontWeight.w700)))).toList(),
                                onChanged: (value) { if (value != null) setState(() => _convertFrom = value); },
                              )),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 7),
                                child: IconButton.filledTonal(
                                  tooltip: 'Swap currencies',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() {
                                    final oldFrom = _convertFrom;
                                    _convertFrom = _convertTo;
                                    _convertTo = oldFrom;
                                  }),
                                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                                ),
                              ),
                              Expanded(child: DropdownButtonFormField<String>(
                                value: _convertTo,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'To',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
                                ),
                                items: CurrencyCatalog.supported.map((code) =>
                                  DropdownMenuItem(value: code, child: Text(code,
                                    style: const TextStyle(fontWeight: FontWeight.w700)))).toList(),
                                onChanged: (value) { if (value != null) setState(() => _convertTo = value); },
                              )),
                            ],
                          ),
                          const SizedBox(height: 11),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .72),
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .28),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .12)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('CONVERTED AMOUNT',
                                  style: TextStyle(fontSize: 9, letterSpacing: .8,
                                    fontWeight: FontWeight.w800, color: Theme.of(context).hintColor)),
                                const SizedBox(height: 4),
                                Text(
                                  _convertedAmount == null
                                      ? 'Rate unavailable'
                                      : _convertTo + '  ' + NumberFormat('#,##0.####').format(_convertedAmount),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900,
                                    color: _convertedAmount == null
                                      ? Theme.of(context).hintColor
                                      : Theme.of(context).colorScheme.primary),
                                ),
                                const SizedBox(height: 3),
                                Text(_online
                                    ? 'Live saved automatic rate'
                                    : 'Saved manual currency-pair rate',
                                  style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  Text('Exchange Rate Sources',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(9, 10, 9, 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('Automatic', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                              Icon(Icons.cloud_sync_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                            ]),
                            const SizedBox(height: 3),
                            Text('1 currency → $_baseCurrency', style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor)),
                            const Divider(height: 14),
                            for (final currency in _currencies)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(currency, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(_rateFor(currency) == null ? 'Not available' : _numberFormat.format(_rateFor(currency)) + ' $_baseCurrency',
                                    maxLines: 2, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                                  if (_rateFor(currency) != null)
                                    Text(_dateLabel(_rates.firstWhere((r) => r['currency'].toString().toUpperCase() == currency)['updated_at']),
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8, color: Theme.of(context).hintColor)),
                                ]),
                              ),
                          ]),
                        ),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(9, 10, 9, 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('Manual', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                              IconButton(
                                tooltip: 'Add currency pair',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: _addManualPair,
                                icon: Icon(Icons.add_circle_outline_rounded, size: 19, color: Theme.of(context).colorScheme.primary),
                              ),
                            ]),
                            Text('Independent pairs', style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor)),
                            const Divider(height: 14),
                            if (_manualPairs.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text('No manual pairs yet', style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
                              ),
                            for (final pair in _manualPairs)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('\${pair['from_currency']} → \${pair['to_currency']}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 3),
                                    Text(_numberFormat.format((pair['rate'] as num).toDouble()),
                                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                                  ])),
                                  IconButton(
                                    tooltip: 'Delete pair',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    onPressed: () => _removeManualPair(pair['id'] as int),
                                    icon: Icon(Icons.close_rounded, size: 15, color: Theme.of(context).hintColor),
                                  ),
                                ]),
                              ),
                          ]),
                        ),
                      )),
                    ],
                  ),

                ],
              ),
            ),
    );
  }
}
