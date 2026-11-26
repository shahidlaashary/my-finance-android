import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';
import 'package:my_finance/modules/finance/models/loans_model.dart';
import 'package:my_finance/modules/finance/models/repayment_model.dart';
import 'package:my_finance/modules/finance/screens/loan_repayment_entry_form.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';
import 'package:my_finance/modules/finance/services/assets_service.dart';
import 'package:my_finance/modules/parties/services/party_service.dart';
import 'package:my_finance/core/files/attachment_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/modules/finance/screens/finance_graph_screens.dart';
import 'package:my_finance/modules/parties/screens/manage_parties_screen.dart';
/// Loans list, receivable/payable records aur loan actions ki main screen hai.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => LoansScreenState();
}
class LoansScreenState extends State<LoansScreen> {
  List<LoansModel> _loans = [];
  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _parties = [];
  Map<int, String> _assetNames = {};
  Map<String, double> _outstandingByCurrency = {};
  bool _loading = true;
  bool _hideBalances = false;
  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _loadData();
  }
  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    super.dispose();
  }
  String _dateString(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
  String _money(double amount) => _hideBalances ? '••••••' : amount.toStringAsFixed(2);
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
  void _onAppDataChanged() {
    if (mounted) _loadData();
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
      final wallets = await WalletService.getWallets();
      final loans = await LoansService.getLoans();
      final parties = await PartyService.getParties();
      final outstandingByCurrency =
          await LoansService.getTotalOutstandingByCurrency();
      final assetNames = <int, String>{};
      try {
        assetNames.addAll(await AssetsService().getAssetNames());
      } catch (_) {
        // Asset section pehli dafa open hone se pehle assets table shayad create na hui ho.
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
        builder: (_) => ManageParties(
          hideBalances: _hideBalances,
          onLoanTap: (loan) => _showLoanDetails(loan),
        ),
      ),
    );
    await _loadData();
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
        Icon(icon, size: 17, color: Theme.of(context).hintColor),
        const SizedBox(width: 6),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(_displayLoanDate(value), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Color(0xFF263B32),
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

  Future<void> _editRepaymentEntry(LoansModel loan, RepaymentModel repayment) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => LoanRepaymentEntryForm(loan: loan, existingRepayment: repayment),
    );
    if (saved == true) {
      await _loadData();
      if (!mounted) return;
      final refreshed = _loans.where((item) => item.id == loan.id);
      if (refreshed.isNotEmpty) {
        Navigator.of(context).pop();
        await _showLoanDetails(refreshed.first);
      }
      if (mounted) _showMessage('Repayment entry updated successfully.');
    }
  }

  Future<void> _showRepaymentAttachments(int repaymentId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          child: SingleChildScrollView(
            child: AttachmentSection(
              ownerType: AttachmentOwnerTypes.repayment,
              ownerId: repaymentId,
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _addRepayment(LoansModel loan) async {
    if (loan.id == null || loan.remainingAmount <= 0) return false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => LoanRepaymentEntryForm(loan: loan),
    );
    if (saved == true) {
      await _loadData();
      if (mounted) _showMessage('Repayment saved successfully.');
      return true;
    }
    return false;
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
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Edit Loan', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Loan Amount (${loan.currency})')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async { final date = await _pickDate(lendingDate); if (date != null) setSheetState(() => lendingDate = date); },
                        icon: Icon(Icons.calendar_month_outlined, size: 18),
                        label: Text('Start: ${_dateString(lendingDate)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async { final date = await _pickDate(dueDate ?? lendingDate); if (date != null) setSheetState(() => dueDate = date); },
                        icon: Icon(Icons.event_outlined, size: 18),
                        label: Text(dueDate == null ? 'Set Due Date' : 'Due: ${_dateString(dueDate!)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                    ]),
                    if (dueDate != null) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setSheetState(() => dueDate = null), child: Text('Clear Due Date'))),
                    const SizedBox(height: 8),
                    TextField(controller: notesController, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
                    const SizedBox(height: 10),
                    AttachmentSection(
                      ownerType: AttachmentOwnerTypes.loan,
                      ownerId: loan.id!,
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext, false), child: Text('Cancel'))),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(sheetContext, true), child: Text('Save Changes'))),
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
      await SoundSettingsService.instance.play('update');
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
        : Theme.of(context).colorScheme.primary;
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
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(_partyNameForLoan(loan),
                              style: TextStyle(fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20)),
                            child: Text(statusLabel, style: TextStyle(
                              color: statusColor, fontSize: 11,
                              fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 2),
                          PopupMenuButton<String>(
                            tooltip: 'Loan options',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: Icon(Icons.more_vert_rounded, size: 21, color: Color(0xFF536987)),
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
                                PopupMenuItem(value: 'delete', child: Row(
                                  children: [Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error), SizedBox(width: 10), Text('Delete')],
                                )),
                            ],
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          '${loan.loanType == 'given' ? 'Loan Given' : 'Loan Taken'} • ${loan.currency.toUpperCase()}',
                          style: TextStyle(fontSize: 12,
                            color: Theme.of(context).hintColor, fontWeight: FontWeight.w600),
                        ),
                        if (_partyPhoneForLoan(loan) != '-')
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(_partyPhoneForLoan(loan),
                              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                          ),
                        if (loan.isAssetLinked)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Asset: ${_assetReferenceLabel(loan)}',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                          ),
                        const SizedBox(height: 3),
                        Text(_moneyWithLoanCurrency(loan.amount, loan),
                          style: TextStyle(fontSize: 25,
                            fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                        const SizedBox(height: 4),
                        Text('Total Loan Amount',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                        const SizedBox(height: 3),
                        Row(children: [
                          Expanded(child: _loanDetailMetric(
                            'Repaid', _moneyWithLoanCurrency(loan.repaidAmount, loan))),
                          const SizedBox(width: 12),
                          Expanded(child: _loanDetailMetric(
                            'Remaining', _moneyWithLoanCurrency(loan.remainingAmount, loan))),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          Expanded(child: Text('Repayment Progress',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                          Text('${(progress * 100).round()}%',
                            style: TextStyle(fontSize: 12, color: statusColor,
                              fontWeight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress, minHeight: 7,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              loan.isOverdue ? const Color(0xFFE34D59) : const Color(0xFF28B879)),
                          ),
                        ),
                        const SizedBox(height: 3),
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
                            color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
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
                              onPressed: () async {
                                final saved = await _addRepayment(loan);
                                if (!saved || !pageContext.mounted || !mounted) return;
                                final refreshedLoans = _loans.where(
                                  (item) => item.id == loan.id,
                                );
                                if (refreshedLoans.isNotEmpty) {
                                  Navigator.pop(pageContext);
                                  await _showLoanDetails(refreshedLoans.first);
                                }
                              },
                              icon: Icon(Icons.payments_outlined),
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  )),
                  FutureBuilder<List<RepaymentModel>>(
                    future: LoansService.getRepayments(loan.id!),
                    builder: (context, snapshot) => Text(
                      snapshot.hasData ? '${snapshot.data!.length} entries' : '',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
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
                          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(children: [
                            Icon(Icons.receipt_long_outlined,
                              size: 32, color: Theme.of(context).hintColor),
                            const SizedBox(height: 8),
                            Text('No payment entries yet',
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
                            color: Theme.of(context).colorScheme.onPrimary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Payment',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: Theme.of(context).hintColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            repayment.repaymentDate,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: Theme.of(context).hintColor,
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
                                        if (repayment.walletCurrency.toUpperCase() != loan.currency.toUpperCase()) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Paid: ${repayment.walletCurrency} ${_money(repayment.walletAmount)}',
                                            maxLines: 1,
                                            style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
                                          ),
                                          if (repayment.exchangeRate > 0)
                                            Text(
                                              'Rate: 1 ${loan.currency} = ${repayment.walletCurrency} ${repayment.exchangeRate.toStringAsFixed(4)}',
                                              maxLines: 1,
                                              style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor),
                                            ),
                                        ],
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
                                            icon: Icon(
                                              Icons.more_horiz,
                                              color: Theme.of(context).hintColor,
                                              size: 19,
                                            ),
                                            onSelected: (value) async {
                                              if (value == 'edit') {
                                                await _editRepaymentEntry(loan, repayment);
                                                return;
                                              }
                                              if (value == 'attachments') {
                                                await _showRepaymentAttachments(repayment.id!);
                                                return;
                                              }
                                              if (value != 'delete') return;
                                              final confirm = await showDialog<bool>(
                                                context: pageContext,
                                                builder: (dialogContext) => AlertDialog(
                                                  title: Text('Delete Payment?'),
                                                  content: Text(
                                                    'This will reverse the wallet balance and loan balance.'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(dialogContext, false),
                                                      child: Text('Cancel'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(dialogContext, true),
                                                      child: Text('Delete'),
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
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_outlined, size: 18),
                                                    SizedBox(width: 9),
                                                    Text('Edit Entry'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'attachments',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.attach_file, size: 18),
                                                    SizedBox(width: 9),
                                                    Text('Attachments'),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
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
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor,
          fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface)),
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
      await SoundSettingsService.instance.play('delete_warning');
      final repayments = await LoansService.getRepayments(loan.id!);
      await LoansService.deleteLoan(loan.id!);
      await SoundSettingsService.instance.play('delete_success');
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: GeneralPreferences.instance.personalizedHeaderTitle(context, Text(appText(context, 'Loans & Repayments', 'قرضے اور واپسی'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface))),
        actions: buildSharedAppBarActions(context),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    height: 110,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Theme.of(context).colorScheme.primary, Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .20)!, Theme.of(context).colorScheme.primaryContainer],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35)),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
                          blurRadius: 16,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.account_balance_wallet_rounded,
                                color: Theme.of(context).colorScheme.onPrimary, size: 18),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appText(context, 'Total Outstanding', 'Total Outstanding'),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Across all currencies',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.72),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'View loans analytics',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(builder: (_) => LoanGraphScreen(hideBalances: _hideBalances)),
                              ),
                              icon: Icon(Icons.trending_up_rounded,
                                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8), size: 22),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: 36,
                          child: _outstandingByCurrency.isEmpty
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    appText(context, 'No outstanding loans.', 'No outstanding loans.'),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.82),
                                      fontSize: 11,
                                    ),
                                  ),
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _outstandingByCurrency.entries.map((entry) {
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Container(
                                          width: 142,
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.10),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.08),
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.key,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onPrimary,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              Text(
                                                _money(entry.value),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onPrimary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 1),
                        Container(
                          padding: const EdgeInsets.only(top: 3),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.22))),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(Icons.receipt_long_rounded, color: Color(0xFFBCEBD7), size: 13),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text('Total Loans  ${_loans.length}',
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 9, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Color(0xFFFFD18A), size: 13),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text('Overdue  $overdueCount',
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                      OutlinedButton(
                        onPressed: _showParties,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_alt_outlined, size: 16),
                            const SizedBox(width: 3),
                            Text('Manage Party (${_parties.length})'),
                          ],
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
                            Icon(Icons.handshake_outlined, size: 55, color: Theme.of(context).colorScheme.primary),
                            SizedBox(height: 12),
                            Text(appText(context, 'No loans added yet.', 'ابھی کوئی قرض شامل نہیں کیا گیا۔'), textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._loans.map((loan) {
                      final progress = loan.amount <= 0 ? 0.0 :
                          (loan.repaidAmount / loan.amount).clamp(0.0, 1.0).toDouble();
                      final statusLabel = loan.isPaid
                          ? appText(context, 'Paid', 'ادا شدہ')
                          : loan.isOverdue
                              ? appText(context, 'Overdue', 'میعاد ختم')
                              : appText(context, 'Active', 'فعال');
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Theme.of(context).colorScheme.onPrimary,
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
                                              style: TextStyle(
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
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF5B6F91),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Transform.translate(
                                        offset: const Offset(0, -9),
                                        child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
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
                                      const SizedBox(width: 4),
                                      Transform.translate(
                                        offset: const Offset(0, -9),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 23,
                                          color: Color(0xFF536987),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 102,
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
                                                    style: TextStyle(fontSize: 21),
                                                  ),
                                                  const SizedBox(width: 7),
                                                  Text(
                                                    loan.currency.toUpperCase(),
                                                    style: TextStyle(
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
                                                        style: TextStyle(
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
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF536987),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Remaining: ${_money(loan.remainingAmount)}',
                                                    style: TextStyle(
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
                                                   icon: Icon(Icons.payments_outlined, size: 17),
                                                   label: Text(
                                                     loan.loanType == 'given' ? 'Receive' : 'Pay Back',
                                                     style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
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
