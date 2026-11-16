import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:my_finance/app/screens/main_screen.dart';

/// First-install personalization. Saves the name into the existing header setting.
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
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
      // Reuse the exact existing Custom Name setting used by every page header.
      await GeneralPreferences.instance.setHeaderName(name);
      await FinanceDB.instance.setBaseCurrency(_currency);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencies = CurrencyCatalog.supported.toList()..sort();
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
                    height: 82,
                    width: 82,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Icon(Icons.account_balance_wallet_rounded,
                        size: 43, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 25),
                  Text('Welcome to My Finance',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text("Let's personalize your experience",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 32),
                  Text('Your Name', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 9),
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _finish(),
                    decoration: const InputDecoration(
                      hintText: 'Enter your name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('Base Currency', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 9),
                  DropdownButtonFormField<String>(
                    value: _currency,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.currency_exchange_rounded),
                      border: OutlineInputBorder(),
                    ),
                    items: currencies.map((code) => DropdownMenuItem(
                      value: code,
                      child: Text('$code — ${_currencyNames[code] ?? code}',
                        overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: _saving ? null : (value) {
                      if (value != null) setState(() => _currency = value);
                    },
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving ? null : _finish,
                      child: _saving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Get Started', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text('You can change your name and currency anytime in Settings.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
