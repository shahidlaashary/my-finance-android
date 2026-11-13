
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/finance/models/finance_category.dart';
import 'package:my_finance/features/finance/services/category_service.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Map<String, dynamic>> transactions = [];
  bool loading = true;
  bool hideBalances = false;
  String numberFormat = '1,234.56';
  String dateFormat = 'dd/MM/yyyy';
  String weekStart = 'Monday';
  String selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    loadTransactions();
  }

  void _onPreferencesChanged() {
    if (mounted) loadTransactions();
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  Future<void> loadTransactions() async {
    if (mounted) setState(() => loading = true);

    try {
      final hide = await GeneralPreferences.instance.hideBalances;
      final number = await GeneralPreferences.instance.numberFormat;
      final date = await GeneralPreferences.instance.dateFormat;
      final week = await GeneralPreferences.instance.weekStart;
      final result = await TransactionsService.getTransactions();

      if (!mounted) return;

      setState(() {
        transactions = result;
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

  Future<void> showAttachments(Map<String, dynamic> item) async {
    final transactionId = item['id'] as int;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: SingleChildScrollView(
                child: AttachmentSection(
                  ownerType: 'transaction',
                  ownerId: transactionId,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> editTransaction(
    Map<String, dynamic> item,
  ) async {
    final wallets = await TransactionsService.getAccounts();

    if (!mounted) return;

    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText(context, "No wallets available.", "No wallets available."))),
      );
      return;
    }

    final type = normalizeType(item['type'] as String);

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
                        labelText: appText(context, "Account", "Account"),
                        border: OutlineInputBorder(),
                      ),
                      items: wallets.map((account) {
                        return DropdownMenuItem<int>(
                          value: account['id'] as int,
                          child: Text(
                            '${account['name']} (${account['currency']})',
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
                          labelText: appText(context, "Destination Account", "Destination Account"),
                          border: OutlineInputBorder(),
                        ),
                        items: availableDestinations.map((account) {
                          return DropdownMenuItem<int>(
                            value: account['id'] as int,
                            child: Text(
                              '${account['name']} (${account['currency']})',
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
                      trailing: const Icon(Icons.calendar_month),
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
                          content: Text(appText(context, 'Select a destination account.', 'رقم وصول کرنے والا اکاؤنٹ منتخب کریں۔')),
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
    final requireConfirmation = await GeneralPreferences.instance.deleteConfirmation;
    final confirmed = requireConfirmation ? await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText(context, 'Delete Transaction?', 'لین دین حذف کریں؟')),
        content: Text(appText(context, "This transaction will be deleted and its effect on account balances will be reversed.", "یہ لین دین حذف ہوگا اور اکاؤنٹ بیلنس پر اس کا اثر واپس ہوگا۔"),
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
      return selectedFilter == 'all' || type == selectedFilter;
    }).toList();

    final filters = [
      ('all', 'All'),
      ('income', 'Income'),
      ('expense', 'Expense'),
      ('transfer', 'Transfer'),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202A26),
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: Text(
          appText(context, "Transactions", "Transactions"),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF202A26),
          ),
        ),
        actions: buildSharedAppBarActions(context),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final filter = filters[index];
                      final selected = selectedFilter == filter.$1;
                      return ChoiceChip(
                        label: Text(filter.$2),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => selectedFilter = filter.$1),
                        backgroundColor: const Color(0xFFF2F5F3),
                        selectedColor: const Color(0xFF147D59),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : const Color(0xFF52615A),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filteredTransactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 52,
                                color: const Color(0xFF147D59).withValues(alpha: 0.65),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                transactions.isEmpty
                                    ? appText(context, "No transactions available", "No transactions available")
                                    : 'No ${selectedFilter == 'all' ? '' : selectedFilter} transactions',
                                style: const TextStyle(
                                  color: Color(0xFF7B8781),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: loadTransactions,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                            itemCount: filteredTransactions.length,
                            itemBuilder: (context, index) {
                              final item = filteredTransactions[index];
                              final type = normalizeType(item['type']?.toString() ?? '');
                              final isIncome = type == 'income';
                              final isExpense = type == 'expense';
                              final isTransfer = type == 'transfer';
                              final color = isIncome
                                  ? const Color(0xFF159B65)
                                  : isExpense
                                      ? const Color(0xFFE45B5B)
                                      : const Color(0xFF3979C6);
                              final icon = isIncome
                                  ? Icons.south_west_rounded
                                  : isExpense
                                      ? Icons.north_east_rounded
                                      : Icons.swap_horiz_rounded;
                              final title = (item['note']?.toString().trim().isNotEmpty ?? false)
                                  ? item['note'].toString().trim()
                                  : isIncome
                                      ? 'Income'
                                      : isExpense
                                          ? 'Expense'
                                          : 'Transfer';
                              final category = item['category']?.toString().trim() ?? '';
                              final currency = item['wallet_currency']?.toString() ?? '';
                              final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
                              final fee = (item['transfer_fee'] as num?)?.toDouble() ?? 0.0;
                              final parsedDate = DateTime.tryParse(item['date']?.toString() ?? '');
                              final dateLabel = parsedDate == null
                                  ? displayDate(item['date'])
                                  : DateFormat('dd MMM yyyy  •  hh:mm a').format(parsedDate);

                              return InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
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
                                  color: Colors.white,
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
                                  padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.11),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(icon, color: color, size: 23),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF25332C),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              [
                                                isTransfer ? 'Transfer' : (category.isEmpty ? 'No category' : category),
                                                if (isTransfer && fee > 0) 'Fee: $currency ${money(fee)}',
                                              ].join('  •  '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: Color(0xFF7B8781),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              dateLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                color: Color(0xFF9AA49F),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${isIncome ? '+' : isExpense ? '-' : '⇄'} $currency ${money(amount)}',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: color,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          PopupMenuButton<String>(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 150),
                                            icon: const Icon(
                                              Icons.more_horiz,
                                              color: Color(0xFF89958E),
                                              size: 21,
                                            ),
                                            onSelected: (value) {
                                              if (value == 'edit') {
                                                editTransaction(item);
                                              } else if (value == 'delete') {
                                                deleteTransaction(item);
                                              } else if (value == 'attachments') {
                                                showAttachments(item);
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              PopupMenuItem(
                                                value: 'attachments',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.attach_file, size: 19),
                                                    const SizedBox(width: 10),
                                                    Text(appText(context, 'Attachments', 'منسلک فائلیں')),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'edit',
                                                child: Text(appText(context, 'Edit', 'ترمیم کریں')),
                                              ),
                                              PopupMenuItem(
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
    final color = isIncome
        ? const Color(0xFF159B65)
        : isExpense
            ? const Color(0xFFE45B5B)
            : const Color(0xFF3979C6);
    final icon = isIncome
        ? Icons.south_west_rounded
        : isExpense
            ? Icons.north_east_rounded
            : Icons.swap_horiz_rounded;
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final fee = (transaction['transfer_fee'] as num?)?.toDouble() ?? 0;
    final toAmount = (transaction['to_amount'] as num?)?.toDouble();
    final exchangeRate = (transaction['exchange_rate'] as num?)?.toDouble();
    final currency = transaction['wallet_currency']?.toString() ?? '';
    final date = DateTime.tryParse(transaction['date']?.toString() ?? '');
    final note = transaction['note']?.toString().trim() ?? '';
    final category = transaction['category']?.toString().trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context, 'Transaction Details', 'Transaction Details')),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: TransactionsService.getAccounts(),
        builder: (context, snapshot) {
          final wallets = snapshot.data ?? const <Map<String, dynamic>>[];
          String walletName(dynamic id) {
            final match = wallets.where((wallet) => wallet['id'] == id);
            return match.isEmpty ? 'Account #$id' : match.first['name'].toString();
          }

          final sourceId = transaction['wallet_id'];
          final destinationId = transaction['to_wallet_id'];
          final details = <Widget>[
            _detailRow('Transaction ID', '#${transaction['id']}'),
            _detailRow('Type', type),
            _detailRow('Date & Time', date == null
                ? (transaction['date']?.toString() ?? '—')
                : DateFormat('dd MMM yyyy, hh:mm a').format(date)),
            _detailRow('Account', walletName(sourceId)),
            if (isTransfer) _detailRow('Destination Account', walletName(destinationId)),
            if (!isTransfer) _detailRow('Category', category.isEmpty ? 'No category' : category),
            if (isTransfer && toAmount != null)
              _detailRow('Amount Received', '${transaction['to_currency'] ?? ''} ${toAmount.toStringAsFixed(2)}'),
            if (isTransfer && exchangeRate != null)
              _detailRow('Exchange Rate', exchangeRate.toStringAsFixed(6)),
            if (isTransfer) _detailRow('Transfer Fee', '$currency ${fee.toStringAsFixed(2)}'),
            _detailRow('Description / Note', note.isEmpty ? '—' : note),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
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
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const SizedBox(height: 12),
                    Text(type, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(
                      '${isIncome ? '+' : isExpense ? '-' : ''} $currency ${amount.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: color),
                    ),
                    if (isTransfer && toAmount != null) ...[
                      const SizedBox(height: 5),
                      Text('Received: ${toAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF65736B))),
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
              const SizedBox(height: 18),
              _detailSection(
                context,
                title: 'Attachments',
                icon: Icons.attach_file_rounded,
                children: [
                  AttachmentSection(
                    ownerType: 'transaction',
                    ownerId: transaction['id'] as int,
                  ),
                ],
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
            Icon(icon, size: 19, color: const Color(0xFF147D59)),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7B8781))),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(value, textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
