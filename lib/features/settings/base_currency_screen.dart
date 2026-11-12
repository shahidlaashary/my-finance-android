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
  List<String> _available = ['PKR'];
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
      final rows = values[1] as List<Map<String, dynamic>>;
      final rates = <String, double>{'PKR': 1};
      for (final row in rows) {
        final code = row['currency'].toString().toUpperCase();
        final rate = (row['rate'] as num).toDouble();
        if (rate.isFinite && rate > 0) rates[code] = rate;
      }
      if (!mounted) return;
      setState(() {
        _selected = selected;
        _rates = rates;
        _available = rates.keys.toList()..sort();
        if (!_available.contains(_selected)) _selected = 'PKR';
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
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _selected = value!),
                        title: Text(currency,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(currency == 'PKR'
                            ? 'Pakistani Rupee • Default'
                            : '1 $currency = PKR ${NumberFormat('#,##0.0000').format(rate)}'),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving || _selected == '' ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Saving...' : 'Save Base Currency'),
                  ),
                ),
                if (_available.length == 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'More currencies will appear after exchange rates are added or updated.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }
}
