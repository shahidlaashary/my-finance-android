import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/models/repayment_model.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/core/localization/app_text.dart';
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});
  @override
  State<LoansScreen> createState() => _LoansScreenState();
}
class _LoansScreenState extends State<LoansScreen> {
  List<LoansModel> _loans = [];
  List<Map<String, dynamic>> _wallets = [];
  Map<String, double> _outstandingByCurrency = {};
  bool _loading = true;
  bool _hideBalances = false;
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
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    _loadData();
  }
  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _repaymentAmountController.dispose();
    _repaymentNotesController.dispose();
    super.dispose();
  }
  String _dateString(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
  String _money(double amount) => _hideBalances ? '••••••' : amount.toStringAsFixed(2);
  String _currencyForAccount(int walletId) {
    final account = _wallets.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == walletId,
      orElse: () => null,
    );
    return (account?['currency']?.toString() ?? 'PKR')
        .trim()
        .toUpperCase();
  }
  String _moneyWithCurrency(double amount, int walletId) {
    return '${_currencyForAccount(walletId)} ${_money(amount)}';
  }
  void _onPreferencesChanged() async {
    final hidden = await GeneralPreferences.instance.hideBalances;
    if (mounted && hidden != _hideBalances) {
      setState(() => _hideBalances = hidden);
    }
  }

  Future<void> _loadData() async {
    try {
      final hideBalances = await GeneralPreferences.instance.hideBalances;
      final wallets = await TransactionsService.getAccounts();
      final loans = await LoansService.getLoans();
      final outstandingByCurrency =
          await LoansService.getTotalOutstandingByCurrency();
      if (!mounted) return;
      setState(() {
        _hideBalances = hideBalances;
        _wallets = wallets;
        _loans = loans;
        _outstandingByCurrency = outstandingByCurrency;
        _loading = false;
        if (_wallets.isNotEmpty) {
          final walletIds = _wallets
              .map((wallet) => (wallet['id'] as num).toInt())
              .toSet();
          final firstWalletId = (_wallets.first['id'] as num).toInt();
          if (_selectedAccountId == null || !walletIds.contains(_selectedAccountId)) {
            _selectedAccountId = firstWalletId;
          }
          if (_selectedRepaymentAccountId == null ||
              !walletIds.contains(_selectedRepaymentAccountId)) {
            _selectedRepaymentAccountId = firstWalletId;
          }
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
    await _loadData();
    if (!mounted) return;
    _nameController.clear();
    _phoneController.clear();
    _amountController.clear();
    _notesController.clear();
    _lendingDate = DateTime.now();
    _dueDate = null;
    if (_wallets.isEmpty) {
      _showMessage('Please create an account first.');
      return;
    }
    int? walletId = _selectedAccountId;
    DateTime lendingDate = _lendingDate;
    DateTime? dueDate = _dueDate;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(appText(context, 'Give New Loan', 'نیا قرض دیں')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: appText(context, "Borrower Name *", "Borrower Name *")),
                ),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: appText(context, "Phone Number", "Phone Number")),
                ),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: appText(context, "Loan Amount *", "Loan Amount *")),
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: walletId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: appText(context, "Payment Account *", "Payment Account *")),
                  items: _wallets.map((account) {
                    return DropdownMenuItem<int>(
                      value: account['id'] as int,
                      child: Text(
                        '${account['name']} '
                        '(${(account['currency']?.toString() ?? 'PKR').toUpperCase()})',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => walletId = value),
                ),
                SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(appText(context, 'Lending Date', 'قرض دینے کی تاریخ')),
                  subtitle: Text(_dateString(lendingDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final date = await _pickDate(lendingDate);
                    if (date != null) setDialogState(() => lendingDate = date);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(appText(context, 'Due Date', 'واپسی کی تاریخ')),
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
                  decoration: InputDecoration(labelText: appText(context, "Notes", "Notes")),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(appText(context, 'Save Loan', 'قرض محفوظ کریں')),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    if (name.isEmpty || amount == null || !amount.isFinite || amount <= 0) {
      _showMessage('Enter a valid borrower name and amount.');
      return;
    }
    if (walletId == null) {
      _showMessage('Please select an account.');
      return;
    }
    try {
      final loan = LoansModel(
        borrowerName: name,
        borrowerPhone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        amount: amount,
        remainingAmount: amount,
        walletId: walletId!,
        lendingDate: _dateString(lendingDate),
        dueDate: dueDate == null ? null : _dateString(dueDate!),
        notes: _notesController.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );
      await LoansService.addLoan(loan);
      _selectedAccountId = walletId;
      await _loadData();
      _showMessage('Loan saved successfully.');
    } catch (error) {
      _showMessage('Could not save loan: $error');
    }
  }
  Future<void> _addRepayment(LoansModel loan) async {
    if (loan.id == null) return;
    await _loadData();
    if (!mounted) return;
    if (_wallets.isEmpty) {
      _showMessage('Please create an account first.');
      return;
    }
    _repaymentAmountController.clear();
    _repaymentNotesController.clear();
    int? walletId = _selectedRepaymentAccountId;
    DateTime repaymentDate = DateTime.now();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(appText(context, 'Receive Repayment', 'قرض کی واپسی وصول کریں')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${appText(context, 'Borrower:', 'قرض لینے والا:')} ${loan.borrowerName}'),
                SizedBox(height: 6),
                Text(appText(context, "Outstanding: ", "Outstanding: ")
                  '${_moneyWithCurrency(loan.remainingAmount, loan.walletId)}',
                ),
                TextField(
                  controller: _repaymentAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: appText(context, "Repayment Amount *", "Repayment Amount *")),
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: walletId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: appText(context, "Receiving Account *", "Receiving Account *")),
                  items: _wallets.map((account) {
                    return DropdownMenuItem<int>(
                      value: account['id'] as int,
                      child: Text(
                        '${account['name']} '
                        '(${(account['currency']?.toString() ?? 'PKR').toUpperCase()})',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => walletId = value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(appText(context, 'Repayment Date', 'واپسی کی تاریخ')),
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
                  decoration: InputDecoration(labelText: appText(context, "Notes", "Notes")),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(appText(context, 'Save Repayment', 'واپسی محفوظ کریں')),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final amount = double.tryParse(_repaymentAmountController.text.trim());
    if (amount == null || !amount.isFinite || amount <= 0) {
      _showMessage('Enter a valid repayment amount.');
      return;
    }
    if (amount > loan.remainingAmount + 0.000001) {
      _showMessage('Amount exceeds outstanding balance.');
      return;
    }
    if (walletId == null) {
      _showMessage('Please select a receiving account.');
      return;
    }
    if (_currencyForAccount(walletId!) !=
        _currencyForAccount(loan.walletId)) {
      _showMessage('Receiving account must use the same currency as the loan.');
      return;
    }
    try {
      final repayment = RepaymentModel(
        loanId: loan.id!,
        amount: amount,
        walletId: walletId!,
        repaymentDate: _dateString(repaymentDate),
        paymentMethod: 'cash',
        notes: _repaymentNotesController.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );
      await LoansService.addRepayment(repayment);
      _selectedRepaymentAccountId = walletId;
      await _loadData();
      _showMessage('Repayment saved successfully.');
    } catch (error) {
      _showMessage('Could not save repayment: $error');
    }
  }
  Future<void> _showLoanDetails(LoansModel loan) async {
    if (loan.id == null) return;
    final currency = _currencyForAccount(loan.walletId);
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
                      Expanded(
                        child: Text(appText(context, "Loan Details", "Loan Details"),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('Borrower: ${loan.borrowerName}'),
                  Text('${appText(context, 'Phone:', 'فون:')} ${loan.borrowerPhone ?? '-'}'),
                  Text('${appText(context, 'Currency:', 'کرنسی:')} $currency'),
                  Text('${appText(context, 'Original Amount:', 'اصل رقم:')} ${_moneyWithCurrency(loan.amount, loan.walletId)}'),
                  Text('${appText(context, 'Repaid:', 'واپس ادا شدہ:')} ${_moneyWithCurrency(loan.repaidAmount, loan.walletId)}'),
                  Text('${appText(context, 'Outstanding:', 'بقایا:')} ${_moneyWithCurrency(loan.remainingAmount, loan.walletId)}'),
                  Text('${appText(context, 'Lending Date:', 'قرض دینے کی تاریخ:')} ${loan.lendingDate}'),
                  Text('Due Date: ${loan.dueDate ?? '-'}'),
                  Text('${appText(context, 'Notes:', 'نوٹس:')} ${loan.notes.isEmpty ? '-' : loan.notes}'),
                  const Divider(height: 28),
                  Text(appText(context, "Loan Attachments", "Loan Attachments"),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  AttachmentSection(
                    ownerType: AttachmentOwnerTypes.loan,
                    ownerId: loan.id!,
                  ),
                  const Divider(height: 28),
                  Text(appText(context, "Repayment History", "Repayment History"),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  FutureBuilder<List<RepaymentModel>>(
                    future: LoansService.getRepayments(loan.id!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text('Could not load repayments: ${snapshot.error}');
                      }
                      final repayments = snapshot.data ?? [];
                      if (repayments.isEmpty) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(appText(context, "No repayments recorded yet.", "No repayments recorded yet.")),
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
                                    title: Text(
                                      _moneyWithCurrency(
                                        repayment.amount,
                                        loan.walletId,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Date: ${repayment.repaymentDate}\n'
                                      'Notes: ${repayment.notes.isEmpty ? '-' : repayment.notes}',
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Delete repayment',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text(appText(context, "Delete Repayment?", "Delete Repayment?")),
                                            content: Text(appText(context, "This will reverse the account balance and loan balance.", "This will reverse the account balance and loan balance."),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, false),
                                                child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, true),
                                                child: Text(appText(context, "Delete", "Delete")),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true && repayment.id != null) {
                                          try {
                                            await LoansService.deleteRepayment(repayment.id!);
                                            await AttachmentService.deleteOwnerAttachments(
                                              ownerType: AttachmentOwnerTypes.repayment,
                                              ownerId: repayment.id!,
                                            );
                                            if (dialogContext.mounted) {
                                              Navigator.pop(dialogContext);
                                            }
                                            await _loadData();
                                            if (mounted) {
                                              _showMessage('Repayment deleted.');
                                            }
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
                  SizedBox(height: 12),
                  if (!loan.isPaid)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _addRepayment(loan);
                        },
                        icon: const Icon(Icons.payments),
                        label: Text(appText(context, 'Receive Repayment', 'قرض کی واپسی وصول کریں')),
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
  Future<void> _deleteLoan(LoansModel loan) async {
    if (loan.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText(context, "Delete Loan?", "Delete Loan?")),
        content: Text(appText(context, "This will delete the loan and its repayment history, ", "This will delete the loan and its repayment history, ")
          'and reverse the related account balance changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(appText(context, "Delete", "Delete")),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final repayments = await LoansService.getRepayments(loan.id!);
      await LoansService.deleteLoan(loan.id!);
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
    final overdueCount = _loans.where((loan) => loan.isOverdue).length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202A26),
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: Text(appText(context, 'Loans & Repayments', 'قرضے اور واپسی'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF202A26))),
        actions: buildSharedAppBarActions(context),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLoan,
        backgroundColor: const Color(0xFF147D59),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(appText(context, 'New Loan', 'نیا قرض')),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
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
                          Text(appText(context, "Total Outstanding by Currency", "Total Outstanding by Currency"),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 12),
                          if (_outstandingByCurrency.isEmpty)
                            Text(appText(context, "No outstanding loans.", "No outstanding loans."),
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            ..._outstandingByCurrency.entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _money(entry.value),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          const Divider(height: 24),
                          Text('Total loans: ${_loans.length}'),
                          Text('Overdue loans: $overdueCount'),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(appText(context, "All Loans", "All Loans"),
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  if (_loans.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.handshake_outlined, size: 55, color: Color(0xFF147D59)),
                            SizedBox(height: 12),
                            Text(appText(context, 'No loans added yet.', 'ابھی کوئی قرض شامل نہیں کیا گیا۔'), textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF7B8781))),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._loans.map((loan) {
                      final currency = _currencyForAccount(loan.walletId);
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
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (loan.isPaid)
                                    Chip(
                                      label: Text(appText(context, 'Paid', 'ادا شدہ')),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  else if (loan.isOverdue)
                                    Chip(
                                      label: Text(appText(context, 'Overdue', 'میعاد ختم')),
                                      backgroundColor: Color(0xFFFFE0E0),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  else
                                    Chip(
                                      label: Text(appText(context, 'Active', 'فعال')),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              if (loan.borrowerPhone != null)
                                Text(loan.borrowerPhone!),
                              SizedBox(height: 8),
                              Text('Currency: $currency'),
                              Text(appText(context, "Loan Amount: ", "Loan Amount: ")
                                '${_moneyWithCurrency(loan.amount, loan.walletId)}',
                              ),
                              Text(appText(context, "Repaid: ", "Repaid: ")
                                '${_moneyWithCurrency(loan.repaidAmount, loan.walletId)}',
                              ),
                              Text(appText(context, "Remaining: ${_moneyWithCurrency(loan.remainingAmount, loan.walletId)}", "باقی: ${_moneyWithCurrency(loan.remainingAmount, loan.walletId)}"),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text('Lending Date: ${loan.lendingDate}'),
                              if (loan.dueDate != null)
                                Text('Due Date: ${loan.dueDate}'),
                              SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: loan.amount <= 0
                                    ? 0
                                    : (loan.repaidAmount / loan.amount)
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                              ),
                              SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _showLoanDetails(loan),
                                    icon: const Icon(Icons.visibility),
                                    label: Text(appText(context, 'Details', 'تفصیلات')),
                                  ),
                                  if (!loan.isPaid)
                                    TextButton.icon(
                                      onPressed: () => _addRepayment(loan),
                                      icon: const Icon(Icons.payments),
                                      label: Text(appText(context, 'Repayment', 'قرض کی واپسی')),
                                    ),
                                  IconButton(
                                    onPressed: () => _deleteLoan(loan),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
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
