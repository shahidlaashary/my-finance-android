
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../models/asset_model.dart';
import '../services/asset_service.dart';
import '../services/transaction_service.dart';
import '../widgets/attachment_section.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final AssetService _service = AssetService();

  List<AssetModel> _assets = [];
  List<Map<String, dynamic>> _wallets = [];

  Map<String, double> _currentValues = {};
  Map<String, double> _purchaseValues = {};
  Map<String, double> _realizedProfitLoss = {};

  bool _loading = true;
  bool _showSold = true;

  final NumberFormat _numberFormat =
      NumberFormat('#,##0.00');

  String _money(double value) {
    return _numberFormat.format(value);
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final assets = await _service.getAssets(
        includeSold: _showSold,
      );

      final current =
          await _service.getTotalCurrentValueByCurrency();

      final purchase =
          await _service.getTotalPurchaseValueByCurrency();

      final realized =
          await _service.getTotalRealizedProfitLossByCurrency();

      final Database db = await TransactionService.database;

      final wallets = await db.query(
        'wallets',
        orderBy: 'name ASC',
      );

      if (!mounted) return;

      setState(() {
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
    AssetModel? asset,
  }) async {
    final formKey = GlobalKey<FormState>();

    final nameController = TextEditingController(
      text: asset?.name ?? '',
    );

    final categoryController = TextEditingController(
      text: asset?.category ?? '',
    );

    final purchaseController = TextEditingController(
      text: asset == null
          ? ''
          : asset.purchasePrice.toString(),
    );

    final currentController = TextEditingController(
      text: asset == null
          ? ''
          : asset.currentValue.toString(),
    );

    final notesController = TextEditingController(
      text: asset?.notes ?? '',
    );

    int? selectedAccount = asset?.walletId;

    DateTime purchaseDate =
        asset?.purchaseDate ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                asset == null ? 'Add Asset' : 'Edit Asset',
              ),
              content: SizedBox(
                width: 450,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Asset Name',
                            prefixIcon: Icon(Icons.inventory_2),
                          ),
                          validator: (value) =>
                              value == null ||
                                      value.trim().isEmpty
                                  ? 'Enter asset name'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: categoryController,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.category),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: purchaseController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Purchase Price',
                          ),
                          validator: (value) {
                            final amount =
                                double.tryParse(value ?? '');

                            if (amount == null ||
                                !amount.isFinite ||
                                amount <= 0) {
                              return 'Enter a valid purchase price';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: currentController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Current Value',
                          ),
                          validator: (value) {
                            final amount =
                                double.tryParse(value ?? '');

                            if (amount == null ||
                                !amount.isFinite ||
                                amount < 0) {
                              return 'Enter a valid current value';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: selectedAccount,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Payment Account',
                          ),
                          items: _wallets.map((account) {
                            return DropdownMenuItem<int>(
                              value:
                                  (account['id'] as num).toInt(),
                              child: Text(
                                '${account['name']} '
                                '(${account['currency'] ?? 'PKR'})',
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedAccount = value;
                            });
                          },
                          validator: (value) =>
                              value == null
                                  ? 'Select account'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading:
                              const Icon(Icons.calendar_month),
                          title: const Text('Purchase Date'),
                          subtitle: Text(
                            DateFormat('dd MMM yyyy')
                                .format(purchaseDate),
                          ),
                          trailing:
                              const Icon(Icons.edit_calendar),
                          onTap: () async {
                            final selected =
                                await showDatePicker(
                              context: context,
                              initialDate: purchaseDate,
                              firstDate: DateTime(1950),
                              lastDate: DateTime.now(),
                            );

                            if (selected != null) {
                              setDialogState(() {
                                purchaseDate = selected;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }

                    try {
                      final purchasePrice =
                          double.parse(purchaseController.text);

                      final currentValue =
                          double.parse(currentController.text);

                      final model = AssetModel(
                        id: asset?.id,
                        name: nameController.text.trim(),
                        category: categoryController.text.trim(),
                        purchasePrice: purchasePrice,
                        currentValue: currentValue,
                        purchaseDate: purchaseDate,
                        walletId: selectedAccount!,
                        notes: notesController.text.trim(),
                        isSold: asset?.isSold ?? false,
                        saleDate: asset?.saleDate,
                        salePrice: asset?.salePrice,
                        createdAt: asset?.createdAt ??
                            DateTime.now(),
                      );

                      if (asset == null) {
                        await _service.addAsset(model);
                      } else {
                        await _service.updateAsset(model);
                      }

                      if (!dialogContext.mounted) return;

                      Navigator.pop(dialogContext);

                      await _loadData();

                      _message(
                        asset == null
                            ? 'Asset added successfully.'
                            : 'Asset updated successfully.',
                      );
                    } catch (e) {
                      _message('Error: $e');
                    }
                  },
                  child: Text(
                    asset == null
                        ? 'Save Asset'
                        : 'Update Asset',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    categoryController.dispose();
    purchaseController.dispose();
    currentController.dispose();
    notesController.dispose();
  }

  Future<void> _updateValuation(AssetModel asset) async {
    final controller = TextEditingController(
      text: asset.currentValue.toString(),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Current Value'),
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
              child: const Text('Cancel'),
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
              child: const Text('Update'),
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

  Future<void> _sellAsset(AssetModel asset) async {
    final controller = TextEditingController(
      text: asset.currentValue.toString(),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        DateTime saleDate = DateTime.now();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Sell Asset'),
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
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sale Date'),
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
                  child: const Text('Cancel'),
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

                    Navigator.pop(context, {
                      'price': price,
                      'date': saleDate,
                    });
                  },
                  child: const Text('Confirm Sale'),
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
      );

      await _loadData();
      _message('Asset sold successfully.');
    } catch (e) {
      _message('Error selling asset: $e');
    }
  }

  Future<void> _deleteAsset(AssetModel asset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Asset'),
          content: Text(
            'Are you sure you want to delete "${asset.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel'),
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
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 5),
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

  Widget _assetCard(AssetModel asset) {
    final currency = _currency(asset.walletId);

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
                const SizedBox(width: 12),
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
                        child: Text('Edit Asset'),
                      ),
                    if (!asset.isSold)
                      const PopupMenuItem(
                        value: 'valuation',
                        child: Text('Update Valuation'),
                      ),
                    if (!asset.isSold)
                      const PopupMenuItem(
                        value: 'sell',
                        child: Text('Sell Asset'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Asset'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            _detailRow(
              'Purchase Price',
              '$currency ${_money(asset.purchasePrice)}',
            ),
            const SizedBox(height: 7),
            if (!asset.isSold)
              _detailRow(
                'Current Value',
                '$currency ${_money(asset.currentValue)}',
                bold: true,
              ),
            if (asset.isSold && asset.salePrice != null)
              _detailRow(
                'Sale Price',
                '$currency ${_money(asset.salePrice!)}',
                bold: true,
              ),
            const SizedBox(height: 7),
            _detailRow(
              asset.isSold
                  ? 'Realized Profit/Loss'
                  : 'Unrealized Profit/Loss',
              '$currency ${_money(profitLoss)}',
              valueColor:
                  profitLoss >= 0 ? Colors.green : Colors.red,
              bold: true,
            ),
            const SizedBox(height: 7),
            _detailRow(
              'Account',
              _accountName(asset.walletId),
            ),
            const SizedBox(height: 7),
            _detailRow(
              'Purchase Date',
              DateFormat('dd MMM yyyy')
                  .format(asset.purchaseDate),
            ),
            if (asset.isSold && asset.saleDate != null) ...[
              const SizedBox(height: 7),
              _detailRow(
                'Sale Date',
                DateFormat('dd MMM yyyy')
                    .format(asset.saleDate!),
              ),
            ],
            if (asset.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
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
        const SizedBox(width: 8),
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
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final currencies = _availableCurrencies;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        title: const Text('Assets'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAssetDialog,
        backgroundColor: const Color(0xFF147D59),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Asset'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  if (currencies.isNotEmpty)
                    ...currencies.map(_currencySummary),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show Sold Assets'),
                      value: _showSold,
                      onChanged: (value) {
                        setState(() => _showSold = value);
                        _loadData();
                      },
                    ),
                  ),
                  if (_assets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 55,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No assets found.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._assets.map(_assetCard),
                ],
              ),
            ),
    );
  }
}
