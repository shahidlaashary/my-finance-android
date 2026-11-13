
import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final AssetsService _service = AssetsService();

  List<AssetsModel> _assets = [];
  List<Map<String, dynamic>> _wallets = [];

  Map<String, double> _currentValues = {};
  Map<String, double> _purchaseValues = {};
  Map<String, double> _realizedProfitLoss = {};

  bool _loading = true;
  bool _hideBalances = false;
  bool _showSold = true;
  String? _selectedCategory;

  final NumberFormat _numberFormat =
      NumberFormat('#,##0.00');

  String _money(double value) {
    return _hideBalances ? '••••••' : _numberFormat.format(value);
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _onPreferencesChanged() async {
    final hidden = await GeneralPreferences.instance.hideBalances;
    if (mounted && hidden != _hideBalances) {
      setState(() => _hideBalances = hidden);
    }
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final hideBalances = await GeneralPreferences.instance.hideBalances;
      final assets = await _service.getAssets(
        includeSold: _showSold,
      );

      final current =
          await _service.getTotalCurrentValueByCurrency();

      final purchase =
          await _service.getTotalPurchaseValueByCurrency();

      final realized =
          await _service.getTotalRealizedProfitLossByCurrency();

      final Database db = await TransactionsService.database;

      final wallets = await db.query(
        'wallets',
        orderBy: 'name ASC',
      );

      if (!mounted) return;

      setState(() {
        _hideBalances = hideBalances;
        _assets = assets;
        _wallets = wallets;
        _currentValues = current;
        _purchaseValues = purchase;
        _realizedProfitLoss = realized;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _message('Error loading assets: $e');
    }
  }

  String _accountName(int walletId) {
    final matches = _wallets.where(
      (account) =>
          (account['id'] as num).toInt() == walletId,
    );

    if (matches.isEmpty) return 'Unknown account';

    return matches.first['name'].toString();
  }

  String _currency(int walletId) {
    final matches = _wallets.where(
      (account) =>
          (account['id'] as num).toInt() == walletId,
    );

    if (matches.isEmpty) return 'PKR';

    return matches.first['currency']?.toString() ?? 'PKR';
  }

  List<AssetsModel> get _visibleAssets => _selectedCategory == null
      ? _assets
      : _assets.where((asset) => asset.category.trim().toLowerCase() == _selectedCategory!.toLowerCase()).toList();

  List<String> get _availableCurrencies {
    final currencies = <String>{
      ..._currentValues.keys,
      ..._purchaseValues.keys,
      ..._realizedProfitLoss.keys,
      ..._assets.map((asset) => _currency(asset.walletId)),
    };

    final result = currencies.toList()..sort();

    return result;
  }

  Future<void> _showAssetDialog({
    AssetsModel? asset,
    String? initialCategory,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: asset?.name ?? '');
    final purchaseController = TextEditingController(text: asset?.purchasePrice.toString() ?? '');
    final currentController = TextEditingController(text: asset?.currentValue.toString() ?? '');
    final notesController = TextEditingController(text: asset?.notes ?? '');
    int? selectedAccount = asset?.walletId;
    DateTime purchaseDate = asset?.purchaseDate ?? DateTime.now();
    String selectedCategory = asset?.category ?? initialCategory ?? 'Property';
    const categories = ['Property', 'Vehicles', 'Gold', 'Jewellery', 'Electronics', 'Investments', 'Livestock', 'Business'];

    InputDecoration fieldDecoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E9E5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF147D59), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      isDense: true,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
          final screenHeight = MediaQuery.sizeOf(context).height;
          final keyboardOpen = keyboardHeight > 0;
          final maxHeight = keyboardOpen
              ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * .95
              : screenHeight * .72;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      primary: false,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD9E0DC), borderRadius: BorderRadius.circular(10)))),
                          SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: Text(asset == null ? 'Add Asset' : 'Edit Asset', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF202B25)))),
                            IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded), color: Colors.grey),
                          ]),
                          SizedBox(height: 10),
                          TextFormField(controller: nameController, decoration: fieldDecoration('Asset Name', Icons.inventory_2_outlined),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Enter asset name' : null),
                          SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: DropdownButtonFormField<String>(
                              value: categories.contains(selectedCategory) ? selectedCategory : categories.first,
                              isExpanded: true,
                              decoration: fieldDecoration('Asset Property', Icons.category_outlined),
                              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) { if (v != null) setSheetState(() => selectedCategory = v); },
                            )),
                            SizedBox(width: 10),
                            Expanded(child: DropdownButtonFormField<int>(
                              value: selectedAccount, isExpanded: true,
                              decoration: fieldDecoration('Payment Account', Icons.account_balance_wallet_outlined),
                              items: _wallets.map((w) => DropdownMenuItem<int>(value: (w['id'] as num).toInt(), child: Text('${w['name']} (${w['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) => setSheetState(() => selectedAccount = v),
                              validator: (v) => v == null ? 'Select account' : null,
                            )),
                          ]),
                          SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: TextFormField(
                              controller: purchaseController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: fieldDecoration('Purchase Price', Icons.shopping_bag_outlined),
                              validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid purchase price' : null; },
                            )),
                            SizedBox(width: 10),
                            Expanded(child: TextFormField(
                              controller: currentController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: fieldDecoration('Current Value', Icons.trending_up_rounded),
                              validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 ? 'Enter a valid current value' : null; },
                            )),
                          ]),
                          SizedBox(height: 8),
                          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.calendar_month, color: Color(0xFF147D59)),
                            title: Text(appText(context, 'Purchase Date', 'خریداری کی تاریخ')), subtitle: Text(DateFormat('dd MMM yyyy').format(purchaseDate)),
                            trailing: const Icon(Icons.edit_calendar), onTap: () async {
                              final picked = await showDatePicker(context: context, initialDate: purchaseDate, firstDate: DateTime(1950), lastDate: DateTime.now());
                              if (picked != null) setSheetState(() => purchaseDate = picked);
                            }),
                          TextFormField(controller: notesController, maxLines: 2, decoration: fieldDecoration('Notes (optional)', Icons.notes_outlined)),
                          SizedBox(height: 16),
                          Row(children: [
                            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext), child: Text(appText(context, 'Cancel', 'منسوخ کریں')))),
                            SizedBox(width: 10),
                            Expanded(child: ElevatedButton.icon(
                              icon: const Icon(Icons.check_rounded), label: Text(asset == null ? 'Save Asset' : 'Update Asset'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF147D59), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                try {
                                  final model = AssetsModel(id: asset?.id, name: nameController.text.trim(), category: selectedCategory,
                                    purchasePrice: double.parse(purchaseController.text), currentValue: double.parse(currentController.text),
                                    purchaseDate: purchaseDate, walletId: selectedAccount!, notes: notesController.text.trim(),
                                    isSold: asset?.isSold ?? false, saleDate: asset?.saleDate, salePrice: asset?.salePrice,
                                    createdAt: asset?.createdAt ?? DateTime.now());
                                  if (asset == null) { await _service.addAsset(model); } else { await _service.updateAsset(model); }
                                  if (!sheetContext.mounted) return;
                                  Navigator.pop(sheetContext);
                                  await _loadData();
                                  _message(asset == null ? 'Asset added successfully.' : 'Asset updated successfully.');
                                } catch (e) { _message('Error: $e'); }
                              },
                            )),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    nameController.dispose();
    purchaseController.dispose();
    currentController.dispose();
    notesController.dispose();
  }

  Future<void> _updateValuation(AssetsModel asset) async {
    final controller = TextEditingController(
      text: asset.currentValue.toString(),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText(context, 'Update Current Value', 'موجودہ قیمت اپ ڈیٹ کریں')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'New Current Value',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            ElevatedButton(
              onPressed: () {
                final value =
                    double.tryParse(controller.text);

                if (value == null ||
                    !value.isFinite ||
                    value < 0) {
                  return;
                }

                Navigator.pop(context, value);
              },
              child: Text(appText(context, 'Update', 'اپ ڈیٹ کریں')),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || asset.id == null) return;

    try {
      await _service.updateCurrentValue(asset.id!, result);
      await _loadData();
      _message('Asset valuation updated.');
    } catch (e) {
      _message('Error: $e');
    }
  }

  Future<void> _sellAsset(AssetsModel asset) async {
    final controller = TextEditingController(
      text: asset.currentValue.toString(),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        DateTime saleDate = DateTime.now();
        int? selectedSaleWallet = asset.walletId;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(appText(context, 'Sell Asset', 'اثاثہ فروخت کریں')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Sale Price',
                    ),
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedSaleWallet,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Sale Account',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    items: _wallets.map((wallet) {
                      return DropdownMenuItem<int>(
                        value: (wallet['id'] as num).toInt(),
                        child: Text('${wallet['name']} (${wallet['currency'] ?? 'PKR'})'),
                      );
                    }).toList(),
                    onChanged: (value) => setDialogState(() => selectedSaleWallet = value),
                  ),
                  SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(appText(context, 'Sale Date', 'فروخت کی تاریخ')),
                    subtitle: Text(
                      DateFormat('dd MMM yyyy')
                          .format(saleDate),
                    ),
                    trailing:
                        const Icon(Icons.calendar_month),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: saleDate,
                        firstDate: asset.purchaseDate,
                        lastDate: DateTime.now(),
                      );

                      if (selected != null) {
                        setDialogState(() {
                          saleDate = selected;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final price =
                        double.tryParse(controller.text);

                    if (price == null ||
                        !price.isFinite ||
                        price < 0) {
                      return;
                    }

                    if (selectedSaleWallet == null) return;
                    Navigator.pop(context, {
                      'price': price,
                      'date': saleDate,
                      'walletId': selectedSaleWallet,
                    });
                  },
                  child: Text(appText(context, 'Confirm Sale', 'فروخت کی تصدیق کریں')),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (result == null || asset.id == null) return;

    try {
      await _service.sellAsset(
        assetId: asset.id!,
        salePrice: result['price'] as double,
        saleDate: result['date'] as DateTime,
        saleWalletId: result['walletId'] as int,
      );

      await _loadData();
      _message('Asset sold successfully.');
    } catch (e) {
      _message('Error selling asset: $e');
    }
  }

  Future<void> _deleteAsset(AssetsModel asset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText(context, 'Delete Asset', 'اثاثہ حذف کریں')),
          content: Text(
            'Are you sure you want to delete "${asset.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true || asset.id == null) return;

    try {
      await _service.deleteAsset(asset.id!);
      await _loadData();
      _message('Asset deleted successfully.');
    } catch (e) {
      _message('Error deleting asset: $e');
    }
  }

  Widget _heroMetric(String label, String value, {Color valueColor = Colors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFD6F5E7), fontSize: 10)),
        SizedBox(height: 5),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _summaryCard(
    String title,
    String currency,
    double amount,
    IconData icon, {
    Color color = const Color(0xFF147D59),
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 25),
            SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 5),
            Text(
              '$currency ${_money(amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _assetCard(AssetsModel asset) {
    final purchaseCurrency = _currency(asset.walletId);
    final saleCurrency = _currency(asset.saleWalletId ?? asset.walletId);
    final currency = asset.isSold ? saleCurrency : purchaseCurrency;

    final profitLoss = asset.isSold && asset.salePrice != null
        ? asset.salePrice! - asset.purchasePrice
        : asset.currentValue - asset.purchasePrice;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE2F2EB),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFF147D59),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        asset.category.isEmpty
                            ? 'Uncategorized'
                            : asset.category,
                        style: const TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (asset.isSold)
                  const Chip(
                    label: Text('Sold'),
                    backgroundColor: Color(0xFFFFE9E9),
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit' && !asset.isSold) {
                      _showAssetDialog(asset: asset);
                    } else if (value == 'valuation' &&
                        !asset.isSold) {
                      _updateValuation(asset);
                    } else if (value == 'sell' &&
                        !asset.isSold) {
                      _sellAsset(asset);
                    } else if (value == 'delete') {
                      _deleteAsset(asset);
                    }
                  },
                  itemBuilder: (context) => [
                    if (!asset.isSold)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text(appText(context, 'Edit Asset', 'اثاثے میں ترمیم کریں')),
                      ),
                    if (!asset.isSold)
                      const PopupMenuItem(
                        value: 'valuation',
                        child: Text(appText(context, 'Update Valuation', 'قیمت اپ ڈیٹ کریں')),
                      ),
                    if (!asset.isSold)
                      const PopupMenuItem(
                        value: 'sell',
                        child: Text(appText(context, 'Sell Asset', 'اثاثہ فروخت کریں')),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(appText(context, 'Delete Asset', 'اثاثہ حذف کریں')),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            _detailRow(
              'Purchase Price',
              '$purchaseCurrency ${_money(asset.purchasePrice)}',
            ),
            SizedBox(height: 7),
            if (!asset.isSold)
              _detailRow(
                'Current Value',
                '$currency ${_money(asset.currentValue)}',
                bold: true,
              ),
            if (asset.isSold && asset.salePrice != null)
              _detailRow(
                'Sale Price',
                '$saleCurrency ${_money(asset.salePrice!)}',
                bold: true,
              ),
            SizedBox(height: 7),
            _detailRow(
              asset.isSold
                  ? 'Realized Profit/Loss'
                  : 'Unrealized Profit/Loss',
              '$currency ${_money(profitLoss)}',
              valueColor:
                  profitLoss >= 0 ? Colors.green : Colors.red,
              bold: true,
            ),
            SizedBox(height: 7),
            _detailRow(
              'Purchase Account',
              _accountName(asset.walletId),
            ),
            if (asset.isSold)
              _detailRow(
                'Sale Account',
                _accountName(asset.saleWalletId ?? asset.walletId),
              ),
            SizedBox(height: 7),
            _detailRow(
              'Purchase Date',
              DateFormat('dd MMM yyyy')
                  .format(asset.purchaseDate),
            ),
            if (asset.isSold && asset.saleDate != null) ...[
              SizedBox(height: 7),
              _detailRow(
                'Sale Date',
                DateFormat('dd MMM yyyy')
                    .format(asset.saleDate!),
              ),
            ],
            if (asset.notes.isNotEmpty) ...[
              SizedBox(height: 10),
              Text(
                asset.notes,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            if (asset.id != null) ...[
              const Divider(height: 24),
              AttachmentSection(
                ownerType: 'asset',
                ownerId: asset.id!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    String title,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(title)),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: valueColor,
              fontWeight:
                  bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _currencySummary(String currency) {
    final current = _currentValues[currency] ?? 0;
    final purchase = _purchaseValues[currency] ?? 0;
    final realized = _realizedProfitLoss[currency] ?? 0;

    final unrealized = current - purchase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            currency,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.65,
            children: [
              _summaryCard(
                'Current Value',
                currency,
                current,
                Icons.account_balance,
              ),
              _summaryCard(
                'Purchase Value',
                currency,
                purchase,
                Icons.shopping_bag,
                color: Colors.blue,
              ),
              _summaryCard(
                'Realized Profit/Loss',
                currency,
                realized,
                Icons.trending_up,
                color: realized >= 0
                    ? Colors.green
                    : Colors.red,
              ),
              _summaryCard(
                'Unrealized Profit/Loss',
                currency,
                unrealized,
                Icons.show_chart,
                color: unrealized >= 0
                    ? Colors.green
                    : Colors.red,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final currencies = _availableCurrencies;

    final primaryCurrency = currencies.contains('PKR')
        ? 'PKR'
        : (currencies.isNotEmpty ? currencies.first : 'PKR');
    final currentTotal = _currentValues[primaryCurrency] ?? 0;
    final purchaseTotal = _purchaseValues[primaryCurrency] ?? 0;
    final unrealized = currentTotal - purchaseTotal;
    final categoryItems = <Map<String, dynamic>>[
      {'name': 'Business', 'icon': Icons.storefront_outlined},
      {'name': 'Electronics', 'icon': Icons.devices_other_outlined},
      {'name': 'Gold', 'icon': Icons.diamond_outlined},
      {'name': 'Investments', 'icon': Icons.trending_up_rounded},
      {'name': 'Jewellery', 'icon': Icons.watch_outlined},
      {'name': 'Livestock', 'icon': Icons.pets_outlined},
      {'name': 'Property', 'icon': Icons.home_work_outlined},
      {'name': 'Vehicles', 'icon': Icons.directions_car_outlined},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202A26),
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: const Text('My Assets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF202A26))),
        actions: buildSharedAppBarActions(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE7EEEA)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAssetDialog,
        backgroundColor: const Color(0xFF147D59),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(appText(context, 'Add Asset', 'اثاثہ شامل کریں')),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF147D59), Color(0xFF0B6245)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOTAL ASSET VALUE  •  $primaryCurrency',
                          style: const TextStyle(color: Color(0xFFD6F5E7), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
                        SizedBox(height: 5),
                        Text('$primaryCurrency ${_money(currentTotal)}',
                          style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _heroMetric('Purchase Value', '$primaryCurrency ${_money(purchaseTotal)}')),
                            Container(width: 1, height: 28, color: Colors.white24),
                            SizedBox(width: 14),
                            Expanded(child: _heroMetric('Unrealized P/L', '$primaryCurrency ${_money(unrealized)}', valueColor: unrealized >= 0 ? const Color(0xFFB9F6D3) : const Color(0xFFFFC5C5))),
                          ],
                        ),
                        if (currencies.length > 1) ...[
                          SizedBox(height: 7),
                          const Text('Totals shown for this currency; other currencies below.',
                            style: TextStyle(color: Color(0xFFD6F5E7), fontSize: 10)),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  GridView.builder(
                    itemCount: categoryItems.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, crossAxisSpacing: 7, mainAxisSpacing: 7, childAspectRatio: 1.70),
                    itemBuilder: (context, index) {
                      final item = categoryItems[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _selectedCategory = _selectedCategory == item['name'] ? null : item['name'] as String),
                        child: Container(
                          decoration: BoxDecoration(color: _selectedCategory == item['name'] ? const Color(0xFFE5F4EC) : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _selectedCategory == item['name'] ? const Color(0xFF147D59) : const Color(0xFFE7EEEA), width: _selectedCategory == item['name'] ? 1.5 : 1)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(item['icon'] as IconData, color: const Color(0xFF147D59), size: 19),
                            SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(item['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Text(_selectedCategory == null ? 'My Assets' : '${_selectedCategory!} Assets', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                      Text('${_visibleAssets.where((a) => !a.isSold).length} Active',
                        style: const TextStyle(color: Color(0xFF147D59), fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  if (currencies.isNotEmpty)
                    ...currencies.where((c) => c != primaryCurrency).map(_currencySummary),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Sold Assets', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    value: _showSold,
                    onChanged: (value) {
                      setState(() => _showSold = value);
                      _loadData();
                    },
                  ),
                  if (_visibleAssets.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                      child: Column(children: [
                        const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 10),
                        Text(_selectedCategory == null ? 'No assets added yet' : 'No ${_selectedCategory!} assets found', style: const TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text(_selectedCategory == null ? 'Add your first asset to start tracking its value.' : 'Add an asset in this category to see it here.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ]),
                    )
                  else
                    ..._visibleAssets.map(_assetCard),
                ],
              ),
            ),
    );
  }
}
