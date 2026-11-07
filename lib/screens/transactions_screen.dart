
import 'package:flutter/material.dart';

import '../models/finance_category.dart';
import '../services/category_service.dart';
import '../services/transaction_service.dart';
import '../widgets/attachment_section.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Map<String, dynamic>> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTransactions();
  }

  Future<void> loadTransactions() async {
    if (mounted) setState(() => loading = true);

    try {
      final result = await TransactionService.getTransactions();

      if (!mounted) return;

      setState(() {
        transactions = result;
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

  String money(dynamic amount) {
    return (amount as num).toStringAsFixed(2);
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
    final accounts = await TransactionService.getAccounts();

    if (!mounted) return;

    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No accounts available.')),
      );
      return;
    }

    final type = normalizeType(item['type'] as String);

    if (!['income', 'expense', 'transfer'].contains(type)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unknown transaction type.')),
      );
      return;
    }

    final categories = type == 'transfer'
        ? <FinanceCategory>[]
        : await CategoryService.getCategories(type);

    if (!mounted) return;

    final amountController = TextEditingController(
      text: money(item['amount']),
    );

    final noteController = TextEditingController(
      text: item['note']?.toString() ?? '',
    );

    int? accountId = item['account_id'] as int?;
    int? toAccountId = item['to_account_id'] as int?;
    int? categoryId = item['category_id'] as int?;

    DateTime selectedDate =
        DateTime.tryParse(item['date']?.toString() ?? '') ??
            DateTime.now();

    if (!accounts.any((a) => a['id'] == accountId)) {
      accountId = accounts.first['id'] as int;
    }

    if (type == 'transfer' &&
        !accounts.any((a) => a['id'] == toAccountId)) {
      toAccountId = null;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            final availableDestinations = accounts
                .where((a) => a['id'] != accountId)
                .toList();

            return AlertDialog(
              title: const Text('Edit Transaction'),
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
                      value: accountId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        border: OutlineInputBorder(),
                      ),
                      items: accounts.map((account) {
                        return DropdownMenuItem<int>(
                          value: account['id'] as int,
                          child: Text(
                            '${account['name']} (${account['currency']})',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        updateDialog(() {
                          accountId = value;
                          if (toAccountId == accountId) {
                            toAccountId = null;
                          }
                        });
                      },
                    ),
                    if (type == 'transfer') ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: toAccountId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Destination Account',
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
                            toAccountId = value;
                          });
                        },
                      ),
                    ],
                    if (type != 'transfer') ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int?>(
                        value: categories.any(
                          (c) => c.id == categoryId,
                        )
                            ? categoryId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('No category'),
                          ),
                          ...categories.map((category) {
                            return DropdownMenuItem<int?>(
                              value: category.id,
                              child: Text(
                                '${category.icon} ${category.name}',
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          updateDialog(() {
                            categoryId = value;
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
                      title: const Text('Transaction Date'),
                      subtitle: Text(
                        '${selectedDate.year}-'
                        '${selectedDate.month.toString().padLeft(2, '0')}-'
                        '${selectedDate.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
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
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(
                      amountController.text.trim(),
                    );

                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a valid amount.'),
                        ),
                      );
                      return;
                    }

                    if (accountId == null) return;

                    if (type == 'transfer' && toAccountId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Select a destination account.'),
                        ),
                      );
                      return;
                    }

                    try {
                      await TransactionService.updateTransaction(
                        id: item['id'] as int,
                        type: type,
                        amount: amount,
                        accountId: accountId!,
                        toAccountId:
                            type == 'transfer' ? toAccountId : null,
                        categoryId:
                            type == 'transfer' ? null : categoryId,
                        note: noteController.text.trim(),
                        date: selectedDate.toIso8601String(),
                      );

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
                  child: const Text('Save Changes'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text(
          'This transaction will be deleted and its effect on '
          'account balances will be reversed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await TransactionService.deleteTransaction(
          item['id'] as int,
        );

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            onPressed: loadTransactions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : transactions.isEmpty
              ? const Center(
                  child: Text('No transactions available'),
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

                      final isIncome = type == 'income';
                      final isExpense = type == 'expense';

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
                              item['category_name']?.toString() ??
                                  'No category',
                              item['note']?.toString() ?? '',
                              item['date']?.toString() ?? '',
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
                                    Text('Attachments'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
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
