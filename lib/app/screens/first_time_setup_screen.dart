import 'package:my_finance/core/database/database_manager.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:my_finance/app/screens/main_screen.dart';

/// First-install setup for the user's name and preferred base currency.
class FirstTimeSetupScreen extends StatefulWidget {
  const FirstTimeSetupScreen({super.key});

  @override
  State<FirstTimeSetupScreen> createState() => _FirstTimeSetupScreenState();
}

class _FirstTimeSetupScreenState extends State<FirstTimeSetupScreen> {
  final _nameController = TextEditingController();
  String _currency = 'PKR';
  bool _saving = false;

  static const _completedKey = 'first_time_setup_completed';
  List<String> get currencies => CurrencyCatalog.supported.toList()..sort();
  static const _currencyNames = <String, String>{
    'PKR': 'Pakistani Rupee', 'USD': 'US Dollar', 'GBP': 'British Pound',
    'EUR': 'Euro', 'AED': 'UAE Dirham', 'SAR': 'Saudi Riyal',
    'INR': 'Indian Rupee', 'CAD': 'Canadian Dollar', 'AUD': 'Australian Dollar',
    'JPY': 'Japanese Yen', 'CNY': 'Chinese Yuan', 'CHF': 'Swiss Franc',
    'SGD': 'Singapore Dollar', 'NZD': 'New Zealand Dollar',
    'KWD': 'Kuwaiti Dinar', 'QAR': 'Qatari Riyal', 'BHD': 'Bahraini Dinar',
    'OMR': 'Omani Rial', 'MYR': 'Malaysian Ringgit', 'TRY': 'Turkish Lira',
    'ZAR': 'South African Rand', 'HKD': 'Hong Kong Dollar',
    'IDR': 'Indonesian Rupiah', 'KRW': 'South Korean Won', 'THB': 'Thai Baht',
  };

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Shahzain Khan';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _refreshSelectedRate() async {
    if (_currency == 'PKR') return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(
        Uri.parse('https://open.er-api.com/v6/latest/PKR'),
      ).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Exchange-rate service returned HTTP ${response.statusCode}.');
      }
      final body = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 20));
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final rates = payload['rates'] as Map<String, dynamic>?;
      final rate = rates?[_currency];
      if (payload['result'] != 'success' || rate is! num || rate <= 0) {
        throw const FormatException('Selected currency rate is unavailable.');
      }
      await FinanceDB.instance.saveExchangeRate(
        _currency, 1 / rate.toDouble(), source: 'automatic',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _finish() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name to continue.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _refreshSelectedRate();
      await GeneralPreferences.instance.setYourName(name);
      await FinanceDB.instance.setBaseCurrency(_currency);

      // Fresh-install defaults: create only missing standard wallets, all
      // using the base currency selected during first-time setup.
      final walletDb = DatabaseManager.instance.database;
      await walletDb.transaction((txn) async {
        const defaults = <Map<String, dynamic>>[
          {
            'name': 'Bank',
            'type': 'Bank',
            'icon_code': Icons.account_balance_outlined,
          },
          {
            'name': 'Cash',
            'type': 'Cash',
            'icon_code': Icons.payments_outlined,
          },
          {
            'name': 'Digital Wallet',
            'type': 'Digital Wallet',
            'icon_code': Icons.account_balance_wallet_outlined,
          },
        ];

        for (final wallet in defaults) {
          final existing = await txn.query(
            'wallets',
            columns: ['id'],
            where: 'LOWER(name) = ? AND type = ?',
            whereArgs: [
              (wallet['name'] as String).toLowerCase(),
              wallet['type'],
            ],
            limit: 1,
          );
          if (existing.isNotEmpty) continue;

          await txn.insert('wallets', {
            'name': wallet['name'],
            'type': wallet['type'],
            'custom_type': null,
            'currency': _currency,
            'balance': 0.0,
            'opening_balance': 0.0,
            'wallet_number': null,
            'icon_code': (wallet['icon_code'] as IconData).codePoint,
            'exclude_total': 0,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_completedKey, true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Setup could not be saved: $error')),
      );
      setState(() => _saving = false);
    }
  }

  static const Map<String, String> _currencyFlags = {
    'PKR':'🇵🇰','USD':'🇺🇸','GBP':'🇬🇧','EUR':'🇪🇺','AED':'🇦🇪',
    'SAR':'🇸🇦','INR':'🇮🇳','CAD':'🇨🇦','AUD':'🇦🇺','JPY':'🇯🇵',
    'CNY':'🇨🇳','CHF':'🇨🇭','SGD':'🇸🇬','NZD':'🇳🇿','KWD':'🇰🇼',
    'QAR':'🇶🇦','BHD':'🇧🇭','OMR':'🇴🇲','MYR':'🇲🇾','TRY':'🇹🇷',
    'ZAR':'🇿🇦','HKD':'🇭🇰','IDR':'🇮🇩','KRW':'🇰🇷','THB':'🇹🇭',
  };

  Future<void> _showCurrencyPicker() async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(builder: (context, setSheetState) {
          final filtered = currencies.where((code) {
            final name = _currencyNames[code] ?? code;
            final q = query.trim().toLowerCase();
            return q.isEmpty || code.toLowerCase().contains(q) || name.toLowerCase().contains(q);
          }).toList();
          return Padding(
            padding: EdgeInsets.only(left: 18, right: 18, top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18),
            child: SizedBox(height: MediaQuery.of(context).size.height * .72,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 38, height: 4,
                  decoration: BoxDecoration(color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 18),
                Text('Choose base currency', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Search by currency name or code', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                TextField(autofocus: true, onChanged: (v) => setSheetState(() => query = v),
                  decoration: InputDecoration(hintText: 'Search currencies...',
                    prefixIcon: const Icon(Icons.search_rounded), filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 12),
                Expanded(child: ListView.separated(itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final code = filtered[index]; final selected = code == _currency;
                    return Material(
                      color: selected ? theme.colorScheme.primaryContainer.withOpacity(.65) : theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(15),
                      child: InkWell(borderRadius: BorderRadius.circular(15),
                        onTap: () => Navigator.pop(sheetContext, code),
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(children: [
                            Text(_currencyFlags[code] ?? '🌐', style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 13),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(code, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              Text(_currencyNames[code] ?? code, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ])),
                            if (selected) Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
                          ]),
                        ),
                      ),
                    );
                  })),
              ]),
            ),
          );
        });
      });
    if (picked != null && mounted) setState(() => _currency = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 82, width: 82, alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Icon(Icons.account_balance_wallet_rounded,
                      size: 43, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 25),
                  Text('Welcome to My Finance', textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text("Let's personalize your experience", textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 32),
                  Text('Username', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 9),
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _finish(),
                    decoration: const InputDecoration(
                      hintText: 'Enter username',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('Base Currency', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 9),
                  Material(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _saving ? null : _showCurrencyPicker,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                        child: Row(children: [
                          Text(_currencyFlags[_currency] ?? '🌐',
                            style: const TextStyle(fontSize: 31)),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_currency, style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(_currencyNames[_currency] ?? _currency,
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12)),
                            ],
                          )),
                          const Icon(Icons.unfold_more_rounded),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving ? null : _finish,
                      child: _saving
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Get Started', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text('You can change your name and currency anytime in Settings.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
