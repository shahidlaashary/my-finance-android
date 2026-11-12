
import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/app_strings.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';

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
        SnackBar(content: Text(AppStrings.translate(context, 'Error: $e'))),
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
        const SnackBar(content: Text(AppStrings.translate(context, 'No wallets available.'))),
      );
      return;
    }

    final type = normalizeType(item['type'] as String);

    if (!['income', 'expense', 'transfer'].contains(type)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.translate(context, 'Unknown transaction type.'))),
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
              title: Text(AppStrings.translate(context, 'Edit Transaction')),
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
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      value: walletId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        border: OutlineInputBorder(),
                      ),
                      items: wallets.map((account) {
                        return DropdownMenuItem<int>(
                          value: account['id'] as int,
                          child: Text(AppStrings.translate(context, '${account[')name']} (${account['currency']})',
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
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: toWalletId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Destination Account',
                          border: OutlineInputBorder(),
                        ),
                        items: availableDestinations.map((account) {
                          return DropdownMenuItem<int>(
                            value: account['id'] as int,
                            child: Text(AppStrings.translate(context, '${account[')name']} (${account['currency']})',
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
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String?>(
                        value: categories.any(
                          (c) => c.name == category,
                        )
                            ? category
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(AppStrings.translate(context, 'No category')),
                          ),
                          ...categories.map((category) {
                            return DropdownMenuItem<String?>(
                              value: category.name,
                              child: Text(AppStrings.translate(context, '${category.icon} ${category.name}'),
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
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(AppStrings.translate(context, 'Transaction Date')),
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
                  child: Text(AppStrings.translate(context, 'Cancel')),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(
                      amountController.text.trim(),
                    );

                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(AppStrings.translate(context, 'Enter a valid amount.')),
                        ),
                      );
                      return;
                    }

                    if (walletId == null) return;

                    if (type == 'transfer' && toWalletId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(AppStrings.translate(context, 'Select a destination account.')),
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
                          SnackBar(content: Text(AppStrings.translate(context, '$e'))),
                        );
                      }
                    }
                  },
                  child: Text(AppStrings.translate(context, 'Save Changes')),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
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
        title: Text(AppStrings.translate(context, 'Delete Transaction?')),
        content: Text(AppStrings.translate(context, 'This transaction will be deleted and its effect on ')
          'account balances will be reversed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.translate(context, 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.translate(context, 'Delete')),
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
          SnackBar(content: Text(AppStrings.translate(context, '$e'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202A26),
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: Text(AppStrings.translate(context, 'Transactions'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF202A26))),
        actions: buildSharedAppBarActions(context),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : transactions.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 55, color: Color(0xFF147D59)),
                      SizedBox(height: 12),
                      Text(AppStrings.translate(context, 'No transactions available'), style: TextStyle(color: Color(0xFF7B8781))),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadTransactions,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final item = transactions[index];

                      final type = normalizeType(
                        item['type'] as String,
                      );
                      final transferFee =
                          (item['transfer_fee'] as num?)?.toDouble() ?? 0.0;
                      final transferAmount =
                          (item['amount'] as num?)?.toDouble() ?? 0.0;
                      final walletCurrency =
                          item['wallet_currency']?.toString() ?? '';

                      final isIncome = type == 'income';
                      final isExpense = type == 'expense';
                      final isTransfer = type == 'transfer';

                      final color = isIncome
                          ? Colors.green
                          : isExpense
                              ? Colors.red
                              : Colors.blue;

                      final title = isIncome
                          ? 'Income'
                          : isExpense
                              ? 'Expense'
                              : 'Transfer';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                color.withValues(alpha: 0.12),
                            child: Icon(
                              isIncome
                                  ? Icons.arrow_downward
                                  : isExpense
                                      ? Icons.arrow_upward
                                      : Icons.swap_horiz,
                              color: color,
                            ),
                          ),
                          title: Text(title),
                          subtitle: Text(
                            [
                              item['category']?.toString() ??
                                  'No category',
                              if (isTransfer && transferFee > 0)
                                'Transfer Amount: ${walletCurrency} ${money(transferAmount)}',
                              if (isTransfer && transferFee > 0)
                                'Transfer Fee: ${walletCurrency} ${money(transferFee)}',
                              if (isTransfer && transferFee > 0)
                                'Total Deducted: ${walletCurrency} ${money(transferAmount + transferFee)}',
                              item['note']?.toString() ?? '',
                              displayDate(item['date']),
                            ].where((s) => s.isNotEmpty).join(' • '),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                editTransaction(item);
                              } else if (value == 'delete') {
                                deleteTransaction(item);
                              } else if (value == 'attachments') {
                                showAttachments(item);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'attachments',
                                child: Row(
                                  children: [
                                    Icon(Icons.attach_file),
                                    SizedBox(width: 10),
                                    Text(AppStrings.translate(context, 'Attachments')),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(AppStrings.translate(context, 'Edit')),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(AppStrings.translate(context, 'Delete')),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
