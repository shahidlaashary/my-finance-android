import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/loan_model.dart';
import '../models/repayment_model.dart';
import '../services/loan_service.dart';
import '../services/attachment_service.dart';
import '../widgets/attachment_section.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  List<LoanModel> _loans = [];
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _repaymentAmountController = TextEditingController();
  final _repaymentNotesController = TextEditingController();

  int? _selectedAccountId;
  int? _selectedRepaymentAccountId;

  DateTime _lendingDate = DateTime.now();
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _repaymentAmountController.dispose();
    _repaymentNotesController.dispose();
    super.dispose();
  }

  Future<Database> get _database async {
    final databasePath = await getDatabasesPath();
    return openDatabase(p.join(databasePath, 'my_finance.db'));
  }

  String _dateString(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _money(double amount) => amount.toStringAsFixed(2);

  Future<void> _loadData() async {
    try {
      final db = await _database;
      final accounts = await db.query('accounts', orderBy: 'name ASC');
      final loans = await LoanService.getLoans();

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loans = loans;
        _loading = false;
        if (_accounts.isNotEmpty) {
          _selectedAccountId ??= _accounts.first['id'] as int;
          _selectedRepaymentAccountId ??= _accounts.first['id'] as int;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Data load error: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<DateTime?> _pickDate(DateTime initialDate) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  Future<void> _addLoan() async {
    _nameController.clear();
    _phoneController.clear();
    _amountController.clear();
    _notesController.clear();
    _lendingDate = DateTime.now();
    _dueDate = null;

    if (_accounts.isEmpty) {
      _showMessage('Please create an account first.');
      return;
    }

    int? accountId = _selectedAccountId;
    DateTime lendingDate = _lendingDate;
    DateTime? dueDate = _dueDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Give New Loan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Borrower Name *'),
                ),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Loan Amount *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Payment Account *'),
                  items: _accounts.map((account) {
                    return DropdownMenuItem<int>(
                      value: account['id'] as int,
                      child: Text(account['name']?.toString() ?? 'Account'),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => accountId = value),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lending Date'),
                  subtitle: Text(_dateString(lendingDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final date = await _pickDate(lendingDate);
                    if (date != null) setDialogState(() => lendingDate = date);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due Date'),
                  subtitle: Text(dueDate == null ? 'Not selected' : _dateString(dueDate!)),
                  trailing: const Icon(Icons.event),
                  onTap: () async {
                    final date = await _pickDate(dueDate ?? lendingDate);
                    if (date != null) setDialogState(() => dueDate = date);
                  },
                ),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save Loan'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    if (name.isEmpty || amount == null || amount <= 0) {
      _showMessage('Enter a valid borrower name and amount.');
      return;
    }
    if (accountId == null) {
      _showMessage('Please select an account.');
      return;
    }

    try {
      final loan = LoanModel(
        borrowerName: name,
        borrowerPhone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        amount: amount,
        remainingAmount: amount,
        accountId: accountId,
        lendingDate: _dateString(lendingDate),
        dueDate: dueDate == null ? null : _dateString(dueDate!),
        notes: _notesController.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );
      await LoanService.addLoan(loan);
      _selectedAccountId = accountId;
      await _loadData();
      _showMessage('Loan saved successfully.');
    } catch (error) {
      _showMessage('Could not save loan: $error');
    }
  }

  Future<void> _addRepayment(LoanModel loan) async {
    if (loan.id == null) return;
    if (_accounts.isEmpty) {
      _showMessage('Please create an account first.');
      return;
    }

    _repaymentAmountController.clear();
    _repaymentNotesController.clear();
    int? accountId = _selectedRepaymentAccountId;
    DateTime repaymentDate = DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Receive Repayment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Borrower: ${loan.borrowerName}'),
                const SizedBox(height: 6),
                Text('Outstanding: ${_money(loan.remainingAmount)}'),
                TextField(
                  controller: _repaymentAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Repayment Amount *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Receiving Account *'),
                  items: _accounts.map((account) {
                    return DropdownMenuItem<int>(
                      value: account['id'] as int,
                      child: Text(account['name']?.toString() ?? 'Account'),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => accountId = value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repayment Date'),
                  subtitle: Text(_dateString(repaymentDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final date = await _pickDate(repaymentDate);
                    if (date != null) {
                      setDialogState(() => repaymentDate = date);
                    }
                  },
                ),
                TextField(
                  controller: _repaymentNotesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save Repayment'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final amount = double.tryParse(_repaymentAmountController.text.trim());

    if (amount == null || amount <= 0) {
      _showMessage('Enter a valid repayment amount.');
      return;
    }
    if (amount > loan.remainingAmount + 0.000001) {
      _showMessage('Amount exceeds outstanding balance.');
      return;
    }
    if (accountId == null) {
      _showMessage('Please select a receiving account.');
      return;
    }

    try {
      final repayment = RepaymentModel(
        loanId: loan.id!,
        amount: amount,
        accountId: accountId,
        repaymentDate: _dateString(repaymentDate),
        paymentMethod: 'cash',
        notes: _repaymentNotesController.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );
      await LoanService.addRepayment(repayment);
      _selectedRepaymentAccountId = accountId;
      await _loadData();
      _showMessage('Repayment saved successfully.');
    } catch (error) {
      _showMessage('Could not save repayment: $error');
    }
  }

  Future<void> _showLoanDetails(LoanModel loan) async {
    if (loan.id == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 600,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Loan Details',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Borrower: ${loan.borrowerName}'),
                  Text('Phone: ${loan.borrowerPhone ?? '-'}'),
                  Text('Original Amount: ${_money(loan.amount)}'),
                  Text('Repaid: ${_money(loan.repaidAmount)}'),
                  Text('Outstanding: ${_money(loan.remainingAmount)}'),
                  Text('Lending Date: ${loan.lendingDate}'),
                  Text('Due Date: ${loan.dueDate ?? '-'}'),
                  Text('Notes: ${loan.notes.isEmpty ? '-' : loan.notes}'),
                  const Divider(height: 28),
                  const Text('Loan Attachments', style: TextStyle(fontWeight: FontWeight.bold)),
                  AttachmentSection(
                    ownerType: AttachmentOwnerTypes.loan,
                    ownerId: loan.id!,
                  ),
                  const Divider(height: 28),
                  const Text('Repayment History', style: TextStyle(fontWeight: FontWeight.bold)),
                  FutureBuilder<List<RepaymentModel>>(
                    future: LoanService.getRepayments(loan.id!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text('Could not load repayments: ${snapshot.error}');
                      }
                      final repayments = snapshot.data ?? [];
                      if (repayments.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No repayments recorded yet.'),
                        );
                      }

                      return Column(
                        children: repayments.map((repayment) {
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(_money(repayment.amount)),
                                    subtitle: Text(
                                      'Date: ${repayment.repaymentDate}\n'
                                      'Notes: ${repayment.notes.isEmpty ? '-' : repayment.notes}',
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Delete repayment',
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Delete Repayment?'),
                                            content: const Text(
                                              'This will reverse the account balance and loan balance.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true && repayment.id != null) {
                                          try {
                                            await LoanService.deleteRepayment(repayment.id!);
                                            await AttachmentService.deleteOwnerAttachments(
                                              ownerType: AttachmentOwnerTypes.repayment,
                                              ownerId: repayment.id!,
                                            );
                                            if (dialogContext.mounted) {
                                              Navigator.pop(dialogContext);
                                            }
                                            await _loadData();
                                            if (mounted) _showMessage('Repayment deleted.');
                                          } catch (error) {
                                            _showMessage('Delete failed: $error');
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                  if (repayment.id != null)
                                    AttachmentSection(
                                      ownerType: AttachmentOwnerTypes.repayment,
                                      ownerId: repayment.id!,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (!loan.isPaid)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _addRepayment(loan);
                        },
                        icon: const Icon(Icons.payments),
                        label: const Text('Receive Repayment'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteLoan(LoanModel loan) async {
    if (loan.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Loan?'),
        content: const Text(
          'This will delete the loan and its repayment history, '
          'and reverse the related account balance changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Fetch repayment IDs before deletion; deleteLoan() removes
      // the repayment rows, so fetching them afterwards returns none.
      final repayments = await LoanService.getRepayments(loan.id!);

      await LoanService.deleteLoan(loan.id!);

      await AttachmentService.deleteOwnerAttachments(
        ownerType: AttachmentOwnerTypes.loan,
        ownerId: loan.id!,
      );

      for (final repayment in repayments) {
        if (repayment.id != null) {
          await AttachmentService.deleteOwnerAttachments(
            ownerType: AttachmentOwnerTypes.repayment,
            ownerId: repayment.id!,
          );
        }
      }

      await _loadData();
      _showMessage('Loan deleted successfully.');
    } catch (error) {
      _showMessage('Could not delete loan: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final outstanding = _loans.fold<double>(
      0,
      (total, loan) => total + loan.remainingAmount,
    );
    final overdueCount = _loans.where((loan) => loan.isOverdue).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans & Lending'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Outstanding',
                            style: TextStyle(fontSize: 15, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _money(outstanding),
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('Total loans: ${_loans.length}'),
                          Text('Overdue loans: $overdueCount'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'All Loans',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        onPressed: _addLoan,
                        icon: const Icon(Icons.add),
                        label: const Text('New Loan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loans.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: Text(
                          'No loans added yet.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._loans.map((loan) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      loan.borrowerName,
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (loan.isPaid)
                                    const Chip(
                                      label: Text('Paid'),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  else if (loan.isOverdue)
                                    const Chip(
                                      label: Text('Overdue'),
                                      backgroundColor: Color(0xFFFFE0E0),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  else
                                    const Chip(
                                      label: Text('Active'),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              if (loan.borrowerPhone != null) Text(loan.borrowerPhone!),
                              const SizedBox(height: 8),
                              Text('Loan Amount: ${_money(loan.amount)}'),
                              Text('Repaid: ${_money(loan.repaidAmount)}'),
                              Text(
                                'Remaining: ${_money(loan.remainingAmount)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text('Lending Date: ${loan.lendingDate}'),
                              if (loan.dueDate != null) Text('Due Date: ${loan.dueDate}'),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: loan.amount <= 0
                                    ? 0
                                    : (loan.repaidAmount / loan.amount)
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _showLoanDetails(loan),
                                    icon: const Icon(Icons.visibility),
                                    label: const Text('Details'),
                                  ),
                                  if (!loan.isPaid)
                                    TextButton.icon(
                                      onPressed: () => _addRepayment(loan),
                                      icon: const Icon(Icons.payments),
                                      label: const Text('Repayment'),
                                    ),
                                  IconButton(
                                    onPressed: () => _deleteLoan(loan),
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: 'Delete loan',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
