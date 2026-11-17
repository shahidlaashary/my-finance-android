import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/models/repayment_model.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/core/localization/app_text.dart';
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});
  @override
  State<LoansScreen> createState() => _LoansScreenState();
}
class _LoansScreenState extends State<LoansScreen> {
  List<LoansModel> _loans = [];
  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _parties = [];
  Map<int, String> _assetNames = {};
  Map<String, double> _outstandingByCurrency = {};
  bool _loading = true;
  bool _hideBalances = false;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _repaymentAmountController = TextEditingController();
  final _repaymentNotesController = TextEditingController();
  int? _selectedWalletId;
  int? _selectedRepaymentWalletId;
  DateTime _lendingDate = DateTime.now();
  DateTime? _dueDate;
  int? _selectedPartyId;
  String _loanType = 'given';
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
  String _currencyForWallet(int walletId) {
    final wallet = _wallets.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == walletId,
      orElse: () => null,
    );
    return (wallet?['currency']?.toString() ?? 'PKR')
        .trim()
        .toUpperCase();
  }
  String _moneyWithCurrency(double amount, int walletId) {
    return '${_currencyForWallet(walletId)} ${_money(amount)}';
  }
  String _moneyWithLoanCurrency(double amount, LoansModel loan) {
    return '${loan.currency.toUpperCase()} ${_money(amount)}';
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
      final wallets = await TransactionsService.getWallets();
      final loans = await LoansService.getLoans();
      final parties = await LoansService.getParties();
      final outstandingByCurrency =
          await LoansService.getTotalOutstandingByCurrency();
      final assetNames = <int, String>{};
      try {
        final db = await TransactionsService.database;
        final assetRows = await db.query('assets', columns: ['id', 'name']);
        for (final row in assetRows) {
          assetNames[(row['id'] as num).toInt()] = row['name']?.toString() ?? 'Asset';
        }
      } catch (_) {
        // Asset table may not exist until the Asset section is first opened.
      }
      if (!mounted) return;
      setState(() {
        _hideBalances = hideBalances;
        _wallets = wallets;
        _parties = parties;
        _assetNames = assetNames;
        _loans = loans;
        _outstandingByCurrency = outstandingByCurrency;
        _loading = false;
        if (_wallets.isNotEmpty) {
          final walletIds = _wallets
              .map((wallet) => (wallet['id'] as num).toInt())
              .toSet();
          final firstWalletId = (_wallets.first['id'] as num).toInt();
          if (_selectedWalletId == null || !walletIds.contains(_selectedWalletId)) {
            _selectedWalletId = firstWalletId;
          }
          if (_selectedRepaymentWalletId == null ||
              !walletIds.contains(_selectedRepaymentWalletId)) {
            _selectedRepaymentWalletId = firstWalletId;
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
  Future<int?> _createParty() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add New Party'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Party Name *')),
          TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
          TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Address')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save Party')),
        ],
      ),
    );
    if (result != true || nameController.text.trim().isEmpty) {
      nameController.dispose(); phoneController.dispose(); addressController.dispose();
      return null;
    }
    try {
      final id = await LoansService.addParty(
        name: nameController.text,
        phone: phoneController.text,
        address: addressController.text,
      );
      nameController.dispose(); phoneController.dispose(); addressController.dispose();
      return id;
    } catch (error) {
      _showMessage('Could not save party: $error');
      nameController.dispose(); phoneController.dispose(); addressController.dispose();
      return null;
    }
  }

  Future<void> _showParties() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyManagementPage(
          hideBalances: _hideBalances,
          onLoanTap: (loan) => _showLoanDetails(loan),
        ),
      ),
    );
    await _loadData();
  }

  Future<void> _addLoan() async {
    await _loadData();
    if (!mounted) return;
    _nameController.clear();
    _phoneController.clear();
    _loanType = 'given';
    _selectedPartyId = null;
    bool createNewParty = _parties.isEmpty;
    if (!createNewParty && _selectedPartyId != null) {
      final selected = _parties.firstWhere((p) => p['id'] == _selectedPartyId);
      _nameController.text = selected['name']?.toString() ?? '';
      _phoneController.text = selected['phone']?.toString() ?? '';
    }
    _amountController.clear();
    _notesController.clear();
    _lendingDate = DateTime.now();
    _dueDate = null;
    if (_wallets.isEmpty) {
      _showMessage('Please create an wallet first.');
      return;
    }
    int? walletId = _selectedWalletId;
    final initialParty = _parties.where((p) => p['id'] == _selectedPartyId).isEmpty
        ? null : _parties.firstWhere((p) => p['id'] == _selectedPartyId);
    final initialCurrency = (initialParty?['currency']?.toString() ?? 'PKR').toUpperCase();
    if (walletId != null && _currencyForWallet(walletId) != initialCurrency) walletId = null;
    DateTime lendingDate = _lendingDate;
    DateTime? dueDate = _dueDate;
    final configuredBaseCurrency = await FinanceDB.instance.getBaseCurrency();
    String newPartyCurrency = CurrencyCatalog.supported.contains(configuredBaseCurrency) ? configuredBaseCurrency : 'PKR';
    final List<XFile> pendingLoanImages = [];
    final ImagePicker loanImagePicker = ImagePicker();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final screenHeight = MediaQuery.sizeOf(context).height;
          final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
          final maxSheetHeight = keyboardHeight > 0
              ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * 0.95
              : screenHeight * 0.78;

          return AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxSheetHeight),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9E0DC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                appText(context, 'New Loan', 'نیا قرض'),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF202A26),
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Navigator.pop(sheetContext, false),
                              icon: const Icon(Icons.close_rounded),
                              color: const Color(0xFF718078),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: DropdownButtonFormField<String>(
                                      value: _loanType,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Loan Type',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'given', child: Text('Loan Given', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: 'taken', child: Text('Loan Taken', overflow: TextOverflow.ellipsis)),
                                      ],
                                      onChanged: (value) => setSheetState(() => _loanType = value ?? 'given'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 1,
                                    child: DropdownButtonFormField<String>(
                                      value: createNewParty ? '__new_party__' : _selectedPartyId?.toString(),
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Select Party *',
                                        hintText: 'Choose party or create new',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                                      ),
                                      items: [
                                        ..._parties.map((party) => DropdownMenuItem<String>(
                                          value: party['id'].toString(),
                                          child: Text(
                                            '${party['name']}${(party['phone'] ?? '').toString().isEmpty ? '' : ' • ${party['phone']}'}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )),
                                        const DropdownMenuItem<String>(
                                          value: '__new_party__',
                                          child: Text('＋ Create Party', overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                      onChanged: (value) {
                                        setSheetState(() {
                                          createNewParty = value == '__new_party__';
                                          if (createNewParty) {
                                            _selectedPartyId = null;
                                            _nameController.clear();
                                            _phoneController.clear();
                                            newPartyCurrency = CurrencyCatalog.supported.contains(configuredBaseCurrency) ? configuredBaseCurrency : 'PKR';
                                            final matching = _wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == newPartyCurrency);
                                            walletId = matching.isEmpty ? null : (matching.first['id'] as num).toInt();
                                          } else {
                                            _selectedPartyId = int.tryParse(value ?? '');
                                            final party = _parties.where((p) => p['id'] == _selectedPartyId).isEmpty
                                                ? null
                                                : _parties.firstWhere((p) => p['id'] == _selectedPartyId);
                                            _nameController.text = party?['name']?.toString() ?? '';
                                            _phoneController.text = party?['phone']?.toString() ?? '';
                                            final currency = (party?['currency']?.toString() ?? 'PKR').toUpperCase();
                                            final matching = _wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == currency);
                                            walletId = matching.isEmpty ? null : (matching.first['id'] as num).toInt();
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (createNewParty) ...[
                                TextField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: const InputDecoration(labelText: 'Party Name *'),
                                ),
                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(labelText: 'Phone Number'),
                                ),
                                DropdownButtonFormField<String>(
                                  value: newPartyCurrency,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Party Currency *'),
                                  items: CurrencyCatalog.supported.map((currency) => DropdownMenuItem(value: currency, child: Text(currency))).toList(),
                                  onChanged: (value) => setSheetState(() {
                                    newPartyCurrency = value ?? 'PKR';
                                    final match = _wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == newPartyCurrency);
                                    walletId = match.isEmpty ? null : (match.first['id'] as num).toInt();
                                  }),
                                ),
                              ] else if (_selectedPartyId != null)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Selected: ${_nameController.text}${_phoneController.text.trim().isEmpty ? '' : ' • ${_phoneController.text}'}',
                                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: _amountController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(labelText: appText(context, "Loan Amount *", "Loan Amount *")),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 1,
                                    child: DropdownButtonFormField<int>(
                                      value: walletId,
                                      isExpanded: true,
                                      decoration: InputDecoration(labelText: appText(context, "Payment Wallet *", "Payment Wallet *")),
                                      items: _wallets.where((wallet) {
                                        final party = _parties.where((p) => p['id'] == _selectedPartyId).isEmpty
                                            ? null : _parties.firstWhere((p) => p['id'] == _selectedPartyId);
                                        final currency = createNewParty ? newPartyCurrency : (party?['currency']?.toString() ?? 'PKR').toUpperCase();
                                        return (wallet['currency']?.toString() ?? 'PKR').toUpperCase() == currency;
                                      }).map((wallet) {
                                        return DropdownMenuItem<int>(
                                          value: (wallet['id'] as num).toInt(),
                                          child: Text(
                                            '${wallet['name']} (${(wallet['currency']?.toString() ?? 'PKR').toUpperCase()})',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (value) => setSheetState(() => walletId = value),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () async {
                                      final date = await _pickDate(lendingDate);
                                      if (date != null) setSheetState(() => lendingDate = date);
                                    },
                                    child: InputDecorator(
                                      decoration: InputDecoration(labelText: appText(context, 'Lending Date', 'قرض دینے کی تاریخ'), suffixIcon: const Icon(Icons.calendar_month)),
                                      child: Text(_dateString(lendingDate), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  )),
                                  const SizedBox(width: 10),
                                  Expanded(child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () async {
                                      final date = await _pickDate(dueDate ?? lendingDate);
                                      if (date != null) setSheetState(() => dueDate = date);
                                    },
                                    child: InputDecorator(
                                      decoration: InputDecoration(labelText: appText(context, 'Due Date', 'واپسی کی تاریخ'), suffixIcon: const Icon(Icons.event)),
                                      child: Text(dueDate == null ? 'Not selected' : _dateString(dueDate!), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  )),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context).inputDecorationTheme.fillColor,
                                ),
                                padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  TextField(
                                    controller: _notesController,
                                    maxLines: 3,
                                    decoration: InputDecoration(
                                      labelText: appText(context, "Notes", "Notes"),
                                      border: InputBorder.none,
                                      filled: false,
                                    ),
                                  ),
                                  Row(children: [
                                    TextButton.icon(
                                      onPressed: () async {
                                        final photos = await loanImagePicker.pickMultiImage(imageQuality: 85);
                                        if (photos.isNotEmpty) setSheetState(() => pendingLoanImages.addAll(photos));
                                      },
                                      icon: const Icon(Icons.photo_library_outlined),
                                      label: const Text('Gallery'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        final photo = await loanImagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
                                        if (photo != null) setSheetState(() => pendingLoanImages.add(photo));
                                      },
                                      icon: const Icon(Icons.camera_alt_outlined),
                                      label: const Text('Camera'),
                                    ),
                                  ]),
                                  if (pendingLoanImages.isNotEmpty)
                                    Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 6, runSpacing: 4, children: pendingLoanImages.asMap().entries.map((entry) => Chip(
                                      avatar: const Icon(Icons.image_outlined, size: 16),
                                      label: SizedBox(width: 105, child: Text(entry.value.name, overflow: TextOverflow.ellipsis)),
                                      onDeleted: () => setSheetState(() => pendingLoanImages.removeAt(entry.key)),
                                    )).toList())),
                                ]),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(sheetContext, false),
                                child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(sheetContext, true),
                                child: Text(appText(context, 'Save Loan', 'قرض محفوظ کریں')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (result != true) return;
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    if ((createNewParty && name.isEmpty) || amount == null || !amount.isFinite || amount <= 0) {
      _showMessage('Enter a valid party name and loan amount.');
      return;
    }
    if (!createNewParty && _selectedPartyId == null) {
      _showMessage('Please select a party.');
      return;
    }
    if (walletId == null) {
      _showMessage('Please select a wallet.');
      return;
    }
    try {
      if (createNewParty) {
        _selectedPartyId = await LoansService.addParty(
          name: name,
          phone: _phoneController.text,
          currency: newPartyCurrency,
        );
        await _loadData();
      }
      final loan = LoansModel(
        partyId: _selectedPartyId,
        loanType: _loanType,
        amount: amount,
        remainingAmount: amount,
        walletId: walletId!,
        currency: createNewParty ? newPartyCurrency : ((_parties.firstWhere((p) => p['id'] == _selectedPartyId, orElse: () => {'currency': 'PKR'})['currency']?.toString() ?? 'PKR').toUpperCase()),
        lendingDate: _dateString(lendingDate),
        dueDate: dueDate == null ? null : _dateString(dueDate!),
        notes: _notesController.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );
      final loanId = await LoansService.addLoan(loan);
      for (final image in pendingLoanImages) {
        await AttachmentService.addAttachment(
          ownerType: AttachmentOwnerTypes.loan,
          ownerId: loanId,
          sourcePath: image.path,
          originalFileName: image.name,
        );
      }
      _selectedWalletId = walletId;
      await _loadData();
      _showMessage('Loan saved successfully.');
    } catch (error) {
      _showMessage('Could not save loan: $error');
    }
  }
  Map<String, dynamic>? _partyForLoan(LoansModel loan) {
    final partyId = loan.partyId;
    if (partyId == null) return null;
    for (final party in _parties) {
      if (party['id'] == partyId) return party;
    }
    return null;
  }

  String _partyNameForLoan(LoansModel loan) =>
      _partyForLoan(loan)?['name']?.toString() ?? 'Unknown Party';

  String _partyPhoneForLoan(LoansModel loan) =>
      _partyForLoan(loan)?['phone']?.toString() ?? '-';
  String _assetReferenceLabel(LoansModel loan) {
    if (!loan.isAssetLinked || loan.sourceId == null) return '';
    final name = _assetNames[loan.sourceId!] ?? 'Asset';
    final type = loan.sourceType == 'asset_purchase' ? 'Purchase' : 'Sale';
    return '$name • $type';
  }

  Future<void> _addRepayment(LoansModel loan) async {
    if (loan.id == null) return;
    await _loadData();
    if (!mounted) return;
    if (_wallets.isEmpty) {
      _showMessage('Please create an wallet first.');
      return;
    }
    _repaymentAmountController.clear();
    _repaymentNotesController.clear();
    int? walletId = _selectedRepaymentWalletId;
    if (walletId == null || _currencyForWallet(walletId) != loan.currency.toUpperCase()) {
      final matching = _wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == loan.currency.toUpperCase());
      walletId = matching.isEmpty ? null : (matching.first['id'] as num).toInt();
    }
    DateTime repaymentDate = DateTime.now();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(loan.loanType == 'given' ? 'Receive Repayment' : 'Pay Back Loan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${loan.loanType == 'given' ? 'Borrower:' : 'Lender:'} ${_partyNameForLoan(loan)}'),
                SizedBox(height: 6),
                Text('${appText(context, "Outstanding: ", "بقایا: ")}'
                  '${_moneyWithLoanCurrency(loan.remainingAmount, loan)}',
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
                  decoration: InputDecoration(labelText: loan.loanType == 'given' ? 'Receiving Wallet *' : 'Paying Wallet *'),
                  items: _wallets.where((wallet) =>
                    (wallet['currency']?.toString() ?? 'PKR').toUpperCase() == loan.currency.toUpperCase()
                  ).map((wallet) {
                    return DropdownMenuItem<int>(
                      value: (wallet['id'] as num).toInt(),
                      child: Text('${wallet['name']} (${(wallet['currency']?.toString() ?? 'PKR').toUpperCase()})'),
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
              child: Text(loan.loanType == 'given' ? 'Save Repayment' : 'Save Payment'),
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
      _showMessage('Please select a receiving wallet.');
      return;
    }
    if (_currencyForWallet(walletId!) != loan.currency.toUpperCase()) {
      _showMessage('Receiving wallet must use the same currency as the loan.');
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
      _selectedRepaymentWalletId = walletId;
      await _loadData();
      _showMessage('Repayment saved successfully.');
    } catch (error) {
      _showMessage('Could not save repayment: $error');
    }
  }
  Future<void> _showLoanDetails(LoansModel loan) async {
    if (loan.id == null) return;
    final currency = loan.currency.toUpperCase();
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
                  Text('${loan.loanType == 'given' ? 'Borrower' : 'Lender'}: ${_partyNameForLoan(loan)}'),
                  Text('${appText(context, 'Phone:', 'فون:')} ${_partyPhoneForLoan(loan)}'),
                  Text('${appText(context, 'Currency:', 'کرنسی:')} $currency'),
                  if (loan.isAssetLinked) Text('Linked Asset Reference: ${_assetReferenceLabel(loan)} • ID ${loan.sourceId}'),
                  Text('${appText(context, 'Original Amount:', 'اصل رقم:')} ${_moneyWithLoanCurrency(loan.amount, loan)}'),
                  Text('${appText(context, 'Repaid:', 'واپس ادا شدہ:')} ${_moneyWithLoanCurrency(loan.repaidAmount, loan)}'),
                  Text('${appText(context, 'Outstanding:', 'بقایا:')} ${_moneyWithLoanCurrency(loan.remainingAmount, loan)}'),
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
                                      _moneyWithLoanCurrency(repayment.amount, loan),
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
                                            content: Text(appText(context, "This will reverse the wallet balance and loan balance.", "This will reverse the wallet balance and loan balance."),
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
                        label: Text(loan.loanType == 'given' ? 'Receive Repayment' : 'Pay Back Loan'),
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
        content: Text(appText(context, "This will delete the loan and its repayment history, and reverse the related wallet balance changes.", "یہ قرض اور اس کی ادائیگیوں کی تاریخ حذف کرکے متعلقہ اکاؤنٹ بیلنس کی تبدیلیاں واپس کرے گا۔")),
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
        title: GeneralPreferences.instance.personalizedHeaderTitle(context, Text(appText(context, 'Loans & Repayments', 'قرضے اور واپسی'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF202A26)))),
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
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _showParties,
                    icon: const Icon(Icons.people_alt_outlined),
                    label: Text('Manage Parties (${_parties.length})'),
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
                      final currency = loan.currency.toUpperCase();
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
                                      '${_partyNameForLoan(loan)} • ${loan.loanType == 'given' ? 'Given' : 'Taken'}',
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
                              if (_partyPhoneForLoan(loan) != '-')
                                Text(_partyPhoneForLoan(loan)),
                              SizedBox(height: 8),
                              Text(loan.loanType == 'given' ? 'Loan Given • Currency: $currency' : 'Loan Taken • Currency: $currency'),
                              if (loan.isAssetLinked) Text('Linked Asset: ${_assetReferenceLabel(loan)} • ID: ${loan.sourceId}'),
                              Text('${appText(context, "Loan Amount: ", "قرض کی رقم: ")}'
                                '${_moneyWithLoanCurrency(loan.amount, loan)}',
                              ),
                              Text('${appText(context, "Repaid: ", "ادا شدہ: ")}'
                                '${_moneyWithLoanCurrency(loan.repaidAmount, loan)}',
                              ),
                              Text(appText(context, "Remaining: ${_moneyWithLoanCurrency(loan.remainingAmount, loan)}", "باقی: ${_moneyWithLoanCurrency(loan.remainingAmount, loan)}"),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text('${loan.loanType == 'given' ? 'Lending Date' : 'Borrowing Date'}: ${loan.lendingDate}'),
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


class PartyManagementPage extends StatefulWidget {
  final bool hideBalances;
  final ValueChanged<LoansModel> onLoanTap;

  const PartyManagementPage({
    super.key,
    required this.hideBalances,
    required this.onLoanTap,
  });

  @override
  State<PartyManagementPage> createState() => _PartyManagementPageState();
}

class _PartyManagementPageState extends State<PartyManagementPage> {
  List<Map<String, dynamic>> _parties = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    final parties = await LoansService.getParties();
    if (!mounted) return;
    setState(() {
      _parties = parties;
      _loading = false;
    });
  }

  String _money(num value) =>
      widget.hideBalances ? '••••••' : value.toStringAsFixed(2);

  Future<void> _editParty([Map<String, dynamic>? party]) async {
    final name = TextEditingController(text: party?['name']?.toString() ?? '');
    final phone = TextEditingController(text: party?['phone']?.toString() ?? '');
    final address = TextEditingController(text: party?['address']?.toString() ?? '');
    final configuredBaseCurrency = await FinanceDB.instance.getBaseCurrency();
    String selectedCurrency = (party?['currency']?.toString() ?? configuredBaseCurrency).toUpperCase();
    final currencies = CurrencyCatalog.supported;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(party == null ? 'Add New Party' : 'Edit Party'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Party Name *'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Party name is required'
                    : null,
              ),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              TextFormField(
                controller: address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              StatefulBuilder(builder: (context, setCurrencyState) => DropdownButtonFormField<String>(
                value: currencies.contains(selectedCurrency) ? selectedCurrency : 'PKR',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Party Currency *'),
                items: currencies.map((currency) => DropdownMenuItem(value: currency, child: Text(currency))).toList(),
                onChanged: (value) { if (value != null) setCurrencyState(() => selectedCurrency = value); },
              )),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        if (party == null) {
          await LoansService.addParty(
            name: name.text,
            phone: phone.text,
            address: address.text,
            currency: selectedCurrency,
          );
        } else {
          await LoansService.updateParty(
            id: (party['id'] as num).toInt(),
            name: name.text,
            phone: phone.text,
            address: address.text,
            currency: selectedCurrency,
          );
        }
        await _loadParties();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save party: $error')),
          );
        }
      }
    }
    name.dispose();
    phone.dispose();
    address.dispose();
  }

  Future<void> _deleteParty(Map<String, dynamic> party) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Party?'),
        content: Text(
          'Delete "${party['name']}"? Parties linked to any loan cannot be deleted, so loan history remains safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await LoansService.deleteParty((party['id'] as num).toInt());
      await _loadParties();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Party deleted')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _openLedger(Map<String, dynamic> party) async {
    final id = (party['id'] as num).toInt();
    final loans = await LoansService.getLoansForParty(id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '${party['name']} • Ledger',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
              Expanded(
                child: loans.isEmpty
                    ? const Center(child: Text('No loan history for this party.'))
                    : ListView.separated(
                        itemCount: loans.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final loan = loans[index];
                          return ListTile(
                            title: Text(
                              '${loan.loanType == 'given' ? 'Loan Given' : 'Loan Taken'} • ${loan.currency} ${loan.amount.toStringAsFixed(2)}',
                            ),
                            subtitle: Text(
                              'Outstanding: ${loan.currency} ${_money(loan.remainingAmount)} • ${loan.lendingDate}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.pop(context);
                              widget.onLoanTap(loan);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _parties.where((party) {
      final query = _search.trim().toLowerCase();
      return query.isEmpty ||
          (party['name']?.toString().toLowerCase().contains(query) ?? false) ||
          (party['phone']?.toString().toLowerCase().contains(query) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Parties'),
        actions: [
          IconButton(
            onPressed: () => _editParty(),
            tooltip: 'Add Party',
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: 'Search parties',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(() => _search = ''),
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(_search.isEmpty
                            ? 'No parties added yet.'
                            : 'No matching parties found.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final party = filtered[index];
                          return FutureBuilder<Map<String, dynamic>>(
                            future: LoansService.getPartySummary(
                              (party['id'] as num).toInt(),
                            ),
                            builder: (context, snapshot) {
                              final balances = (snapshot.data?['balances']
                                      as List<dynamic>?) ??
                                  [];
                              final summary = balances.isEmpty
                                  ? 'No loan history yet'
                                  : balances.map((item) {
                                      final amount =
                                          (item['outstanding'] as num?) ?? 0;
                                      final type = item['loan_type'] == 'given'
                                          ? 'Receivable'
                                          : 'Payable';
                                      return '${item['currency']} $type: ${_money(amount)}';
                                    }).join('  •  ');
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person_outline),
                                ),
                                title: Text(party['name']?.toString() ?? ''),
                                subtitle: Text(
                                  [
                                    'Currency: ${(party['currency']?.toString() ?? 'PKR').toUpperCase()}',
                                    if ((party['phone'] ?? '').toString().isNotEmpty)
                                      party['phone'].toString(),
                                    summary,
                                  ].join('\n'),
                                ),
                                isThreeLine: true,
                                onTap: () => _openLedger(party),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') _editParty(party);
                                    if (value == 'delete') _deleteParty(party);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        dense: true,
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text('Edit'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        dense: true,
                                        leading: Icon(Icons.delete_outline, color: Colors.red),
                                        title: Text('Delete'),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editParty(),
        icon: const Icon(Icons.add),
        label: const Text('Add Party'),
      ),
    );
  }
}
