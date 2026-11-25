
import 'package:my_finance/core/database/database_manager.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/database/finance_database.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/modules/finance/models/finance_category.dart';
import 'package:my_finance/modules/finance/services/category_service.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
import 'package:my_finance/modules/finance/services/assets_service.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';
import 'package:my_finance/modules/finance/services/recurring_transaction_service.dart';
import 'package:my_finance/modules/finance/screens/recurring_transactions_screen.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

class TransactionsScreen extends StatefulWidget {
  final int? walletId;
  final String? walletName;
  final bool showAllTransactions;

  const TransactionsScreen({super.key, this.walletId, this.walletName, this.showAllTransactions = false});

  @override
  State<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Map<String, dynamic>> transactions = [];
  Map<String, dynamic>? walletInfo;
  bool loading = true;
  bool hideBalances = false;
  String numberFormat = '1,234.56';
  String dateFormat = 'dd/MM/yyyy';
  String weekStart = 'Monday';
  String selectedFilter = 'all';
  int currentPage = 0;

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    AppRefreshController.revision.addListener(_onAppDataChanged);
    loadTransactions();
  }

  void _onAppDataChanged() {
    if (mounted) loadTransactions();
  }

  void _onPreferencesChanged() {
    if (mounted) loadTransactions();
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    super.dispose();
  }

  Future<void> loadTransactions() async {
    if (mounted) setState(() => loading = true);

    try {
      final hide = await GeneralPreferences.instance.hideBalances;
      final number = await GeneralPreferences.instance.numberFormat;
      final date = await GeneralPreferences.instance.dateFormat;
      final week = await GeneralPreferences.instance.weekStart;
      final result = await TransactionsService.getTransactions(walletId: widget.walletId);

      // Include asset and loan activity in the existing Others filter.
      // These are read-only source records; wallet transactions remain editable.
      final assetModels = await AssetsService().getAssets();
      final loanModels = await LoansService.getLoans();
      final otherRows = <Map<String, dynamic>>[];
      for (final asset in assetModels) {
        otherRows.add({
          'id': 'asset_purchase_${asset.id}',
          'source_record': true,
          'type': 'asset',
          'amount': asset.purchasePrice,
          'wallet_id': asset.walletId,
          'category': 'Asset Purchase • ${asset.category}',
          'note': 'Purchased: ${asset.name}',
          'date': asset.purchaseDate.toIso8601String(),
          'wallet_currency': asset.currency,
          'payment_type': asset.paymentType,
        });
        if (asset.isSold && asset.salePrice != null && asset.saleDate != null) {
          otherRows.add({
            'id': 'asset_sale_${asset.id}',
            'source_record': true,
            'type': 'asset',
            'amount': asset.saleWalletAmount ?? asset.salePrice,
            'wallet_id': asset.saleWalletId ?? asset.walletId,
            'category': 'Asset Sale',
            'note': 'Sold: ${asset.name}',
            'date': asset.saleDate!.toIso8601String(),
            'wallet_currency': asset.saleWalletCurrency,
            'payment_type': asset.salePaymentType,
          });
        }
      }
      for (final loan in loanModels) {
        // Asset-linked loans are represented by their asset purchase/sale row,
        // but their repayments must still appear in the Others transaction filter.
        final isAssetLinked =
            loan.sourceType == 'asset_purchase' || loan.sourceType == 'asset_sale';
        if (!isAssetLinked) {
          otherRows.add({
            'id': 'loan_${loan.id}',
            'source_record': true,
            'type': 'loan',
            'amount': loan.amount,
            'wallet_id': loan.walletId,
            'category': loan.loanType == 'given' ? 'Loan Given' : 'Loan Taken',
            'note': loan.notes.trim().isNotEmpty ? loan.notes : (loan.loanType == 'given' ? 'Loan Given' : 'Loan Taken'),
            'date': loan.lendingDate,
            'wallet_currency': loan.currency,
          });
        }
        if (loan.id != null) {
          final repayments = await LoansService.getRepayments(loan.id!);
          for (final repayment in repayments) {
            otherRows.add({
              'id': 'loan_repayment_${repayment.id}',
              'source_record': true,
              'type': 'loan',
              // Wallet history must use the exact saved wallet-side snapshot.
              // Loan/Asset Details continue to use repayment.amount in loan currency.
              'amount': repayment.walletAmount,
              'wallet_id': repayment.walletId,
              'category': 'Loan Repayment',
              'note': 'Loan Repayment',
              'date': repayment.repaymentDate,
              'wallet_currency': repayment.walletCurrency,
              'original_currency': loan.currency,
              'original_amount': repayment.amount,
              'exchange_rate': repayment.exchangeRate,
            });
          }
        }
      }
      if (widget.walletId != null) {
        // Loan-financed asset purchases/sales are source records, not wallet cash flows.
        // Keep them in the global Others list, but hide them from wallet-specific history.
        otherRows.removeWhere((row) =>
            row['wallet_id'] != widget.walletId ||
            (row['type'] == 'asset' &&
                row['payment_type']?.toString().trim().toLowerCase() == 'loan'));
      }
      final wallet = widget.walletId == null ? null : await FinanceDB.instance.getWallet(widget.walletId!);

      // Upcoming recurring schedules are display-only; they do not affect balances.
      final recurringItems = await RecurringTransactionService().getRecurringTransactions(activeOnly: true);
      final db = DatabaseManager.instance.database;
      final walletRows = await db.query('wallets', columns: ['id', 'currency']);
      final currencyByWallet = <int, String>{
        for (final row in walletRows)
          (row['id'] as num).toInt(): row['currency']?.toString() ?? '',
      };
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final scheduledRows = <Map<String, dynamic>>[];
      for (final schedule in recurringItems) {
        final nextDate = schedule.nextRunDate;
        if (nextDate == null) continue;
        final scheduledDate = DateTime(nextDate.year, nextDate.month, nextDate.day);
        if (!scheduledDate.isAfter(today)) continue;
        if (widget.walletId != null && schedule.walletId != widget.walletId && schedule.toWalletId != widget.walletId) continue;
        scheduledRows.add({
          'id': schedule.id,
          'is_scheduled': true,
          'type': schedule.type[0].toUpperCase() + schedule.type.substring(1).toLowerCase(),
          'amount': schedule.amount,
          'transfer_fee': schedule.transferFee,
          'wallet_id': schedule.walletId,
          'to_wallet_id': schedule.toWalletId,
          'category': schedule.category ?? '',
          'note': schedule.note.trim().isNotEmpty ? schedule.note : schedule.title,
          'date': DateFormat('yyyy-MM-dd').format(scheduledDate),
          'wallet_currency': currencyByWallet[schedule.walletId] ?? '',
          'frequency': schedule.frequency,
        });
      }

      if (!mounted) return;

      setState(() {
        transactions = [...result, ...scheduledRows, ...otherRows];
        walletInfo = wallet;
        hideBalances = hide;
        numberFormat = number;
        dateFormat = date;
        weekStart = week;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }


  Future<void> adjustWalletBalance() async {
    final wallet = walletInfo;
    if (wallet == null) return;
    final controller = TextEditingController(
      text: (wallet['balance'] as num).toStringAsFixed(2),
    );
    final newBalance = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Adjust Balance'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(
            labelText: 'New balance',
            prefixText: '${wallet['currency']} ',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || !value.isFinite) return;
              Navigator.pop(dialogContext, value);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newBalance == null) return;
    try {
      await FinanceDB.instance.updateWallet(
        id: (wallet['id'] as num).toInt(),
        name: wallet['name'] as String,
        type: wallet['type'] as String,
        customType: wallet['custom_type'] as String?,
        currency: wallet['currency'] as String,
        requestedCurrentBalance: newBalance,
        walletNumber: wallet['wallet_number'] as String?,
        iconCode: (wallet['icon_code'] as num).toInt(),
        excludeTotal: (wallet['exclude_total'] as num? ?? 0).toInt() == 1,
      );
      await loadTransactions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Balance adjusted. Adjustment transaction added.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _buildWalletSummaryCard() {
    final wallet = walletInfo;
    if (widget.walletId == null || wallet == null) return const SizedBox.shrink();
    final currency = wallet['currency']?.toString() ?? '';
    final balance = (wallet['balance'] as num?)?.toDouble() ?? 0;
    final iconCode = (wallet['icon_code'] as num?)?.toInt() ??
        Icons.account_balance_wallet_outlined.codePoint;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.surfaceContainerLowest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(IconData(iconCode, fontFamily: 'MaterialIcons'),
                color: Theme.of(context).colorScheme.primary, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(wallet['name']?.toString() ?? 'Wallet',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(hideBalances ? '${currency} ••••••' : '${currency} ${money(balance, conceal: false)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: adjustWalletBalance,
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              visualDensity: VisualDensity.compact,
            ),
            child: Text('Adjust Balance', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  String money(dynamic amount, {bool conceal = true}) {
    if (conceal && hideBalances) return '••••••';
    final locale = numberFormat == '1.234,56' ? 'de_DE' : 'en_US';
    return NumberFormat('#,##0.00', locale).format((amount as num).toDouble());
  }

  String displayDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? (value?.toString() ?? '') : DateFormat(dateFormat).format(parsed);
  }

  String normalizeType(String type) {
    return type.trim().toLowerCase();
  }

  Future<void> _editAdjustmentTransaction(Map<String, dynamic> item) async {
    final controller = TextEditingController(
      text: ((item['balance_delta'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
    );
    final noteController = TextEditingController(text: item['note']?.toString() ?? '');
    DateTime selectedDate = DateTime.tryParse(item['date']?.toString() ?? '') ?? DateTime.now();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: Text('Edit Adjustment'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Balance change (+ / -)',
                  helperText: 'Use + to increase and - to decrease the wallet balance',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Transaction Date'),
                subtitle: Text(DateFormat(dateFormat).format(selectedDate)),
                trailing: Icon(Icons.calendar_month),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    locale: weekStart == 'Sunday' ? const Locale('en', 'US') : const Locale('en', 'GB'),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) updateDialog(() => selectedDate = date);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final delta = double.tryParse(controller.text.trim());
                if (delta == null || !delta.isFinite || delta == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid non-zero balance change.')),
                  );
                  return;
                }
                try {
                  await TransactionsService.updateAdjustmentTransaction(
                    id: item['id'] as int,
                    balanceDelta: delta,
                    note: noteController.text.trim(),
                    date: selectedDate.toIso8601String(),
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              child: Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    noteController.dispose();
    if (result == true) await loadTransactions();
  }

  Future<void> editTransaction(
    Map<String, dynamic> item,
  ) async {
    final wallets = await TransactionsService.getWallets();

    if (!mounted) return;

    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText(context, "No wallets available.", "No wallets available."))),
      );
      return;
    }

    final type = normalizeType(item['type'] as String);
    if (type == 'adjustment') {
      await _editAdjustmentTransaction(item);
      return;
    }

    if (!['income', 'expense', 'transfer'].contains(type)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText(context, "Unknown transaction type.", "Unknown transaction type."))),
      );
      return;
    }

    final categories = type == 'transfer'
        ? <FinanceCategory>[]
        : await CategoryService.getCategories(type);

    if (!mounted) return;

    final amountController = TextEditingController(
      text: money(item['amount'], conceal: false),
    );

    final noteController = TextEditingController(
      text: item['note']?.toString() ?? '',
    );

    // Transfer ki asal received amount ko edit ke waqt bhi mehfooz rakhta hai.
    final destinationAmountController = TextEditingController(
      text: ((item['to_amount'] as num?)?.toDouble() ??
              (item['amount'] as num).toDouble())
          .toStringAsFixed(2),
    );

    int? walletId = item['wallet_id'] as int?;
    int? toWalletId = item['to_wallet_id'] as int?;
    String? category = item['category']?.toString();

    DateTime selectedDate =
        DateTime.tryParse(item['date']?.toString() ?? '') ??
            DateTime.now();

    if (!wallets.any((a) => a['id'] == walletId)) {
      walletId = wallets.first['id'] as int;
    }

    if (type == 'transfer' &&
        !wallets.any((a) => a['id'] == toWalletId)) {
      toWalletId = null;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            final availableDestinations = wallets
                .where((a) => a['id'] != walletId)
                .toList();

            return AlertDialog(
              title: Text(appText(context, 'Edit Transaction', 'لین دین میں ترمیم کریں')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: appText(context, "Amount", "Amount"),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      value: walletId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: appText(context, "Wallet", "Wallet"),
                        border: OutlineInputBorder(),
                      ),
                      items: wallets.map((wallet) {
                        return DropdownMenuItem<int>(
                          value: wallet['id'] as int,
                          child: Text(
                            '${wallet['name']} (${wallet['currency']})',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        updateDialog(() {
                          walletId = value;
                          if (toWalletId == walletId) {
                            toWalletId = null;
                          }
                        });
                      },
                    ),
                    if (type == 'transfer') ...[
                      SizedBox(height: 14),
                      TextField(
                        controller: destinationAmountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: appText(
                            context,
                            'Received Amount',
                            'Received Amount',
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: toWalletId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: appText(context, "Destination Wallet", "Destination Wallet"),
                          border: OutlineInputBorder(),
                        ),
                        items: availableDestinations.map((wallet) {
                          return DropdownMenuItem<int>(
                            value: wallet['id'] as int,
                            child: Text(
                              '${wallet['name']} (${wallet['currency']})',
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          updateDialog(() {
                            toWalletId = value;
                          });
                        },
                      ),
                    ],
                    if (type != 'transfer') ...[
                      SizedBox(height: 14),
                      DropdownButtonFormField<String?>(
                        value: categories.any(
                          (c) => c.name == category,
                        )
                            ? category
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: appText(context, "Category", "Category"),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(appText(context, "No category", "No category")),
                          ),
                          ...categories.map((category) {
                            return DropdownMenuItem<String?>(
                              value: category.name,
                              child: Text(
                                '${category.icon} ${category.name}',
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          updateDialog(() {
                            category = value;
                          });
                        },
                      ),
                    ],
                    SizedBox(height: 14),
                    TextField(
                      controller: noteController,
                      decoration: InputDecoration(
                        labelText: appText(context, "Description", "Description"),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 14),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(appText(context, 'Transaction Date', 'لین دین کی تاریخ')),
                      subtitle: Text(
                        DateFormat(dateFormat).format(selectedDate),
                      ),
                      trailing: Icon(Icons.calendar_month),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          locale: weekStart == 'Sunday' ? const Locale('en', 'US') : const Locale('en', 'GB'),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );

                        if (date != null) {
                          updateDialog(() {
                            selectedDate = date;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(
                      amountController.text.trim(),
                    );

                    if (amount == null || !amount.isFinite || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(appText(context, 'Enter a valid amount.', 'درست رقم درج کریں۔')),
                        ),
                      );
                      return;
                    }

                    if (walletId == null) return;

                    final destinationAmount = type == 'transfer'
                        ? double.tryParse(destinationAmountController.text.trim())
                        : null;

                    if (type == 'transfer' &&
                        (destinationAmount == null ||
                            !destinationAmount.isFinite ||
                            destinationAmount <= 0)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(appText(
                            context,
                            'Enter a valid received amount.',
                            'Enter a valid received amount.',
                          )),
                        ),
                      );
                      return;
                    }

                    if (type == 'transfer' && toWalletId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(appText(context, 'Select a destination wallet.', 'رقم وصول کرنے والا اکاؤنٹ منتخب کریں۔')),
                        ),
                      );
                      return;
                    }

                    try {
                      await TransactionsService.updateTransaction(
                        id: item['id'] as int,
                        type: type,
                        amount: amount,
                        walletId: walletId!,
                        toWalletId:
                            type == 'transfer' ? toWalletId : null,
                        toAmount: destinationAmount,
                        exchangeRate: type == 'transfer'
                            ? destinationAmount! / amount
                            : null,
                        category:
                            type == 'transfer' ? null : category,
                        note: noteController.text.trim(),
                        date: selectedDate.toIso8601String(),
                      );
                      if (await GeneralPreferences.instance.hapticFeedback) {
                        await HapticFeedback.selectionClick();
                      }

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
                  child: Text(appText(context, 'Save Changes', 'تبدیلیاں محفوظ کریں')),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
    destinationAmountController.dispose();
    noteController.dispose();

    if (result == true) {
      await loadTransactions();
    }
  }

  Future<void> deleteTransaction(
    Map<String, dynamic> item,
  ) async {
    await SoundSettingsService.instance.play('delete_warning');
    final requireConfirmation = await GeneralPreferences.instance.deleteConfirmation;
    final confirmed = requireConfirmation ? await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText(context, 'Delete Transaction?', 'لین دین حذف کریں؟')),
        content: Text(appText(context, "This transaction will be deleted and its effect on wallet balances will be reversed.", "یہ لین دین حذف ہوگا اور اکاؤنٹ بیلنس پر اس کا اثر واپس ہوگا۔"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(appText(context, "Delete", "Delete")),
          ),
        ],
      ),
    ) : true;

    if (confirmed == true) {
      try {
        await TransactionsService.deleteTransaction(
          item['id'] as int,
        );
        await SoundSettingsService.instance.play('delete_success');
        if (await GeneralPreferences.instance.hapticFeedback) {
          await HapticFeedback.selectionClick();
        }
        await loadTransactions();
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredTransactions = transactions.where((item) {
      final type = normalizeType(item['type']?.toString() ?? '');
      if (selectedFilter == 'others') {
        return !['income', 'expense', 'transfer'].contains(type);
      }
      return selectedFilter == 'all' || type == selectedFilter;
    }).toList()
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(1970);
        final bDate = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

    // Show a compact first page, then paginate the complete history in View All.
    const transactionsPerPage = 10;
    final pageCount = (filteredTransactions.length / transactionsPerPage).ceil();
    final safePage = currentPage.clamp(0, pageCount > 0 ? pageCount - 1 : 0).toInt();
    final pageTransactions = filteredTransactions
        .skip((widget.showAllTransactions ? safePage : 0) * transactionsPerPage)
        .take(transactionsPerPage)
        .toList();
    final groupedByDate = <String, List<Map<String, dynamic>>>{};
    for (final item in pageTransactions) {
      final parsed = DateTime.tryParse(item['date']?.toString() ?? '');
      final key = parsed == null ? 'Unknown date' : DateFormat('yyyy-MM-dd').format(parsed);
      groupedByDate.putIfAbsent(key, () => []).add(item);
    }
    final displayRows = <Map<String, dynamic>>[];
    for (final entry in groupedByDate.entries) {
      // Daily net is calculated independently per currency. Income adds,
      // expenses subtract; transfers and balance adjustments are excluded
      // because they are not income/expense activity.
      final dailyNetByCurrency = <String, double>{};
      for (final item in entry.value) {
        final type = normalizeType(item['type']?.toString() ?? '');
        if (item['is_scheduled'] == true || (type != 'income' && type != 'expense')) continue;
        final currency = item['wallet_currency']?.toString().trim().toUpperCase() ?? '';
        if (currency.isEmpty) continue;
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;
        dailyNetByCurrency.update(
          currency,
          (current) => current + (type == 'income' ? amount : -amount),
          ifAbsent: () => type == 'income' ? amount : -amount,
        );
      }
      displayRows.add({
        'dateHeader': entry.key,
        'dailyNetByCurrency': dailyNetByCurrency,
      });
      for (final item in entry.value) {
        displayRows.add({'transaction': item});
      }
    }

    final filters = [
      ('all', 'All'),
      ('income', 'Income'),
      ('expense', 'Expense'),
      ('transfer', 'Transfer'),
      ('others', 'Others'),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: widget.walletId == null
            ? GeneralPreferences.instance.personalizedHeaderTitle(
                context,
                Text(
                  appText(context, "Transactions", "Transactions"),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                ),
              )
            : Text(
                widget.walletName ?? appText(context, "Transactions", "Transactions"),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
              ),
        actions: buildSharedAppBarActions(context),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildWalletSummaryCard(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      ...filters.asMap().entries.map((entry) {
                        final filter = entry.value;
                        final selected = selectedFilter == filter.$1;
                        final chipFlex = switch (filter.$1) {
                          'all' => 5,
                          'income' => 8,
                          'expense' => 8,
                          'transfer' => 8,
                          _ => 7,
                        };
                        return Expanded(
                          flex: chipFlex,
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: entry.key == filters.length - 1 ? 0 : 3,
                            ),
                            child: ChoiceChip(
                              label: SizedBox(
                                width: double.infinity,
                                child: Text(
                                  filter.$2,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                              labelPadding: EdgeInsets.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              selected: selected,
                              onSelected: (_) => setState(() {
                                selectedFilter = filter.$1;
                                currentPage = 0;
                              }),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).hintColor,
                              ),
                              selectedColor: Theme.of(context).colorScheme.primary,
                              backgroundColor: Theme.of(context).cardColor,
                              side: BorderSide(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outlineVariant,
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              showCheckmark: false,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 3),
                      Expanded(
                        flex: 11,
                        child: ActionChip(
                          label: SizedBox(
                            width: double.infinity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.settings_outlined,
                                  size: 14,
                                  color: Theme.of(context).hintColor,
                                ),
                                SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    'Recurring',
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          labelPadding: EdgeInsets.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const RecurringTransactionsScreen(),
                              ),
                            ).then((_) => loadTransactions());
                          },
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor,
                          ),
                          backgroundColor: Theme.of(context).cardColor,
                          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: filteredTransactions.isEmpty
                      ? RefreshIndicator(
                          onRefresh: loadTransactions,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                            children: [
                              SizedBox(
                                height: 260,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.receipt_long_outlined,
                                        size: 52,
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        appText(context, "No transactions available", "No transactions available"),
                                        style: TextStyle(
                                          color: Theme.of(context).hintColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text('Pull down to refresh', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: loadTransactions,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                            itemCount: displayRows.length + 1,
                            itemBuilder: (context, index) {
                              if (index == displayRows.length) {
                                if (!widget.showAllTransactions && filteredTransactions.length > transactionsPerPage) {
                                  return Align(
                                    alignment: Alignment.center,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                                          builder: (_) => TransactionsScreen(
                                            walletId: widget.walletId,
                                            walletName: widget.walletName,
                                            showAllTransactions: true,
                                          ),
                                        )),
                                        icon: Icon(Icons.view_list_rounded),
                                        label: Text('View All Transactions'),
                                      ),
                                    ),
                                  );
                                }
                                if (widget.showAllTransactions && pageCount > 1) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        OutlinedButton(
                                          onPressed: safePage > 0 ? () => setState(() => currentPage--) : null,
                                          child: Text('Previous'),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          child: Text('Page ${safePage + 1} of $pageCount'),
                                        ),
                                        OutlinedButton(
                                          onPressed: safePage < pageCount - 1 ? () => setState(() => currentPage++) : null,
                                          child: Text('Next'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return const SizedBox(height: 8);
                              }
                              final row = displayRows[index];
                              if (row.containsKey('dateHeader')) {
                                final rawDate = row['dateHeader'] as String;
                                final parsedHeader = DateTime.tryParse(rawDate);
                                final dailyNet = row['dailyNetByCurrency'] as Map<String, double>? ?? const {};
                                final netEntries = dailyNet.entries.toList()
                                  ..sort((a, b) => a.key.compareTo(b.key));
                                final dayNumber = parsedHeader == null
                                    ? '—'
                                    : DateFormat('dd').format(parsedHeader);
                                final dayName = parsedHeader == null
                                    ? 'Unknown day'
                                    : DateFormat('EEEE').format(parsedHeader);
                                final monthYear = parsedHeader == null
                                    ? rawDate
                                    : DateFormat('MMM yyyy').format(parsedHeader);
                                return Container(
                                  margin: const EdgeInsets.fromLTRB(0, 12, 0, 9),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        dayNumber,
                                        style: TextStyle(
                                          fontSize: 34,
                                          height: 1,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -1.2,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              dayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.15,
                                                fontWeight: FontWeight.w800,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              monthYear,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                height: 1.1,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context).hintColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (netEntries.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: netEntries.map((entry) {
                                            final net = entry.value;
                                            final netColor = net > 0
                                                ? Theme.of(context).colorScheme.secondary
                                                : net < 0
                                                    ? Theme.of(context).colorScheme.error
                                                    : Theme.of(context).hintColor;
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 1),
                                              child: Text(
                                                hideBalances
                                                    ? '${entry.key} ••••••'
                                                    : '${net > 0 ? '+' : net < 0 ? '−' : ''}${entry.key} ${money(net.abs())}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  color: netColor,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }
                              final item = row['transaction'] as Map<String, dynamic>;
                              final type = normalizeType(item['type']?.toString() ?? '');
                              final isIncome = type == 'income';
                              final isExpense = type == 'expense';
                              final isTransfer = type == 'transfer';
                              final isCommittee = type == 'committee';
                              final isSourceRecord = item['source_record'] == true;
                              final isAssetRecord = type == 'asset';
                              final isLoanRecord = type == 'loan';
                              final isCommitteeTransfer = item['category']?.toString() == 'Committee Transfer';
                              final isAdjustment = type == 'adjustment';
                              final color = isAssetRecord
                                  ? Theme.of(context).colorScheme.tertiary
                                  : isLoanRecord
                                      ? Theme.of(context).colorScheme.tertiary
                                      : isCommittee
                                  ? Theme.of(context).colorScheme.secondary
                                  : isAdjustment
                                      ? Theme.of(context).colorScheme.tertiary
                                      : isIncome
                                  ? Theme.of(context).colorScheme.secondary
                                  : isExpense
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.primary;
                              final icon = isAssetRecord
                                  ? Icons.real_estate_agent_outlined
                                  : isLoanRecord
                                      ? Icons.handshake_outlined
                                      : isCommittee
                                  ? Icons.groups_2_outlined
                                  : isIncome
                                  ? Icons.south_west_rounded
                                  : isExpense
                                      ? Icons.north_east_rounded
                                      : isAdjustment
                                          ? Icons.tune_rounded
                                          : Icons.swap_horiz_rounded;
                              final title = isCommittee
                                  ? ((item['note']?.toString().trim().isNotEmpty ?? false)
                                      ? item['note'].toString().trim()
                                      : 'Committee')
                                  : isAdjustment
                                      ? 'Adjustment'
                                      : (item['note']?.toString().trim().isNotEmpty ?? false)
                                      ? item['note'].toString().trim()
                                      : isIncome
                                          ? 'Income'
                                          : isExpense
                                              ? 'Expense'
                                              : 'Transfer';
                              final category = item['category']?.toString().trim() ?? '';
                              final currency = item['wallet_currency']?.toString() ?? '';
                              final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
                              final originalAmount = (item['original_amount'] as num?)?.toDouble();
                              final originalCurrency = item['original_currency']?.toString() ?? '';
                              final exchangeRate = (item['exchange_rate'] as num?)?.toDouble();
                              final showOriginalAmount = isLoanRecord && originalAmount != null &&
                                  originalCurrency.isNotEmpty && originalCurrency.toUpperCase() != currency.toUpperCase();
                              final fee = (item['transfer_fee'] as num?)?.toDouble() ?? 0.0;
                              final parsedDate = DateTime.tryParse(item['date']?.toString() ?? '');
                              final dateLabel = parsedDate == null
                                   ? displayDate(item['date'])
                                   : DateFormat(item['is_scheduled'] == true ? 'dd MMM yyyy' : 'dd MMM yyyy  •  hh:mm a').format(parsedDate);

                              final isScheduled = item['is_scheduled'] == true;
                              final isReadOnlySource = isScheduled || isSourceRecord;
                              return InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: isReadOnlySource ? null : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TransactionDetailScreen(
                                        transaction: item,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE9EFEB)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF183D2D).withValues(alpha: 0.035),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 8, 5, 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.11),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(icon, color: color, size: 21),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              [
                                                if (isSourceRecord) (category.isEmpty ? (isAssetRecord ? 'Asset' : 'Loan') : category),
                                                if (!isScheduled && !isSourceRecord) isAdjustment ? 'Balance Adjustment' : (isTransfer ? 'Transfer' : (category.isEmpty ? 'No category' : category)),
                                                                                                 if (isScheduled && item['frequency'] != null) item['frequency'].toString(),
                                                 if (isTransfer && fee > 0) 'Fee: $currency ${money(fee)}',
                                                 if (isAssetRecord && item['payment_type'] != null) 'Payment: ${item['payment_type']}',
                                              ].join('  •  '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Theme.of(context).hintColor,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            if (showOriginalAmount) ...[
                                              Text(
                                                'Loan amount: $originalCurrency ${money(originalAmount)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor),
                                              ),
                                              if (exchangeRate != null && exchangeRate > 0)
                                                Text(
                                                  'Rate: 1 $originalCurrency = $currency ${exchangeRate.toStringAsFixed(4)}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 9.5, color: Theme.of(context).hintColor),
                                                ),
                                              const SizedBox(height: 2),
                                            ],
                                            Text(
                                              dateLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: Color(0xFF9AA49F),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${isIncome ? '+' : isExpense ? '-' : isAdjustment ? (((item['balance_delta'] as num?)?.toDouble() ?? 0) >= 0 ? '+' : '-') : isCommittee ? ((item['category']?.toString().toLowerCase().contains('installment') ?? false) ? '+' : '-') : '⇄'} $currency ${money(isAdjustment ? ((item['balance_delta'] as num?)?.toDouble().abs() ?? amount) : amount)}',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: color,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          if (isScheduled)
                                             Container(
                                               padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                               decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                                               child: Text('Scheduled', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 9.5, fontWeight: FontWeight.w800)),
                                             )
                                           else if (isSourceRecord)
                                            const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF9AA49F)))
                                           else
                                           PopupMenuButton<String>(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 150),
                                            iconSize: 19,
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(30, 28),
                                              maximumSize: const Size(30, 28),
                                              padding: EdgeInsets.zero,
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            icon: Icon(
                                              Icons.more_horiz,
                                              color: Color(0xFF89958E),
                                              size: 19,
                                            ),
                                            onSelected: (value) {
                                              if (value == 'edit') {
                                                editTransaction(item);
                                              } else if (value == 'delete') {
                                                deleteTransaction(item);
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              if (!isCommittee && !isCommitteeTransfer) PopupMenuItem(
                                                value: 'edit',
                                                child: Text(appText(context, 'Edit', 'ترمیم کریں')),
                                              ),
                                              if (!isCommittee && !isCommitteeTransfer) PopupMenuItem(
                                                value: 'delete',
                                                child: Text(appText(context, 'Delete', 'Delete')),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}


class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.transaction});

  final Map<String, dynamic> transaction;

  @override
  Widget build(BuildContext context) {
    final type = transaction['type']?.toString() ?? 'Transaction';
    final normalized = type.toLowerCase();
    final isIncome = normalized == 'income';
    final isExpense = normalized == 'expense';
    final isTransfer = normalized == 'transfer';
    final isAdjustment = normalized == 'adjustment';
    final isCommittee = normalized == 'committee';
    final isCommitteeTransfer = transaction['category']?.toString() == 'Committee Transfer';
    final color = isCommittee
        ? Theme.of(context).colorScheme.secondary
        : isAdjustment
        ? Theme.of(context).colorScheme.tertiary
        : isIncome
        ? Theme.of(context).colorScheme.secondary
        : isExpense
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary;
    final icon = isCommittee
        ? Icons.groups_2_outlined
        : isIncome
        ? Icons.south_west_rounded
        : isExpense
            ? Icons.north_east_rounded
            : isAdjustment
                ? Icons.tune_rounded
                : Icons.swap_horiz_rounded;
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final toAmount = (transaction['to_amount'] as num?)?.toDouble();
    final currency = transaction['wallet_currency']?.toString() ?? '';
    final date = DateTime.tryParse(transaction['date']?.toString() ?? '');
    final note = transaction['note']?.toString().trim() ?? '';
    final category = transaction['category']?.toString().trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context, 'Transaction Details', 'Transaction Details')),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: TransactionsService.getWallets(),
        builder: (context, snapshot) {
          final wallets = snapshot.data ?? const <Map<String, dynamic>>[];
          String walletName(dynamic id) {
            final match = wallets.where((wallet) => wallet['id'] == id);
            return match.isEmpty ? 'Wallet #$id' : match.first['name'].toString();
          }

          final sourceId = transaction['wallet_id'];
          final details = <Widget>[
            _detailRow(context, 'Transaction ID', '#${transaction['id']}'),
            _detailRow(context, 'Type', type),
            _detailRow(context, 'Date & Time', date == null
                ? (transaction['date']?.toString() ?? '—')
                : DateFormat('dd MMM yyyy, hh:mm a').format(date)),
            _detailRow(context, 'Wallet', walletName(sourceId)),
            if (isCommitteeTransfer)
              _detailRow(context, 'Transfer link', (transaction['balance_delta'] as num?)?.toDouble() != null &&
                ((transaction['balance_delta'] as num).toDouble() < 0)
                  ? 'Personal Wallet → Committee Ledger'
                  : 'Committee Ledger → Personal Wallet'),
            _detailRow(context, 'Category', category.isEmpty ? (isTransfer ? 'Transfer' : 'No category') : category),
            _detailRow(context, 'Description / Note', note.isEmpty ? '—' : note),
            if (transaction['original_amount'] is num && (transaction['original_currency']?.toString().isNotEmpty ?? false))
              _detailRow(context, 'Original loan amount',
                '${transaction['original_currency']} ${((transaction['original_amount'] as num).toDouble()).toStringAsFixed(2)}'),
            if (transaction['exchange_rate'] is num && (transaction['original_currency']?.toString().toUpperCase() != currency.toUpperCase()))
              _detailRow(context, 'Applied rate',
                '1 ${transaction['original_currency']} = $currency ${((transaction['exchange_rate'] as num).toDouble()).toStringAsFixed(4)}'),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.13), color.withValues(alpha: 0.045)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 21),
                    ),
                    const SizedBox(height: 4),
                    Text(type, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '${isIncome ? '+' : isExpense ? '-' : (isAdjustment || isCommitteeTransfer) ? (((transaction['balance_delta'] as num?)?.toDouble() ?? 0) >= 0 ? '+' : '-') : ''} $currency ${(isAdjustment || isCommitteeTransfer ? ((transaction['balance_delta'] as num?)?.toDouble().abs() ?? amount) : amount).toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                    ),
                    if (isTransfer && toAmount != null) ...[
                      const SizedBox(height: 2),
                      Text('Received: ${toAmount.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 12, color: Color(0xFF65736B))),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _detailSection(
                context,
                title: 'Transaction Information',
                icon: Icons.receipt_long_outlined,
                children: details,
              ),
              const SizedBox(height: 12),
              AttachmentSection(
                ownerType: 'transaction',
                ownerId: transaction['id'] as int,
                readOnly: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE8EEE9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(value, textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
