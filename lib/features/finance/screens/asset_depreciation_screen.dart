import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/asset_depreciation_service.dart';

class AssetDepreciationScreen extends StatefulWidget {
  const AssetDepreciationScreen({super.key});

  @override
  State<AssetDepreciationScreen> createState() => _AssetDepreciationScreenState();
}

class _AssetDepreciationScreenState extends State<AssetDepreciationScreen> {
  final _assetsService = AssetsService();
  final _service = AssetDepreciationService();
  final _money = NumberFormat('#,##0.00');
  List<AssetsModel> _assets = [];
  final Map<int, Map<String, dynamic>?> _settings = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final assets = await _assetsService.getAssets(includeSold: false);
      _settings.clear();
      for (final asset in assets) {
        if (asset.id != null) {
          _settings[asset.id!] = await _service.getSettings(asset.id!);
        }
      }
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Depreciation data load nahi ho saka: $error');
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _configure(AssetsModel asset) async {
    if (asset.id == null) return;
    final existing = _settings[asset.id!];
    String method = existing?['method']?.toString() ?? 'straight_line';
    final life = TextEditingController(
      text: (existing?['useful_life_years'] ?? 5).toString());
    final salvage = TextEditingController(
      text: (existing?['salvage_value'] ?? 0).toString());
    final rate = TextEditingController(
      text: (existing?['declining_rate'] ?? 20).toString());
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Depreciation • ${asset.name}'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: const [
                    DropdownMenuItem(value: 'straight_line', child: Text('Straight-line')),
                    DropdownMenuItem(value: 'declining_balance', child: Text('Declining balance')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => method = value);
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: life,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Useful life (years)'),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || !n.isFinite || n <= 0 || n > 100
                        ? 'Enter 0–100 years'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: salvage,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Salvage value'),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || !n.isFinite || n < 0
                        ? 'Enter a valid amount'
                        : null;
                  },
                ),
                if (method == 'declining_balance') ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Annual declining rate (%)'),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      return n == null || !n.isFinite || n <= 0 || n > 100
                          ? 'Enter 0–100%'
                          : null;
                    },
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
            FilledButton(onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await _service.saveSettings(
          assetId: asset.id!,
          method: method,
          usefulLifeYears: double.parse(life.text),
          salvageValue: double.parse(salvage.text),
          decliningRate: double.tryParse(rate.text) ?? 20,
        );
        await _load();
        _message('Depreciation settings saved.');
      } catch (error) {
        _message('Settings save nahi ho sakin: $error');
      }
    }
    life.dispose();
    salvage.dispose();
    rate.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asset Depreciation')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _assets.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 100),
                      Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey),
                      SizedBox(height: 12),
                      Center(child: Text('No active assets available.')),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _assets.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final asset = _assets[index];
                        final config = asset.id == null ? null : _settings[asset.id!];
                        final values = _service.calculate(
                          purchasePrice: asset.purchasePrice,
                          purchaseDate: asset.purchaseDate,
                          settings: config,
                        );
                        final configured = config != null;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.trending_down_rounded),
                                  const SizedBox(width: 9),
                                  Expanded(child: Text(asset.name,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                                  TextButton(onPressed: () => _configure(asset),
                                    child: Text(configured ? 'Edit' : 'Configure')),
                                ]),
                                Text(configured
                                    ? (config!['method'] == 'declining_balance'
                                        ? 'Declining balance • ${config['declining_rate']}% rate'
                                        : 'Straight-line • ${config['useful_life_years']} years')
                                    : 'Default estimate • Configure for accurate schedule',
                                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                const Divider(height: 20),
                                _line('Purchase cost', asset.purchasePrice),
                                _line('Estimated book value', values['book_value']!),
                                _line('Accumulated depreciation', values['accumulated_depreciation']!),
                                _line('Annual depreciation', values['annual_depreciation']!),
                                _line('Monthly depreciation', values['monthly_depreciation']!),
                                Text('Purchased ${DateFormat('dd MMM yyyy').format(asset.purchaseDate)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _line(String label, double amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
      Text(_money.format(amount), style: const TextStyle(fontWeight: FontWeight.w700)),
    ]),
  );
}
