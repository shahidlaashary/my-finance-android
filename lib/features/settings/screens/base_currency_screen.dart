import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/modules/finance/services/currency_service.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';

/// App ki base currency aur exchange rates select karne ki screen.
class BaseCurrencyScreen extends StatefulWidget {
  const BaseCurrencyScreen({super.key});

  @override
  State<BaseCurrencyScreen> createState() => _BaseCurrencyScreenState();
}

class _BaseCurrencyScreenState extends State<BaseCurrencyScreen> {
  bool _loading = true;
  bool _saving = false;
  String _selected = 'PKR';
  String _referenceCurrency = 'PKR';
  // Live PKR-based rate provider ki taraf se supported international currencies.
  static const List<String> _available = CurrencyCatalog.supported;
  Map<String, double> _rates = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Base currency ko rates se alag load karein. Dono queries ko Future.wait
    // mein rakhne se aik slow query poori screen ka spinner roke rakhti thi.
    String selected = 'PKR';
    try {
      selected = await CurrencyService.getBaseCurrency()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline/slow database read ki surat mein screen phir bhi open hogi.
    }

    if (!mounted) return;
    setState(() {
      _selected = _available.contains(selected) ? selected : 'PKR';
      _referenceCurrency = _selected;
      _loading = false;
    });

    // Cached rates optional hain: unki query screen render hone ke baad chale.
    try {
      final rows = await CurrencyService.getExchangeRates()
          .timeout(const Duration(seconds: 5));
      final rates = _parseRates(rows);
      final now = DateTime.now();
      final needsRefresh = _available
          .where((code) => code != _referenceCurrency)
          .any((code) {
        final row = rows.where(
          (item) => item['currency'].toString().toUpperCase() == code,
        );
        if (row.isEmpty) return true;
        final updatedAt =
            DateTime.tryParse(row.first['updated_at']?.toString() ?? '');
        return updatedAt == null ||
            now.difference(updatedAt) >= const Duration(hours: 24);
      });

      if (!mounted) return;
      setState(() => _rates = rates);

      if (needsRefresh) {
        _refreshRatesInBackground();
      }
    } catch (_) {
      // Rates read fail ho to bhi currency picker aur page usable rehte hain.
    }
  }

  Future<void> _refreshRatesInBackground() async {
    try {
      await _refreshRatesOnline().timeout(const Duration(seconds: 15));
      final rows = await CurrencyService.getExchangeRates();
      if (!mounted) return;
      setState(() => _rates = _parseRates(rows));
    } catch (_) {
      // Offline honay par cached/local rates available rehte hain.
      // Network failure ki wajah se Base Currency screen block nahi hoti.
    }
  }

  static const Map<String, String> _currencyFlags = {
    'PKR': '🇵🇰', 'USD': '🇺🇸', 'GBP': '🇬🇧', 'EUR': '🇪🇺',
    'AED': '🇦🇪', 'SAR': '🇸🇦', 'INR': '🇮🇳', 'CAD': '🇨🇦',
    'AUD': '🇦🇺', 'JPY': '🇯🇵', 'CNY': '🇨🇳', 'CHF': '🇨🇭',
    'SGD': '🇸🇬', 'NZD': '🇳🇿', 'KWD': '🇰🇼', 'QAR': '🇶🇦',
    'BHD': '🇧🇭', 'OMR': '🇴🇲', 'MYR': '🇲🇾', 'TRY': '🇹🇷',
    'ZAR': '🇿🇦', 'HKD': '🇭🇰', 'IDR': '🇮🇩', 'KRW': '🇰🇷',
    'THB': '🇹🇭',
  };

  static const Map<String, String> _currencyCountries = {
    'PKR': 'Pakistani Rupee', 'USD': 'US Dollar', 'GBP': 'British Pound',
    'EUR': 'Euro', 'AED': 'UAE Dirham', 'SAR': 'Saudi Riyal',
    'INR': 'Indian Rupee', 'CAD': 'Canadian Dollar', 'AUD': 'Australian Dollar',
    'JPY': 'Japanese Yen', 'CNY': 'Chinese Yuan', 'CHF': 'Swiss Franc',
    'SGD': 'Singapore Dollar', 'NZD': 'New Zealand Dollar',
    'KWD': 'Kuwaiti Dinar', 'QAR': 'Qatari Riyal', 'BHD': 'Bahraini Dinar',
    'OMR': 'Omani Rial', 'MYR': 'Malaysian Ringgit', 'TRY': 'Turkish Lira',
    'ZAR': 'South African Rand', 'HKD': 'Hong Kong Dollar',
    'IDR': 'Indonesian Rupiah', 'KRW': 'South Korean Won',
    'THB': 'Thai Baht',
  };

  Map<String, double> _parseRates(List<Map<String, dynamic>> rows) {
    final rates = <String, double>{};
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

      final currentBase = await CurrencyService.getBaseCurrency();
      final baseProviderRate =
          currentBase == 'PKR' ? 1.0 : latestRates[currentBase];
      if (baseProviderRate is! num || baseProviderRate <= 0) {
        throw const FormatException('Selected Base Currency ka rate missing hai.');
      }
      for (final currency in _available.where((code) => code != currentBase)) {
        final rawRate = latestRates[currency];
        if (rawRate is! num || rawRate <= 0) continue;
        // Provider PKR reference deta hai; app ki current Base Currency mein save karein.
        final basePerUnit = baseProviderRate.toDouble() / rawRate.toDouble();
        if (basePerUnit.isFinite && basePerUnit > 0) {
          await CurrencyService.saveExchangeRate(
            currency,
            basePerUnit,
            source: 'automatic',
          );
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _showCurrencyPicker() async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = _available.where((code) {
              final name = _currencyCountries[code] ?? code;
              final search = query.trim().toLowerCase();
              return search.isEmpty || code.toLowerCase().contains(search) ||
                  name.toLowerCase().contains(search);
            }).toList()
              ..sort((a, b) => (_currencyCountries[a] ?? a)
                  .compareTo(_currencyCountries[b] ?? b));
            return Padding(
              padding: EdgeInsets.only(
                left: 18, right: 18, top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(
                      width: 38, height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    )),
                    const SizedBox(height: 18),
                    Text(appText(context, 'Choose base currency', 'بنیادی کرنسی منتخب کریں'),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(appText(context, 'Search by currency name or code', 'کرنسی کے نام یا کوڈ سے تلاش کریں'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    TextField(
                      autofocus: true,
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: InputDecoration(
                        hintText: appText(context, 'Search currencies...', 'کرنسیاں تلاش کریں...'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(vertical: 9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: ListView.separated(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final code = filtered[index];
                        final selected = code == _selected;
                        final rate = _rates[code];
                        final enabled = code == _referenceCurrency || rate != null;
                        return Material(
                          color: selected
                              ? theme.colorScheme.primaryContainer.withOpacity(0.65)
                              : theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(15),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(15),
                            onTap: enabled ? () => Navigator.pop(sheetContext, code) : null,
                            child: Opacity(
                              opacity: enabled ? 1 : 0.45,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(children: [
                                  Text(_currencyFlags[code] ?? '🌐',
                                    style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 13),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(code, style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800)),
                                      Text(_currencyCountries[code] ?? code,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant)),
                                    ],
                                  )),
                                  if (code != _referenceCurrency && rate != null)
                                    Text('$_referenceCurrency ${NumberFormat('#,##0.0000').format(rate)}',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant)),
                                  if (selected) ...[
                                    const SizedBox(width: 8),
                                    Icon(Icons.check_circle_rounded,
                                      color: theme.colorScheme.primary),
                                  ] else if (!enabled)
                                    const Icon(Icons.cloud_off_rounded, size: 18),
                                ]),
                              ),
                            ),
                          ),
                        );
                      },
                    )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked != null && mounted) setState(() => _selected = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CurrencyService.setBaseCurrency(_selected);
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
        title: Text(appText(context, 'Base Currency', 'بنیادی کرنسی'),
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
                        Text(appText(context, 'Choose your main currency', 'اپنی بنیادی کرنسی منتخب کریں'),
                            style: TextStyle(fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(appText(context, "Dashboard totals and consolidated wallet values will be shown in this currency. Existing wallet currencies and records will not be changed.", "Dashboard totals and consolidated wallet values will be shown in this currency. Existing wallet currencies and records will not be changed."),
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
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _saving ? null : _showCurrencyPicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                      child: Row(children: [
                        Text(_currencyFlags[_selected] ?? '🌐',
                          style: const TextStyle(fontSize: 31)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selected, style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(_currencyCountries[_selected] ?? _selected,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 12)),
                          ],
                        )),
                        const Icon(Icons.unfold_more_rounded),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving || (_selected != 'PKR' && !_rates.containsKey(_selected)) ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(appText(context, 'Save Base Currency', 'بنیادی کرنسی محفوظ کریں')),
                  ),
                ),
                if (_rates.length < _available.length)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(appText(context, "Kuch rates abhi available nahi. Internet connect karke screen dobara kholein.", "Kuch rates abhi available nahi. Internet connect karke screen dobara kholein."),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }
}
