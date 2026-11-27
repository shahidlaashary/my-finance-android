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
    if (direct.isNotEmpty) {
      final rate = (direct.first['rate'] as num).toDouble();
      return rate.isFinite && rate > 0 ? rate : null;
    }
    final graph = <String, List<MapEntry<String, double>>>{};
    for (final pair in _manualPairs) {
      final a = pair['from_currency'].toString();
      final b = pair['to_currency'].toString();
      final rate = (pair['rate'] as num).toDouble();
      if (!rate.isFinite || rate <= 0) continue;
      graph.putIfAbsent(a, () => []).add(MapEntry(b, rate));
      graph.putIfAbsent(b, () => []).add(MapEntry(a, 1 / rate));
    }
    final queue = <(String, double)>[(from, 1.0)];
    final visited = <String>{from};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final edge in graph[current.$1] ?? const <MapEntry<String, double>>[]) {
        if (!visited.add(edge.key)) continue;
        final combined = current.$2 * edge.value;
        if (!combined.isFinite || combined <= 0) continue;
        if (edge.key == to) return combined;
        queue.add((edge.key, combined));
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

  Future<void> _addManualPair([Map<String, dynamic>? existing]) async {
    String from = existing?['from_currency']?.toString() ?? 'USD';
    String to = existing?['to_currency']?.toString() ?? 'PKR';
    final rateController = TextEditingController(
      text: existing == null ? '' : (existing['rate'] as num).toString(),
    );
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Manual Currency Pair' : 'Edit Manual Currency Pair'),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.hintColor;
    final converted = _convertedAmount;
    final resultText = converted == null
        ? 'Rate unavailable'
        : NumberFormat('#,##0.####').format(converted);

    InputDecoration compactDecoration(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
        );

    Widget currencyDropdown(String label, String value,
        ValueChanged<String?> onChanged) {
      return DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        isDense: true,
        decoration: compactDecoration(label),
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: theme.textTheme.bodyLarge?.color),
        items: CurrencyCatalog.supported
            .map((code) => DropdownMenuItem(
                  value: code,
                  child: Text(code, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: onChanged,
      );
    }

    Widget columnHeader(String title, String subtitle, IconData icon,
        {Widget? action}) {
      return Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: colors.primary),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 8, color: muted)),
              ],
            ),
          ),
          if (action != null) action,
        ],
      );
    }

    Widget automaticColumn() {
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              columnHeader('Automatic', 'Rates in $_baseCurrency',
                  Icons.cloud_sync_rounded),
              const SizedBox(height: 8),
              Divider(height: 1, color: theme.dividerColor),
              const SizedBox(height: 3),
              for (final currency in _currencies)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(currency,
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                            if (_rateFor(currency) != null)
                              Text(
                                _dateLabel(_rates.firstWhere((r) =>
                                    r['currency']
                                        .toString()
                                        .toUpperCase() ==
                                    currency)['updated_at']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 7, color: muted),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          _rateFor(currency) == null
                              ? '—'
                              : _numberFormat.format(_rateFor(currency)),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _rateFor(currency) == null
                                ? muted
                                : colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Widget manualColumn() {
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              columnHeader(
                'Manual',
                'Saved currency pairs',
                Icons.tune_rounded,
                action: IconButton(
                  tooltip: 'Add currency pair',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: _addManualPair,
                  icon: Icon(Icons.add_circle_rounded,
                      size: 18, color: colors.primary),
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: theme.dividerColor),
              const SizedBox(height: 3),
              if (_manualPairs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.swap_horiz_rounded,
                            size: 21, color: muted),
                        const SizedBox(height: 5),
                        Text('No pairs added',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 8, color: muted)),
                      ],
                    ),
                  ),
                ),
              for (final pair in _manualPairs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${pair['from_currency']} → ${pair['to_currency']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _numberFormat.format(
                                  (pair['rate'] as num).toDouble()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 9,
                                  color: colors.primary,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit pair',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 23, minHeight: 23),
                        onPressed: () => _addManualPair(pair),
                        icon: Icon(Icons.edit_outlined,
                            size: 13, color: muted),
                      ),
                      IconButton(
                        tooltip: 'Delete pair',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 23, minHeight: 23),
                        onPressed: () =>
                            _removeManualPair(pair['id'] as int),
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 13, color: muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          appText(context, 'Exchange Rates', 'زرِ مبادلہ کی شرحیں'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Update rates',
            onPressed: _updating ? null : () => _refreshRates(),
            icon: _updating
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadData(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.currency_exchange_rounded,
                                  size: 18, color: colors.primary),
                              const SizedBox(width: 7),
                              const Expanded(
                                child: Text('Currency Converter',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (_online
                                          ? Colors.green
                                          : Colors.orange)
                                      .withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _online ? 'ONLINE' : 'OFFLINE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    letterSpacing: .3,
                                    fontWeight: FontWeight.w800,
                                    color: _online
                                        ? Colors.green.shade700
                                        : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  controller: _convertAmount,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800),
                                  decoration: compactDecoration('Amount'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: colors.primaryContainer
                                        .withValues(alpha: .48),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('YOU RECEIVE',
                                          style: TextStyle(
                                              fontSize: 8,
                                              letterSpacing: .6,
                                              fontWeight: FontWeight.w800,
                                              color: muted)),
                                      const SizedBox(height: 3),
                                      Text(
                                        resultText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: converted == null
                                              ? muted
                                              : colors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              Expanded(
                                child: currencyDropdown(
                                  'From',
                                  _convertFrom,
                                  (value) {
                                    if (value != null) {
                                      setState(() => _convertFrom = value);
                                    }
                                  },
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                child: IconButton.filledTonal(
                                  tooltip: 'Swap currencies',
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                      minWidth: 34, minHeight: 34),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => setState(() {
                                    final previous = _convertFrom;
                                    _convertFrom = _convertTo;
                                    _convertTo = previous;
                                  }),
                                  icon: const Icon(
                                      Icons.swap_horiz_rounded,
                                      size: 19),
                                ),
                              ),
                              Expanded(
                                child: currencyDropdown(
                                  'To',
                                  _convertTo,
                                  (value) {
                                    if (value != null) {
                                      setState(() => _convertTo = value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _online
                                ? 'Using saved automatic rates'
                                : 'Using saved manual currency-pair rates',
                            style: TextStyle(fontSize: 9, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 9),
                    Material(
                      color: _messageIsError
                          ? Colors.red.withValues(alpha: .08)
                          : colors.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            fontSize: 11,
                            color: _messageIsError
                                ? Colors.red.shade700
                                : colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Rate Sources',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900)),
                        ),
                        Text('Base: $_baseCurrency',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: muted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: automaticColumn()),
                      const SizedBox(width: 8),
                      Expanded(child: manualColumn()),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
