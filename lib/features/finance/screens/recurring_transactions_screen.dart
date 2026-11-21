import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/finance/models/recurring_transaction_model.dart';
import 'package:my_finance/features/finance/services/recurring_transaction_service.dart';
import 'package:my_finance/features/finance/services/category_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/core/services/attachment_service.dart';

class RecurringTransactionsScreen extends StatefulWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  State<RecurringTransactionsScreen> createState() =>
      _RecurringTransactionsScreenState();
}

class _RecurringTransactionsScreenState
    extends State<RecurringTransactionsScreen> {
  final RecurringTransactionService _service =
      RecurringTransactionService();

  List<RecurringTransactionModel> _items = [];
  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _categories = [];

  bool _loading = true;
  bool _hideBalances = false;

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _loadData();
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
      // Wallets ke liye app ka central database connection istemal karte hain.
      final db = FinanceDB.instance.db;

      final wallets = await db.query(
        'wallets',
        orderBy: 'name ASC',
      );

      final categoryItems = [
        ...await CategoryService.getCategories('income'),
        ...await CategoryService.getCategories('expense'),
      ];
      final categories = categoryItems
          .map((item) => {'name': item.name, 'type': item.type})
          .toList();

      final items = await _service.getRecurringTransactions();

      if (!mounted) return;

      setState(() {
        _hideBalances = hideBalances;
        _wallets = wallets;
        _categories = categories;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      _showMessage('Data load error: $e', isError: true);
    }
  }

  String _money(double amount, String currency) {
    return '$currency ${_hideBalances ? '••••••' : amount.toStringAsFixed(2)}';
  }

  String _date(DateTime? value) {
    if (value == null) return 'Not set';

    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }

  String _walletName(int? id) {
    if (id == null) return 'Unknown wallet';

    final matches = _wallets.where(
      (wallet) => wallet['id'] == id,
    );

    if (matches.isEmpty) return 'Unknown wallet';

    return matches.first['name'].toString();
  }

  String _currency(int? id) {
    if (id == null) return '';

    final matches = _wallets.where(
      (wallet) => wallet['id'] == id,
    );

    if (matches.isEmpty) return '';

    return (matches.first['currency'] ?? 'PKR').toString();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _processDue() async {
    try {
      final count = await _service.processDueTransactions();

      await _loadData();

      final failed = _service.lastProcessingErrors;
      if (failed.isEmpty) {
        _showMessage('$count recurring transaction(s) processed.');
      } else {
        _showMessage(
          '$count transaction(s) processed; ${failed.length} schedule(s) paused due to errors. Open and edit them, then resume.',
          isError: true,
        );
      }
    } catch (e) {
      _showMessage('Processing failed: $e', isError: true);
    }
  }

  Future<void> _toggleStatus(
    RecurringTransactionModel item,
  ) async {
    if (item.id == null) return;

    try {
      await _service.setRecurringTransactionStatus(
        item.id!,
        !item.isActive,
      );

      await _loadData();
    } catch (e) {
      _showMessage('Status update failed: $e', isError: true);
    }
  }

  Future<void> _deleteItem(
    RecurringTransactionModel item,
  ) async {
    if (item.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText(context, "Delete Schedule", "Delete Schedule")),
        content: Text(appText(context, "Are you sure you want to delete this recurring schedule?", "Are you sure you want to delete this recurring schedule?"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(appText(context, "Delete", "Delete")),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AttachmentService.deleteOwnerAttachments(ownerType: 'recurring', ownerId: item.id!);
      await SoundSettingsService.instance.play('delete_warning');
      await _service.deleteRecurringTransaction(item.id!);
      await SoundSettingsService.instance.play('delete_success');
      await _loadData();
      _showMessage('Schedule deleted successfully.');
    } catch (e) {
      await SoundSettingsService.instance.play('error');
      _showMessage('Delete failed: $e', isError: true);
    }
  }

  Future<void> _openForm({
    RecurringTransactionModel? existing,
  }) async {
    if (_wallets.isEmpty) {
      _showMessage(
        'Please create an wallet before adding a recurring transaction.',
        isError: true,
      );
      return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        // Fill the available sheet height while the keyboard is visible.
        // The modal route moves the sheet above the keyboard automatically.
        heightFactor: MediaQuery.of(context).viewInsets.bottom > 0 ? 1.0 : 0.94,
        child: _RecurringTransactionDialog(
          wallets: _wallets,
          categories: _categories,
          existing: existing,
        ),
      ),
    );

    if (result == true) {
      await _loadData();
    }
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.repeat,
              size: 65,
              color: Theme.of(context).hintColor,
            ),
            SizedBox(height: 15),
            Text(appText(context, "No recurring transactions yet", "No recurring transactions yet"),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(appText(context, "Create a schedule for regular income, expenses or transfers.", "Create a schedule for regular income, expenses or transfers."),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionCard(RecurringTransactionModel item) {
    final isIncome = item.type.toLowerCase() == 'income';
    final isTransfer = item.isTransfer;
    final scheme = Theme.of(context).colorScheme;
    final accent = isIncome ? scheme.tertiary : isTransfer ? scheme.primary : scheme.error;
    final icon = isIncome ? Icons.south_west_rounded : isTransfer ? Icons.swap_horiz_rounded : Icons.north_east_rounded;
    Widget detail(IconData glyph, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(glyph, size: 14, color: scheme.onSurfaceVariant),
      const SizedBox(width: 5),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500))),
    ]);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: const Color(0xFF183D2D).withOpacity(0.08),
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.75))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 9, 7, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: accent.withOpacity(.12), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 19, color: accent)),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('${item.type.toUpperCase()} · ${item.frequency.toUpperCase()}',
                style: TextStyle(fontSize: 10, letterSpacing: .3, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            ])),
            const SizedBox(width: 4),
            Text(_money(item.amount, _currency(item.walletId)), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: accent)),
          ]),
          const SizedBox(height: 7),
          Wrap(spacing: 10, runSpacing: 5, children: [
            detail(Icons.account_balance_wallet_outlined, isTransfer ? _walletName(item.walletId) + ' → ' + _walletName(item.toWalletId) : _walletName(item.walletId)),
            detail(Icons.repeat_rounded, 'Next: ${_date(item.nextRunDate)}'),
            if (!isTransfer && (item.category ?? '').trim().isNotEmpty)
              detail(Icons.category_outlined, item.category!.trim()),
            if (isTransfer && item.transferFee > 0)
              detail(Icons.payments_outlined, 'Fee: ${_money(item.transferFee, _currency(item.walletId))}'),
            detail(Icons.calendar_month_outlined, 'Start: ${_date(item.startDate)}'),
            detail(Icons.event_outlined, item.endDate == null ? 'No end date' : 'End: ${_date(item.endDate)}'),
          ]),
          if (item.note.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(item.note, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 3),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: item.isActive ? scheme.secondaryContainer : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
              child: Text(item.isActive ? 'ACTIVE' : 'PAUSED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                color: item.isActive ? scheme.onSecondaryContainer : scheme.onSurfaceVariant))),
            const Spacer(),
            IconButton(tooltip: 'Edit', visualDensity: VisualDensity.compact, onPressed: () => _openForm(existing: item),
              icon: Icon(Icons.edit_outlined, size: 18, color: scheme.primary)),
            IconButton(tooltip: item.isActive ? 'Pause' : 'Resume', visualDensity: VisualDensity.compact, onPressed: () => _toggleStatus(item),
              icon: Icon(item.isActive ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 19, color: scheme.onSurfaceVariant)),
            IconButton(tooltip: 'Delete', visualDensity: VisualDensity.compact, onPressed: () => _deleteItem(item),
              icon: Icon(Icons.delete_outline_rounded, size: 19, color: scheme.error)),
          ]),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _items.where((e) => e.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context, 'Recurring Transactions', 'بار بار ہونے والے لین دین')),
        actions: [
          IconButton(
            tooltip: appText(context, 'Add Schedule', 'شیڈول شامل کریں'),
            onPressed: _loading ? null : () => _openForm(),
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _items.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.65,
                          child: _emptyState(),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      children: [
                        Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.14)),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Theme.of(context).colorScheme.primaryContainer.withOpacity(0.72),
                                  Theme.of(context).colorScheme.surface,
                                ],
                              ),
                            ),
                            child: Row(children: [
                              Container(
                                width: 42, height: 42,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(Icons.event_repeat_rounded, size: 23, color: Theme.of(context).colorScheme.primary),
                              ),
                              const SizedBox(width: 11),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(appText(context, "Recurring Schedule", "Recurring Schedule"),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 3),
                                  Text('${_items.length} total schedules',
                                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ],
                              )),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Column(children: [
                                  Text('$activeCount', style: TextStyle(
                                    fontSize: 19, height: 1, fontWeight: FontWeight.w900,
                                    color: Theme.of(context).colorScheme.onSecondaryContainer)),
                                  const SizedBox(height: 3),
                                  Text(appText(context, "Active", "Active"), style: TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSecondaryContainer)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(appText(context, "Your Schedules", "Your Schedules"),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        ..._items.map(_transactionCard),
                        SizedBox(height: 16),
                      ],
                    ),
            ),
    );
  }
}

class _RecurringTransactionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> categories;
  final RecurringTransactionModel? existing;

  const _RecurringTransactionDialog({
    required this.wallets,
    required this.categories,
    this.existing,
  });

  @override
  State<_RecurringTransactionDialog> createState() =>
      _RecurringTransactionDialogState();
}

class _RecurringTransactionDialogState
    extends State<_RecurringTransactionDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _transferFeeController;
  late final TextEditingController _noteController;

  late String _type;
  late String _frequency;

  int? _walletId;
  int? _toWalletId;
  String? _category;

  late DateTime _startDate;
  DateTime? _endDate;

  bool _saving = false;
  bool _transferFeeEnabled = false;
  final List<Map<String, String>> _pendingAttachments = [];
  final ImagePicker _attachmentPicker = ImagePicker();

  bool get _isTransfer => _type == 'transfer';

  @override
  void initState() {
    super.initState();

    final item = widget.existing;

    _titleController = TextEditingController(
      text: item?.title ?? '',
    );

    _amountController = TextEditingController(
      text: item?.amount.toString() ?? '',
    );

    _transferFeeController = TextEditingController(
      text: item != null && item.transferFee > 0 ? item.transferFee.toString() : '',
    );
    _transferFeeEnabled = item != null && item.transferFee > 0;

    _noteController = TextEditingController(
      text: item?.note ?? '',
    );

    _type = item?.type.toLowerCase() ?? 'expense';
    _frequency = item?.frequency.toLowerCase() ?? 'monthly';

    _walletId = item?.walletId;
    _toWalletId = item?.toWalletId;
    _category = item?.category;

    _startDate = item?.startDate ?? DateTime.now();
    _endDate = item?.endDate;

    if (!_accountExists(_walletId)) {
      _walletId = null;
    }

    if (!_accountExists(_toWalletId)) {
      _toWalletId = null;
    }
  }

  bool _accountExists(int? id) {
    if (id == null) return false;

    return widget.wallets.any(
      (wallet) => wallet['id'] == id,
    );
  }

  List<Map<String, dynamic>> get _availableCategories {
    if (_isTransfer) return [];

    return widget.categories.where((category) {
      return category['type'].toString().toLowerCase() == _type;
    }).toList();
  }

  Future<void> _pickDate({required bool isEndDate}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isEndDate
          ? (_endDate ?? _startDate)
          : _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected == null) return;

    setState(() {
      if (isEndDate) {
        _endDate = selected;
      } else {
        _startDate = selected;

        if (_endDate != null && _endDate!.isBefore(_startDate)) {
          _endDate = null;
        }
      }
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Future<void> _stagePhotos({bool camera = false}) async {
    try {
      List<XFile> photos = [];
      if (camera) {
        final photo = await _attachmentPicker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (photo != null) photos = [photo];
      } else {
        photos = await _attachmentPicker.pickMultiImage(imageQuality: 85);
      }
      for (final photo in photos) {
        _pendingAttachments.add({'path': photo.path, 'name': photo.name});
      }
      if (mounted) setState(() {});
    } catch (e) {
      _message('Photo selection failed: $e');
    }
  }

  Future<void> _stagePdfs() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true,
      );
      if (result == null) return;
      for (final file in result.files) {
        if (file.path != null) _pendingAttachments.add({'path': file.path!, 'name': file.name});
      }
      if (mounted) setState(() {});
    } catch (e) {
      _message('PDF selection failed: $e');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_walletId == null) {
      _message('Please select an wallet.');
      return;
    }

    if (_isTransfer) {
      if (_toWalletId == null) {
        _message('Please select destination wallet.');
        return;
      }

      if (_toWalletId == _walletId) {
        _message('Source and destination wallets must be different.');
        return;
      }

      final source = widget.wallets.firstWhere(
        (a) => a['id'] == _walletId,
      );

      final destination = widget.wallets.firstWhere(
        (a) => a['id'] == _toWalletId,
      );

      if (source['currency'] != destination['currency']) {
        _message('Transfer wallets must have the same currency.');
        return;
      }
    }

    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      _message(appText(context, 'End date cannot be before start date.', 'اختتامی تاریخ، آغاز کی تاریخ سے پہلے نہیں ہو سکتی۔'));
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    final transferFee = _isTransfer && _transferFeeEnabled
        ? (double.tryParse(_transferFeeController.text.trim()) ?? double.nan)
        : 0.0;

    if (_isTransfer && _transferFeeEnabled &&
        (!transferFee.isFinite || transferFee < 0)) {
      _message('Please enter a valid transfer fee.');
      return;
    }

    if (amount == null || amount <= 0) {
      _message(appText(context, 'Please enter a valid amount.', 'براہ کرم درست رقم درج کریں۔'));
      return;
    }

    setState(() => _saving = true);

    try {
      final model = RecurringTransactionModel(
        id: widget.existing?.id,
        title: _titleController.text.trim(),
        type: _type,
        amount: amount,
        transferFee: transferFee,
        walletId: _walletId!,
        toWalletId: _isTransfer ? _toWalletId : null,
        category: _isTransfer ? null : _category,
        note: _noteController.text.trim(),
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
        nextRunDate: widget.existing?.nextRunDate != null && !widget.existing!.nextRunDate!.isBefore(_startDate)
            ? widget.existing!.nextRunDate
            : _startDate,
        isActive: widget.existing?.isActive ?? true,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      if (widget.existing == null) {
        final createdId = await RecurringTransactionService().addRecurringTransaction(model);
        await SoundSettingsService.instance.play('save');
        try {
          for (final attachment in _pendingAttachments) {
            await AttachmentService.addAttachment(ownerType: 'recurring', ownerId: createdId, sourcePath: attachment['path']!, originalFileName: attachment['name']);
          }
        } catch (attachmentError) {
          await AttachmentService.deleteOwnerAttachments(ownerType: 'recurring', ownerId: createdId);
          await RecurringTransactionService().rollbackNewRecurringTransaction(createdId);
          throw Exception('Attachment save failed. Schedule was rolled back. $attachmentError');
        }
      } else {
        await RecurringTransactionService().updateRecurringTransaction(
          model,
        );
        await SoundSettingsService.instance.play('update');
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      _message('Save failed: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _transferFeeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {IconData? icon}) {
    return InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)), contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13));
  }

  @override
  Widget build(BuildContext context) {
    final categories = _availableCategories;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 8), child: Row(children: [Expanded(child: Text(widget.existing == null ? 'Add Schedule' : 'Edit Schedule', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))), IconButton(onPressed: _saving ? null : () => Navigator.pop(context, false), icon: Icon(Icons.close))])),
        Container(width: 42, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(8))),
        Expanded(child: SingleChildScrollView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: const EdgeInsets.fromLTRB(18, 18, 18, 20), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(segments: [ButtonSegment(value: 'income', label: Text(appText(context, "Income", "Income"))), ButtonSegment(value: 'expense', label: Text(appText(context, "Expense", "Expense"))), ButtonSegment(value: 'transfer', label: Text(appText(context, "Transfer", "Transfer")))], selected: {_type}, onSelectionChanged: _saving ? null : (value) => setState(() { _type = value.first; _category = null; _toWalletId = null; })),
          SizedBox(height: 14),
          TextFormField(controller: _titleController, decoration: _decoration('Schedule Title', icon: Icons.title), validator: (value) => value == null || value.trim().isEmpty ? appText(context, 'Please enter a title.', 'براہ کرم عنوان درج کریں۔') : null),
          SizedBox(height: 12),
          if (_isTransfer) ...[
            Row(children: [
              Expanded(child: TextFormField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Amount', icon: Icons.payments_outlined), validator: (value) { final amount = double.tryParse(value ?? ''); return amount == null || amount <= 0 ? 'Enter a valid amount.' : null; })),
              SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<int>(value: _walletId, isExpanded: true, decoration: _decoration('From Wallet', icon: Icons.account_balance_wallet_outlined), items: widget.wallets.map((wallet) => DropdownMenuItem<int>(value: wallet['id'] as int, child: Text('${wallet['name']} (${wallet['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() { _walletId = value; if (_toWalletId == value) _toWalletId = null; }), validator: (value) => value == null ? 'Select wallet' : null)),
              SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<int>(value: _toWalletId, isExpanded: true, decoration: _decoration('To Wallet', icon: Icons.account_balance_outlined), items: widget.wallets.where((a) => a['id'] != _walletId).map((wallet) => DropdownMenuItem<int>(value: wallet['id'] as int, child: Text('${wallet['name']} (${wallet['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() => _toWalletId = value), validator: (value) => value == null ? 'Select wallet' : null)),
            ]),
            SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Transfer Fee', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text('Add an optional fee to this recurring transfer', style: TextStyle(fontSize: 11)),
                value: _transferFeeEnabled,
                onChanged: _saving ? null : (value) => setState(() {
                  _transferFeeEnabled = value;
                  if (!value) _transferFeeController.clear();
                }),
              ),
            ),
            if (_transferFeeEnabled) ...[
              SizedBox(height: 10),
              TextFormField(
                controller: _transferFeeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _decoration('Fee Amount (${widget.wallets.firstWhere((a) => a['id'] == _walletId, orElse: () => {'currency': ''})['currency'] ?? ''})', icon: Icons.payments_outlined),
                validator: (value) {
                  if (!_transferFeeEnabled) return null;
                  final fee = double.tryParse(value ?? '');
                  return fee == null || !fee.isFinite || fee < 0 ? 'Enter a valid fee amount.' : null;
                },
              ),
            ],
          ] else ...[
            Row(children: [
              Expanded(child: TextFormField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Amount', icon: Icons.payments_outlined), validator: (value) { final amount = double.tryParse(value ?? ''); return amount == null || amount <= 0 ? 'Enter a valid amount.' : null; })),
              SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<int>(value: _walletId, isExpanded: true, decoration: _decoration('Wallet', icon: Icons.account_balance_wallet_outlined), items: widget.wallets.map((wallet) => DropdownMenuItem<int>(value: wallet['id'] as int, child: Text('${wallet['name']} (${wallet['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() => _walletId = value), validator: (value) => value == null ? 'Select wallet' : null)),
            ]),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(value: categories.any((item) => item['name'] == _category) ? _category : null, isExpanded: true, decoration: _decoration('Category', icon: Icons.category_outlined), hint: Text(appText(context, 'Optional', 'اختیاری')), items: categories.map((item) => DropdownMenuItem<String>(value: item['name'].toString(), child: Text(item['name'].toString(), overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() => _category = value))),
              SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _noteController, decoration: _decoration('Notes (Optional)', icon: Icons.notes_rounded))),
            ]),
          ],
          if (_isTransfer) ...[SizedBox(height: 12), TextFormField(controller: _noteController, maxLines: 2, decoration: _decoration('Notes (Optional)', icon: Icons.notes_rounded))],
          SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _frequency, isExpanded: true, decoration: _decoration('Repeat Schedule', icon: Icons.repeat_rounded), items: [DropdownMenuItem(value: 'daily', child: Text(appText(context, 'Daily', 'روزانہ'))), DropdownMenuItem(value: 'weekly', child: Text(appText(context, 'Weekly', 'ہفتہ وار'))), DropdownMenuItem(value: 'monthly', child: Text(appText(context, 'Monthly', 'ماہانہ'))), DropdownMenuItem(value: 'yearly', child: Text(appText(context, 'Yearly', 'سالانہ')))], onChanged: (value) { if (value != null) setState(() => _frequency = value); }),
          SizedBox(height: 12),
          Row(children: [
            Expanded(child: InkWell(onTap: () => _pickDate(isEndDate: false), borderRadius: BorderRadius.circular(12), child: InputDecorator(decoration: _decoration('Start Date', icon: Icons.calendar_month_outlined), child: Text(_formatDate(_startDate))))),
            SizedBox(width: 10),
            Expanded(child: InkWell(onTap: () => _pickDate(isEndDate: true), borderRadius: BorderRadius.circular(12), child: InputDecorator(decoration: _decoration('End Date (Optional)', icon: Icons.event_outlined).copyWith(suffixIcon: _endDate == null ? null : IconButton(onPressed: () => setState(() => _endDate = null), icon: Icon(Icons.close))), child: Text(_endDate == null ? 'No end date' : _formatDate(_endDate!))))),
          ]),
          if (widget.existing?.id != null) ...[
            SizedBox(height: 14),
            AttachmentSection(ownerType: 'recurring', ownerId: widget.existing!.id!, compact: false),
          ] else ...[
            SizedBox(height: 14),
            Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.attach_file), SizedBox(width: 8), Expanded(child: Text('Attachments', style: TextStyle(fontWeight: FontWeight.bold))), Text('${_pendingAttachments.length}')]),
              SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (Platform.isAndroid || Platform.isIOS) OutlinedButton.icon(onPressed: _saving ? null : () => _stagePhotos(camera: true), icon: Icon(Icons.camera_alt), label: Text('Camera')),
                OutlinedButton.icon(onPressed: _saving ? null : () => _stagePhotos(), icon: Icon(Icons.photo_library), label: Text('Gallery')),
                OutlinedButton.icon(onPressed: _saving ? null : _stagePdfs, icon: Icon(Icons.picture_as_pdf), label: Text('Add PDFs')),
              ]),
              if (_pendingAttachments.isNotEmpty) ...[
                SizedBox(height: 8),
                ..._pendingAttachments.asMap().entries.map((entry) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(entry.value['name']!.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image_outlined), title: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(onPressed: _saving ? null : () => setState(() => _pendingAttachments.removeAt(entry.key)), icon: Icon(Icons.close))))
              ]
            ]))),
          ],
        ])))),
        Padding(padding: EdgeInsets.fromLTRB(18, 10, 18, 14 + MediaQuery.of(context).padding.bottom), child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: Text(appText(context, 'Cancel', 'منسوخ کریں')))),
          SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: _saving ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: _saving ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.existing == null ? 'Save Schedule' : 'Update Schedule'))),
        ])),
      ]),
    );
  }}
