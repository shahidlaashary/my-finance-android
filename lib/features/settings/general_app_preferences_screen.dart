import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';

import 'package:my_finance/core/localization/app_text.dart';
class GeneralAppPreferencesScreen extends StatefulWidget {
  const GeneralAppPreferencesScreen({super.key});

  @override
  State<GeneralAppPreferencesScreen> createState() => _GeneralAppPreferencesScreenState();
}

class _GeneralAppPreferencesScreenState extends State<GeneralAppPreferencesScreen> {
  final _preferences = GeneralPreferences.instance;
  bool _loading = true;
  String _dateFormat = 'dd/MM/yyyy';
  String _weekStart = 'Monday';
  String _numberFormat = '1,234.56';
  String _defaultDate = 'Today';
  bool _rememberWallet = true;
  bool _deleteConfirmation = true;
  bool _hideBalances = false;
  bool _hapticFeedback = true;
  final TextEditingController _headerNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      _preferences.dateFormat, _preferences.weekStart, _preferences.numberFormat,
      _preferences.defaultDate, _preferences.rememberWallet,
      _preferences.deleteConfirmation, _preferences.hideBalances,
      _preferences.hapticFeedback, _preferences.headerName,
    ]);
    if (!mounted) return;
    setState(() {
      _dateFormat = values[0] as String;
      _weekStart = values[1] as String;
      _numberFormat = values[2] as String;
      _defaultDate = values[3] as String;
      _rememberWallet = values[4] as bool;
      _deleteConfirmation = values[5] as bool;
      _hideBalances = values[6] as bool;
      _hapticFeedback = values[7] as bool;
      _headerNameController.text = values[8] as String;
      _loading = false;
    });
  }

  @override
  void dispose() { _headerNameController.dispose(); super.dispose(); }

  Future<void> _changeHeaderName() async {
    _headerNameController.text = await _preferences.headerName;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Custom Name'),
        content: TextField(
          controller: _headerNameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Your Name', hintText: 'Enter your name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await _save(() => _preferences.setHeaderName(_headerNameController.text));
      if (mounted) setState(() {});
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    await action();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(appText(context, "Preference saved", "Preference saved"))),
    );
  }

  Widget _choice(String title, String subtitle, IconData icon, String value,
      List<String> options, ValueChanged<String> onChanged) {
    return Card(child: ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        items: options.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) { if (v != null) { setState(() {}); onChanged(v); } },
      ),
    ));
  }

  Widget _toggle(String title, String subtitle, IconData icon, bool value,
      ValueChanged<bool> onChanged) => Card(child: SwitchListTile(
        secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle), value: value, onChanged: onChanged,
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appText(context, 'General App Preferences', 'ایپ کی عمومی ترجیحات'))),
      body: _loading ? Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Custom Name', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('This name appears in the header on all main tabs.'),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: _preferences.headerName,
                builder: (context, snapshot) => Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.person_outline),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      (snapshot.data ?? '').trim().isEmpty ? 'Name not set' : snapshot.data!.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
                onPressed: _changeHeaderName,
                icon: const Icon(Icons.edit_outlined), label: const Text('Change'))),
            ]),
          )),
          _choice('Date Format', 'Choose how dates appear', Icons.calendar_month, _dateFormat,
            const ['dd/MM/yyyy','MM/dd/yyyy','yyyy-MM-dd'], (v) { setState(() => _dateFormat=v); _save(() => _preferences.setDateFormat(v)); }),
          _choice('First Day of Week', 'Calendar week starts on', Icons.calendar_view_week, _weekStart,
            const ['Monday','Sunday'], (v) { setState(() => _weekStart=v); _save(() => _preferences.setWeekStart(v)); }),
          _choice('Number Format', 'Choose decimal and grouping style', Icons.numbers, _numberFormat,
            const ['1,234.56','1.234,56'], (v) { setState(() => _numberFormat=v); _save(() => _preferences.setNumberFormat(v)); }),
          _toggle('Remember Last Wallet', 'Preselect the wallet used last time', Icons.account_balance_wallet_outlined, _rememberWallet,
            (v) { setState(() => _rememberWallet=v); _save(() => _preferences.setRememberWallet(v)); }),
          _choice('Default Transaction Date', 'Date used for a new transaction', Icons.event, _defaultDate,
            const ['Today','Last Selected Date'], (v) { setState(() => _defaultDate=v); _save(() => _preferences.setDefaultDate(v)); }),
          _toggle('Delete Confirmation', 'Ask before deleting records', Icons.delete_outline, _deleteConfirmation,
            (v) { setState(() => _deleteConfirmation=v); _save(() => _preferences.setDeleteConfirmation(v)); }),
          _toggle('Hide Balances', 'Hide financial amounts in the app', Icons.visibility_off_outlined, _hideBalances,
            (v) { setState(() => _hideBalances=v); _save(() => _preferences.setHideBalances(v)); }),
          _toggle('Haptic Feedback', 'Vibration feedback for supported actions', Icons.vibration, _hapticFeedback,
            (v) { setState(() => _hapticFeedback=v); _save(() => _preferences.setHapticFeedback(v)); }),
          SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async { await _preferences.reset(); await _load(); },
            icon: const Icon(Icons.restart_alt), label: Text(appText(context, 'Reset Preferences', 'ترجیحات بحال کریں')),
          ),
          Padding(padding: EdgeInsets.only(top: 8), child: Text(appText(context, "Resetting preferences does not delete wallets, transactions, or other financial records.", "Resetting preferences does not delete wallets, transactions, or other financial records."),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12),
          )),
        ],
      ),
    );
  }
}
