import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
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
  String _currencyFlag(String currency) {
    switch (currency.trim().toUpperCase()) {
      case 'PKR':
        return '🇵🇰';
      case 'AED':
        return '🇦🇪';
      case 'USD':
        return '🇺🇸';
      case 'GBP':
        return '🇬🇧';
      case 'EUR':
        return '🇪🇺';
      case 'SAR':
        return '🇸🇦';
      case 'INR':
        return '🇮🇳';
      case 'CAD':
        return '🇨🇦';
      case 'AUD':
        return '🇦🇺';
      default:
        return '🌐';
    }
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
    if (createNewParty) {
      final matching = _wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == newPartyCurrency);
      walletId = matching.isEmpty ? null : (matching.first['id'] as num).toInt();
    }
    final List<XFile> pendingLoanImages = [];
    final List<PlatformFile> pendingLoanPdfs = [];
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
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _nameController,
                                        textCapitalization: TextCapitalization.words,
                                        decoration: const InputDecoration(labelText: 'Party Name *'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller: _phoneController,
                                        keyboardType: TextInputType.phone,
                                        decoration: const InputDecoration(labelText: 'Phone Number'),
                                      ),
                                    ),
                                  ],
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
                                    TextButton.icon(
                                      onPressed: () async {
                                        final result = await FilePicker.platform.pickFiles(
                                          type: FileType.custom,
                                          allowedExtensions: ['pdf'],
                                          allowMultiple: true,
                                        );
                                        if (result != null) {
                                          setSheetState(() => pendingLoanPdfs.addAll(
                                            result.files.where((file) => file.path != null),
                                          ));
                                        }
                                      },
                                      icon: const Icon(Icons.picture_as_pdf_outlined),
                                      label: const Text('PDF'),
                                    ),
                                  ]),
                                  if (pendingLoanImages.isNotEmpty)
                                    Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 6, runSpacing: 4, children: pendingLoanImages.asMap().entries.map((entry) => Chip(
                                      avatar: const Icon(Icons.image_outlined, size: 16),
                                      label: SizedBox(width: 105, child: Text(entry.value.name, overflow: TextOverflow.ellipsis)),
                                      onDeleted: () => setSheetState(() => pendingLoanImages.removeAt(entry.key)),
                                    )).toList())),
                                  if (pendingLoanPdfs.isNotEmpty)
                                    Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 6, runSpacing: 4, children: pendingLoanPdfs.asMap().entries.map((entry) => Chip(
                                      avatar: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                      label: SizedBox(width: 105, child: Text(entry.value.name, overflow: TextOverflow.ellipsis)),
                                      onDeleted: () => setSheetState(() => pendingLoanPdfs.removeAt(entry.key)),
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
      for (final pdf in pendingLoanPdfs) {
        final path = pdf.path;
        if (path == null) continue;
        await AttachmentService.addAttachment(
          ownerType: AttachmentOwnerTypes.loan,
          ownerId: loanId,
          sourcePath: path,
          originalFileName: pdf.name,
        );
      }
      _selectedWalletId = walletId;
      await _loadData();
      _showMessage('Loan saved successfully.');
    } catch (error) {
      _showMessage('Could not save loan: $error');
    }
  }
  String _displayLoanDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.year}';
  }

  Widget _loanDateInfo(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF71877C)),
        const SizedBox(width: 6),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF71877C),
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(_displayLoanDate(value), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF263B32),
                fontWeight: FontWeight.w700)),
          ],
        )),
      ],
    );
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
  Future<bool> _editLoan(LoansModel loan) async {
    if (loan.id == null || loan.isAssetLinked) {
      _showMessage('Asset-linked loans must be edited from Asset Section.');
      return false;
    }
    final amountController = TextEditingController(text: loan.amount.toStringAsFixed(2));
    final notesController = TextEditingController(text: loan.notes);
    DateTime lendingDate = DateTime.tryParse(loan.lendingDate) ?? DateTime.now();
    DateTime? dueDate = loan.dueDate == null ? null : DateTime.tryParse(loan.dueDate!);
    bool saved = false;
    try {
      saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Edit Loan', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Loan Amount (${loan.currency})')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async { final date = await _pickDate(lendingDate); if (date != null) setSheetState(() => lendingDate = date); },
                        icon: const Icon(Icons.calendar_month_outlined, size: 18),
                        label: Text('Start: ${_dateString(lendingDate)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async { final date = await _pickDate(dueDate ?? lendingDate); if (date != null) setSheetState(() => dueDate = date); },
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(dueDate == null ? 'Set Due Date' : 'Due: ${_dateString(dueDate!)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                    ]),
                    if (dueDate != null) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setSheetState(() => dueDate = null), child: const Text('Clear Due Date'))),
                    const SizedBox(height: 8),
                    TextField(controller: notesController, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
                    const SizedBox(height: 10),
                    AttachmentSection(
                      ownerType: AttachmentOwnerTypes.loan,
                      ownerId: loan.id!,
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext, false), child: const Text('Cancel'))),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('Save Changes'))),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ) ?? false;
      if (!saved) return false;
      final amount = double.tryParse(amountController.text.trim());
      if (amount == null || !amount.isFinite || amount <= 0) {
        _showMessage('Enter a valid loan amount.');
        return false;
      }
      await LoansService.updateLoanDetails(
        loanId: loan.id!,
        amount: amount,
        lendingDate: _dateString(lendingDate),
        dueDate: dueDate == null ? null : _dateString(dueDate!),
        notes: notesController.text.trim(),
      );
      await _loadData();
      _showMessage('Loan updated successfully.');
      return true;
    } catch (error) {
      _showMessage('Could not update loan: $error');
      return false;
    } finally {
      amountController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _showLoanDetails(LoansModel loan) async {
    if (loan.id == null) return;
    final progress = loan.amount <= 0
        ? 0.0
        : (loan.repaidAmount / loan.amount).clamp(0.0, 1.0).toDouble();
    final statusColor = loan.isOverdue
        ? const Color(0xFFD94841)
        : const Color(0xFF147D59);
    final statusLabel = loan.isPaid
        ? 'Paid'
        : loan.isOverdue
            ? 'Overdue'
            : 'Active';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          appBar: AppBar(
            title: Text(appText(context, 'Loan Details', 'Loan Details')),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Card(
                  elevation: 2,
                  shadowColor: const Color(0xFF173D2E).withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFFE7ECE9)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(_partyNameForLoan(loan),
                              style: const TextStyle(fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF172B25))),
                          ),
                          Transform.translate(
                            offset: const Offset(5, 0),
                            child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20)),
                            child: Text(statusLabel, style: TextStyle(
                              color: statusColor, fontSize: 11,
                              fontWeight: FontWeight.w700)),
                          ),
                          ),
                          const SizedBox(width: 1),
                          Transform.translate(
                            offset: const Offset(5, 0),
                            child: PopupMenuButton<String>(
                            tooltip: 'Loan options',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                            icon: const Icon(Icons.more_vert_rounded, size: 21, color: Color(0xFF536987)),
                            onSelected: (value) async {
                              if (value == 'edit') {
                                final updated = await _editLoan(loan);
                                if (updated && pageContext.mounted) {
                                  Navigator.pop(pageContext);
                                  final refreshed = _loans.where((item) => item.id == loan.id);
                                  if (refreshed.isNotEmpty && mounted) {
                                    await _showLoanDetails(refreshed.first);
                                  }
                                }
                              } else if (value == 'delete') {
                                await _deleteLoan(loan);
                                if (pageContext.mounted && !mounted) return;
                                if (pageContext.mounted && loan.id != null) {
                                  final stillExists = _loans.any((item) => item.id == loan.id);
                                  if (!stillExists) Navigator.pop(pageContext);
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              if (!loan.isAssetLinked)
                                const PopupMenuItem(value: 'edit', child: Row(
                                  children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('Edit')],
                                )),
                              if (!loan.isAssetLinked)
                                const PopupMenuItem(value: 'delete', child: Row(
                                  children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10), Text('Delete')],
                                )),
                            ],
                          ),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          '${loan.loanType == 'given' ? 'Loan Given' : 'Loan Taken'} • ${loan.currency.toUpperCase()}',
                          style: const TextStyle(fontSize: 12,
                            color: Color(0xFF65736C), fontWeight: FontWeight.w600),
                        ),
                        if (_partyPhoneForLoan(loan) != '-')
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(_partyPhoneForLoan(loan),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7B8781))),
                          ),
                        if (loan.isAssetLinked)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Asset: ${_assetReferenceLabel(loan)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF65736C))),
                          ),
                        const SizedBox(height: 5),
                        Text(_moneyWithLoanCurrency(loan.amount, loan),
                          style: const TextStyle(fontSize: 25,
                            fontWeight: FontWeight.w800, color: Color(0xFF172B25))),
                        const SizedBox(height: 4),
                        Text('Total Loan Amount',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 5),
                        Row(children: [
                          Expanded(child: _loanDetailMetric(
                            'Repaid', _moneyWithLoanCurrency(loan.repaidAmount, loan))),
                          const SizedBox(width: 12),
                          Expanded(child: _loanDetailMetric(
                            'Remaining', _moneyWithLoanCurrency(loan.remainingAmount, loan))),
                        ]),
                        const SizedBox(height: 5),
                        Row(children: [
                          const Expanded(child: Text('Repayment Progress',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                          Text('${(progress * 100).round()}%',
                            style: TextStyle(fontSize: 12, color: statusColor,
                              fontWeight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress, minHeight: 9,
                            backgroundColor: const Color(0xFFE8EFEB),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              loan.isOverdue ? const Color(0xFFE34D59) : const Color(0xFF28B879)),
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Divider(height: 1),
                        const SizedBox(height: 5),
                        Row(children: [
                          Expanded(child: _loanDetailMetric(
                            loan.loanType == 'given' ? 'Lending Date' : 'Borrowing Date',
                            _displayLoanDate(loan.lendingDate))),
                          const SizedBox(width: 12),
                          Expanded(child: _loanDetailMetric('Due Date', loan.dueDate == null ? '-' : _displayLoanDate(loan.dueDate!))),
                        ]),
                        if (loan.notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Notes', style: TextStyle(fontSize: 11,
                            color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(loan.notes),
                        ],
                        FutureBuilder(
                          future: AttachmentService.getLoanAttachments(loan.id!),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState != ConnectionState.done ||
                                (snapshot.data?.isEmpty ?? true)) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: AttachmentSection(
                                ownerType: AttachmentOwnerTypes.loan,
                                ownerId: loan.id!,
                                readOnly: true,
                              ),
                            );
                          },
                        ),
                        if (!loan.isPaid) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(pageContext);
                                _addRepayment(loan);
                              },
                              icon: const Icon(Icons.payments_outlined),
                              label: Text(loan.loanType == 'given'
                                ? 'Receive Repayment' : 'Pay Back Loan'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: Text(
                    appText(context, 'Payment Entries', 'Payment Entries'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  )),
                  FutureBuilder<List<RepaymentModel>>(
                    future: LoansService.getRepayments(loan.id!),
                    builder: (context, snapshot) => Text(
                      snapshot.hasData ? '${snapshot.data!.length} entries' : '',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                FutureBuilder<List<RepaymentModel>>(
                  future: LoansService.getRepayments(loan.id!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text('Could not load payment entries: ${snapshot.error}');
                    }
                    final repayments = snapshot.data ?? [];
                    if (repayments.isEmpty) {
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE7ECE9))),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(children: [
                            Icon(Icons.receipt_long_outlined,
                              size: 32, color: Colors.grey.shade500),
                            const SizedBox(height: 8),
                            const Text('No payment entries yet',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      );
                    }
                    return Column(
                      children: repayments.map((repayment) {
                        final repaymentColor = loan.loanType == 'given'
                            ? const Color(0xFF159B65)
                            : const Color(0xFFE45B5B);
                        final repaymentIcon = loan.loanType == 'given'
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded;
                        return Container(
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
                            padding: const EdgeInsets.fromLTRB(10, 9, 5, 9),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: repaymentColor.withValues(alpha: 0.11),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(repaymentIcon,
                                        color: repaymentColor, size: 21),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            repayment.notes.trim().isNotEmpty
                                                ? repayment.notes.trim()
                                                : 'Loan Repayment',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF25332C),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          const Text(
                                            'Payment',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFF7B8781),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            repayment.repaymentDate,
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
                                    const SizedBox(width: 4),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _moneyWithLoanCurrency(repayment.amount, loan),
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            color: repaymentColor,
                                          ),
                                        ),
                                        if (repayment.id != null)
                                          PopupMenuButton<String>(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 145),
                                            iconSize: 19,
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(30, 28),
                                              maximumSize: const Size(30, 28),
                                              padding: EdgeInsets.zero,
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            icon: const Icon(
                                              Icons.more_horiz,
                                              color: Color(0xFF89958E),
                                              size: 19,
                                            ),
                                            onSelected: (value) async {
                                              if (value != 'delete') return;
                                              final confirm = await showDialog<bool>(
                                                context: pageContext,
                                                builder: (dialogContext) => AlertDialog(
                                                  title: const Text('Delete Payment?'),
                                                  content: const Text(
                                                    'This will reverse the wallet balance and loan balance.'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(dialogContext, false),
                                                      child: const Text('Cancel'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(dialogContext, true),
                                                      child: const Text('Delete'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true && repayment.id != null) {
                                                await LoansService.deleteRepayment(repayment.id!);
                                                await AttachmentService.deleteOwnerAttachments(
                                                  ownerType: AttachmentOwnerTypes.repayment,
                                                  ownerId: repayment.id!,
                                                );
                                                await _loadData();
                                                if (pageContext.mounted) Navigator.pop(pageContext);
                                                if (mounted) _showMessage('Payment entry deleted.');
                                              }
                                            },
                                            itemBuilder: (context) => const [
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                                    SizedBox(width: 9),
                                                    Text('Delete'),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (repayment.id != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 49, top: 3),
                                    child: AttachmentSection(
                                      ownerType: AttachmentOwnerTypes.repayment,
                                      ownerId: repayment.id!,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loanDetailMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600,
          fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: Color(0xFF172B25))),
      ],
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(appText(context, "All Loans", "All Loans"),
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showParties,
                        icon: const Icon(Icons.people_alt_outlined, size: 17),
                        label: Text('Manage Party (${_parties.length})'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
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
                      final progress = loan.amount <= 0 ? 0.0 :
                          (loan.repaidAmount / loan.amount).clamp(0.0, 1.0).toDouble();
                      final statusColor = loan.isOverdue
                          ? const Color(0xFFD94841) : const Color(0xFF147D59);
                      final statusLabel = loan.isPaid
                          ? appText(context, 'Paid', 'ادا شدہ')
                          : loan.isOverdue
                              ? appText(context, 'Overdue', 'میعاد ختم')
                              : appText(context, 'Active', 'فعال');
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Colors.white,
                        shadowColor: const Color(0xFF173D2E).withValues(alpha: 0.10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: const BorderSide(color: Color(0xFFE5ECF3)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => _showLoanDetails(loan),
                          child: SizedBox(
                            height: 182,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: loan.isAssetLinked
                                              ? const Color(0xFFFFE8ED)
                                              : loan.loanType == 'taken'
                                                  ? const Color(0xFFE4F0FF)
                                                  : const Color(0xFFF0E9FF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          loan.isAssetLinked
                                              ? Icons.home_rounded
                                              : loan.loanType == 'taken'
                                                  ? Icons.account_balance_rounded
                                                  : Icons.person_rounded,
                                          color: loan.isAssetLinked
                                              ? const Color(0xFFD92D48)
                                              : loan.loanType == 'taken'
                                                  ? const Color(0xFF1763A8)
                                                  : const Color(0xFF7252C7),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _partyNameForLoan(loan),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF101D3A),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              loan.isAssetLinked
                                                  ? 'Asset • ${_assetReferenceLabel(loan)}'
                                                  : loan.loanType == 'given'
                                                      ? 'Loan Given'
                                                      : 'Loan Taken',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF5B6F91),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Transform.translate(
                                        offset: const Offset(0, -2),
                                        child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: loan.isPaid
                                              ? const Color(0xFFE8F1FF)
                                              : loan.isOverdue
                                                  ? const Color(0xFFFFE9ED)
                                                  : const Color(0xFFE7F8ED),
                                          borderRadius: BorderRadius.circular(22),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: loan.isPaid
                                                    ? const Color(0xFF2674E8)
                                                    : loan.isOverdue
                                                        ? const Color(0xFFEA263F)
                                                        : const Color(0xFF159B55),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              statusLabel,
                                              style: TextStyle(
                                                color: loan.isPaid
                                                    ? const Color(0xFF2674E8)
                                                    : loan.isOverdue
                                                        ? const Color(0xFFDA233C)
                                                        : const Color(0xFF11864A),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ),
                                      const SizedBox(width: 7),
                                      Transform.translate(
                                        offset: const Offset(0, -2),
                                        child: const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 23,
                                          color: Color(0xFF536987),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 96,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 8,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    _currencyFlag(loan.currency),
                                                    style: const TextStyle(fontSize: 21),
                                                  ),
                                                  const SizedBox(width: 7),
                                                  Text(
                                                    loan.currency.toUpperCase(),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF526987),
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 9),
                                                  Container(
                                                    width: 1,
                                                    height: 22,
                                                    color: const Color(0xFFCAD5E3),
                                                  ),
                                                  const SizedBox(width: 9),
                                                  Expanded(
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment: Alignment.centerLeft,
                                                      child: Text(
                                                        _money(loan.amount),
                                                        style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.w800,
                                                          color: Color(0xFF101D3A),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 5),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(20),
                                                      child: LinearProgressIndicator(
                                                        value: progress,
                                                        minHeight: 9,
                                                        backgroundColor: const Color(0xFFE8EDF4),
                                                        valueColor: AlwaysStoppedAnimation<Color>(
                                                          loan.isOverdue
                                                              ? const Color(0xFFEF3155)
                                                              : const Color(0xFF25B875),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '${(progress * 100).round()}%',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w800,
                                                      color: loan.isOverdue
                                                          ? const Color(0xFFEF3155)
                                                          : const Color(0xFF159E61),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Repaid: ${_money(loan.repaidAmount)}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF536987),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Remaining: ${_money(loan.remainingAmount)}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF536987),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          width: 1,
                                          height: 88,
                                          color: const Color(0xFFE0E8F1),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _loanDateInfo(
                                                Icons.calendar_month_rounded,
                                                'Start Date',
                                                loan.lendingDate,
                                              ),
                                              const SizedBox(height: 8),
                                              _loanDateInfo(
                                                Icons.event_available_rounded,
                                                'Next Due',
                                                loan.dueDate ?? 'Not set',
                                              ),
                                              const SizedBox(height: 5),
                                               if (!loan.isPaid)
                                                 TextButton.icon(
                                                   style: TextButton.styleFrom(
                                                     visualDensity: VisualDensity.compact,
                                                     padding: const EdgeInsets.symmetric(horizontal: 4),
                                                     minimumSize: const Size(0, 26),
                                                     tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                     foregroundColor: const Color(0xFF1763A8),
                                                   ),
                                                   onPressed: () => _addRepayment(loan),
                                                   icon: const Icon(Icons.payments_outlined, size: 17),
                                                   label: Text(
                                                     loan.loanType == 'given' ? 'Receive' : 'Pay Back',
                                                     style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                                                   ),
                                                 ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(height: 1, color: Color(0xFFE7EDF4)),
                                ],
                              ),
                            ),
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
