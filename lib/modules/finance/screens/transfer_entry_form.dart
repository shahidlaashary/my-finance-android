import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/modules/finance/services/category_service.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';
import 'package:my_finance/core/files/attachment_service.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
import 'package:my_finance/modules/finance/screens/categories_management_screen.dart' show CategoriesPage;
import 'package:my_finance/modules/finance/models/recurring_transaction_model.dart';
import 'package:my_finance/modules/finance/services/recurring_transaction_service.dart';

class TransferEntryForm extends StatefulWidget {
  const TransferEntryForm({super.key});

  @override
  State<TransferEntryForm> createState() => _TransferEntryFormState();
}

class _TransferEntryFormState extends State<TransferEntryForm> {
  final formKey = GlobalKey<FormState>();

  final amountController = TextEditingController();
  final destinationAmountController = TextEditingController();
  final transferFeeController = TextEditingController();
  final noteController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  List<Map<String, dynamic>> wallets = [];
  List<Map<String, dynamic>> transactionCategories = [];

  int? selectedWalletId;
  int? selectedDestinationWalletId;

  DateTime selectedDate = DateTime.now();
  String selectedRecurring = 'None';
  XFile? selectedNoteImage;
  final List<PlatformFile> selectedNotePdfs = [];

  bool saving = false;
  bool loading = true;
  bool transferFeeEnabled = false;

  String selectedCategory = '';
  String _dateFormat = 'dd/MM/yyyy';
  String _weekStart = 'Monday';

  bool get isTransfer => 'Transfer' == 'Transfer';

  @override
  void initState() {
    super.initState();
    AppRefreshController.revision.addListener(_onAppDataChanged);
    loadWallets();
  }

  void _onAppDataChanged() {
    if (mounted) loadWallets(preserveSelections: true);
  }

  @override
  void dispose() {
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    amountController.dispose();
    destinationAmountController.dispose();
    transferFeeController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> loadWallets({bool preserveSelections = false}) async {
    final previousWalletId = selectedWalletId;
    final previousDestinationWalletId = selectedDestinationWalletId;
    final previousDate = selectedDate;
    final prefs = await SharedPreferences.getInstance();
    final rememberWallet = await GeneralPreferences.instance.rememberWallet;
    final defaultDate = await GeneralPreferences.instance.defaultDate;
    final weekStart = await GeneralPreferences.instance.weekStart;
    final savedDate = prefs.getString('general_last_transaction_date');
    final result = await WalletService.getWallets();
    final categories = isTransfer
        ? <Map<String, dynamic>>[]
        : await CategoryService.getCategoryMaps('Expense');

    if (!mounted) return;

    setState(() {
      wallets = result;
      transactionCategories = categories;
      loading = false;

      _dateFormat = prefs.getString('general_date_format') ?? 'dd/MM/yyyy';
      _weekStart = weekStart;
      if (preserveSelections) {
        selectedDate = previousDate;
      } else if (defaultDate == 'Last Selected Date' && savedDate != null) {
        selectedDate = DateTime.tryParse(savedDate) ?? DateTime.now();
      }
      if (wallets.isNotEmpty) {
        final savedWalletId = rememberWallet ? prefs.getInt('general_last_wallet_id') : null;
        final preferredWalletId = preserveSelections ? previousWalletId : savedWalletId;
        selectedWalletId = wallets.any((w) => w['id'] == preferredWalletId)
            ? preferredWalletId : wallets.first['id'] as int;
        if (isTransfer && wallets.length > 1) {
          final preferredDestinationId = preserveSelections
              ? previousDestinationWalletId : wallets[1]['id'] as int;
          selectedDestinationWalletId = wallets.any((w) => w['id'] == preferredDestinationId)
              ? preferredDestinationId : wallets.firstWhere((w) => w['id'] != selectedWalletId)['id'] as int;
        }
      }

      if (transactionCategories.isNotEmpty &&
          !transactionCategories.any(
            (category) => category['name'] == selectedCategory,
          )) {
        selectedCategory = transactionCategories.first['name'] as String;
      }
    });
  }

  Map<String, dynamic>? get selectedWallet {
    for (final wallet in wallets) {
      if (wallet['id'] == selectedWalletId) return wallet;
    }
    return null;
  }

  Map<String, dynamic>? get selectedDestinationWallet {
    for (final wallet in wallets) {
      if (wallet['id'] == selectedDestinationWalletId) return wallet;
    }
    return null;
  }

  InputDecoration decoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      locale: _weekStart == 'Sunday' ? const Locale('en', 'US') : const Locale('en', 'GB'),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null || !mounted) return;

    setState(() {
      selectedDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        selectedDate.hour,
        selectedDate.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDate),
    );

    if (picked == null || !mounted) return;

    setState(() {
      selectedDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _showRecurringOptions() async {
    const options = ['None', 'Daily', 'Weekly', 'Monthly', 'Yearly'];

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).hintColor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              SizedBox(height: 15),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(appText(context, "Recurring", "Recurring"),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              SizedBox(height: 8),
              ...options.map(
                (option) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option),
                  trailing: selectedRecurring == option
                      ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                      : Icon(Icons.circle_outlined, color: Theme.of(context).hintColor),
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => selectedRecurring = selected);
    }
  }

  Widget _buildDateTimeRecurringBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appText(context, "Date", "Date"), style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
                    SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 15),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            DateFormat(_dateFormat).format(selectedDate),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 30, color: Theme.of(context).dividerColor),
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(appText(context, "Time", "Time"), style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
                    SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.access_time_rounded, size: 15),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            DateFormat('h:mm a').format(selectedDate),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 30, color: Theme.of(context).dividerColor),
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _showRecurringOptions,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(appText(context, "Recurring", "Recurring"), style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
                    SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(Icons.repeat_rounded, size: 15),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            selectedRecurring,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountField() {
    return TextFormField(
      controller: amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: decoration('Amount', icon: Icons.payments_outlined),
      validator: (value) {
        final amount = double.tryParse(value?.trim() ?? '');
        if (amount == null || !amount.isFinite || amount <= 0) {
          return 'Valid amount enter karein.';
        }
        return null;
      },
    );
  }

  Widget _walletField() {
    return DropdownButtonFormField<int>(
      value: selectedWalletId,
      isExpanded: true,
      decoration: decoration(
        isTransfer ? 'From Wallet' : 'Wallet',
        icon: Icons.account_balance_wallet_outlined,
      ),
      items: wallets.map((wallet) => DropdownMenuItem<int>(
        value: wallet['id'] as int,
        child: Text(
          '${wallet['name']} (${wallet['currency']})',
          overflow: TextOverflow.ellipsis,
        ),
      )).toList(),
      onChanged: (value) => setState(() => selectedWalletId = value),
    );
  }

  Widget _destinationWalletField() {
    return DropdownButtonFormField<int>(
      value: selectedDestinationWalletId,
      isExpanded: true,
      decoration: decoration(
        'To Wallet',
        icon: Icons.account_balance_outlined,
      ),
      items: wallets.where((wallet) => wallet['id'] != selectedWalletId)
          .map((wallet) => DropdownMenuItem<int>(
            value: wallet['id'] as int,
            child: Text(
              '${wallet['name']} (${wallet['currency']})',
              overflow: TextOverflow.ellipsis,
            ),
          )).toList(),
      onChanged: (value) => setState(() => selectedDestinationWalletId = value),
    );
  }

  Future<void> _manageCategories() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CategoriesPage(initialType: 'Transfer'),
      ),
    );

    if (!mounted) return;
    final categories = await CategoryService.getCategoryMaps(
      'Expense',
    );
    if (!mounted) return;

    setState(() {
      transactionCategories = categories;
      if (!categories.any(
        (category) => category['name'] == selectedCategory,
      )) {
        selectedCategory = categories.isEmpty
            ? ''
            : categories.first['name'] as String;
      }
    });
  }

  Widget _categoryField() {
    return DropdownButtonFormField<String>(
      value: transactionCategories.any(
        (category) => category['name'] == selectedCategory,
      ) ? selectedCategory : null,
      isExpanded: true,
      decoration: decoration('Category', icon: Icons.category_outlined).copyWith(
        suffixIcon: IconButton(
          tooltip: appText(context, 'Manage Categories', 'زمرے منظم کریں'),
          icon: const Icon(Icons.tune_rounded),
          onPressed: _manageCategories,
        ),
      ),
      hint: Text(appText(context, 'Select Category', 'زمرہ منتخب کریں')),
      items: transactionCategories.map((category) {
        final iconCode = category['icon'] as int;
        return DropdownMenuItem<String>(
          value: category['name'] as String,
          child: Row(
            children: [
              Icon(
                IconData(iconCode, fontFamily: 'MaterialIcons'),
                size: 19,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  category['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) setState(() => selectedCategory = value);
      },
    );
  }

  Widget _notesField() {
    return TextFormField(
      controller: noteController,
      maxLines: 2,
      decoration: decoration('Notes (Optional)', icon: Icons.notes_rounded).copyWith(
        suffixIcon: PopupMenuButton<String>(
          tooltip: 'Add attachment',
          icon: Icon(Icons.attach_file_rounded, color: Theme.of(context).colorScheme.primary),
          onSelected: (value) {
            if (value == 'camera') {
              _pickNoteImage(ImageSource.camera);
            } else if (value == 'gallery') {
              _pickNoteImage(ImageSource.gallery);
            } else if (value == 'pdf') {
              _pickNotePdfs();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'camera', child: Text('Camera')),
            PopupMenuItem(value: 'gallery', child: Text('Gallery')),
            PopupMenuItem(value: 'pdf', child: Text('Add PDFs')),
          ],
        ),
      ),
    );
  }

  Future<void> _pickNoteImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => selectedNoteImage = picked);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image select nahi ho saki: $e')),
      );
    }
  }

  Future<void> _pickNotePdfs() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      if (result != null && mounted) {
        setState(() => selectedNotePdfs.addAll(result.files.where((file) => file.path != null)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF select nahi ho saki: $e')),
      );
    }
  }



  DateTime _nextRecurringDate(DateTime date, String frequency) {
    final current = DateTime(date.year, date.month, date.day);
    switch (frequency.toLowerCase()) {
      case 'daily': return current.add(const Duration(days: 1));
      case 'weekly': return current.add(const Duration(days: 7));
      case 'monthly':
        final next = DateTime(current.year, current.month + 1, 1);
        final last = DateTime(next.year, next.month + 1, 0).day;
        return DateTime(next.year, next.month, current.day > last ? last : current.day);
      case 'yearly':
        final year = current.year + 1;
        final last = DateTime(year, current.month + 1, 0).day;
        return DateTime(year, current.month, current.day > last ? last : current.day);
      default: return current;
    }
  }

  Future<void> _createRecurringSchedule({
    required double amount,
    required double transferFee,
  }) async {
    if (selectedRecurring == 'None') return;
    final type = 'transfer';
    final frequency = selectedRecurring.toLowerCase();
    final title = selectedCategory.trim().isNotEmpty
        ? selectedCategory.trim()
        : noteController.text.trim().isNotEmpty
            ? noteController.text.trim()
            : 'Recurring Transfer';
    final schedule = RecurringTransactionModel(
      title: title,
      type: type,
      amount: amount,
      transferFee: type == 'transfer' ? transferFee : 0,
      walletId: selectedWalletId!,
      toWalletId: type == 'transfer' ? selectedDestinationWalletId : null,
      category: type == 'transfer' ? null : selectedCategory,
      note: noteController.text.trim(),
      frequency: frequency,
      startDate: selectedDate,
      nextRunDate: _nextRecurringDate(selectedDate, frequency),
      isActive: true,
      createdAt: DateTime.now(),
    );
    await RecurringTransactionService().addRecurringTransaction(schedule);
  }

  Future<void> save() => _saveTransaction();

  Future<void> _saveTransaction() async {
    if (!formKey.currentState!.validate()) return;

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || !amount.isFinite || amount <= 0) return;

    if (selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText(context, "Select a wallet.", "والٹ منتخب کریں۔"))),
      );
      return;
    }

    double? destinationAmount;
    double transferFee = 0;

    if (isTransfer) {
      if (transferFeeEnabled) {
        transferFee = double.tryParse(transferFeeController.text.trim()) ?? 0;
        if (!transferFee.isFinite || transferFee <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appText(context, "Enter a valid transfer fee.", "منتقلی کی درست فیس درج کریں۔"))),
          );
          return;
        }
      }
      if (selectedDestinationWalletId == null ||
          selectedDestinationWalletId == selectedWalletId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appText(context, "Select a different destination wallet.", "منزل کے لیے دوسرا والٹ منتخب کریں۔"))),
        );
        return;
      }

      final sourceCurrency = selectedWallet?['currency'];
      final destinationCurrency = selectedDestinationWallet?['currency'];

      if (sourceCurrency != destinationCurrency) {
        destinationAmount = double.tryParse(destinationAmountController.text.trim());
        if (destinationAmount == null || destinationAmount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appText(context, "Enter a destination amount.", "منزل کی رقم درج کریں۔"))),
          );
          return;
        }
      }
    }

    setState(() => saving = true);

    try {
      final preferences = await SharedPreferences.getInstance();
      if (await GeneralPreferences.instance.rememberWallet) {
        await preferences.setInt('general_last_wallet_id', selectedWalletId!);
      }
      await preferences.setString('general_last_transaction_date', selectedDate.toIso8601String());
      if (await GeneralPreferences.instance.hapticFeedback) {
        await HapticFeedback.selectionClick();
      }
      final transactionId = await TransactionsService.addTransaction(
        type: 'Transfer',
        amount: amount,
        walletId: selectedWalletId!,
        toWalletId: isTransfer ? selectedDestinationWalletId : null,
        toAmount: destinationAmount,
        transferFee: transferFee,
        category: isTransfer ? '' : selectedCategory,
        note: noteController.text.trim(),
        date: selectedDate.toIso8601String(),
      );

      String? scheduleWarning;
      if (selectedRecurring != 'None') {
        try {
          await _createRecurringSchedule(
            amount: amount,
            transferFee: transferFee,
          );
        } catch (e) {
          scheduleWarning = e.toString().replaceFirst('Exception: ', '');
        }
      }

      String? attachmentWarning;
      final selectedAttachments = <({String path, String name})>[];
      if (selectedNoteImage != null) {
        selectedAttachments.add((path: selectedNoteImage!.path, name: selectedNoteImage!.name));
      }
      for (final pdf in selectedNotePdfs) {
        if (pdf.path != null) selectedAttachments.add((path: pdf.path!, name: pdf.name));
      }
      for (final attachment in selectedAttachments) {
        try {
          await AttachmentService.addAttachment(
            ownerType: AttachmentOwnerTypes.transaction,
            ownerId: transactionId,
            sourcePath: attachment.path,
            originalFileName: attachment.name,
          );
        } catch (e) {
          attachmentWarning ??= e.toString().replaceFirst('Exception: ', '');
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scheduleWarning == null
                ? (attachmentWarning == null
                    ? 'Transaction successfully saved.'
                    : 'Transaction saved, but an attachment could not be added: $attachmentWarning')
                : (attachmentWarning == null
                    ? 'Transaction saved, but recurring schedule could not be created: $scheduleWarning'
                    : 'Transaction saved. Attachment and recurring schedule warnings: $attachmentWarning; $scheduleWarning'),
          ),
        ),
      );

      await SoundSettingsService.instance.play('transfer');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );

      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = 'Transfer' == 'Income';
    final accentColor = isIncome
        ? Theme.of(context).colorScheme.secondary
        : isTransfer
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error;

    if (loading) {
      return Center(child: CircularProgressIndicator());
    }
    if (wallets.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(appText(context, "Add a wallet first.", "پہلے ایک والٹ شامل کریں۔")),
        ),
      );
    }

    return Form(
      key: formKey,
      child: SingleChildScrollView(
        primary: false,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDateTimeRecurringBox(),
            SizedBox(height: 14),
            if (isTransfer) ...[
              Row(
                children: [
                  Expanded(child: _walletField()),
                  SizedBox(width: 10),
                  Expanded(child: _destinationWalletField()),
                ],
              ),
              SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: _amountField(),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAF9),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    appText(context, "Transfer Fee", "Transfer Fee"),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    appText(context, "Add fee (Optional)", "Add fee (Optional)"),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).hintColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch.adaptive(
                                value: transferFeeEnabled,
                                activeColor: Theme.of(context).colorScheme.primary,
                                onChanged: (value) => setState(() {
                                  transferFeeEnabled = value;
                                  if (!value) transferFeeController.clear();
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (transferFeeEnabled) ...[
                SizedBox(height: 10),
                TextFormField(
                  controller: transferFeeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: decoration(
                    'Fee Amount (${selectedWallet?['currency'] ?? ''})',
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
              if (selectedWallet != null &&
                  selectedDestinationWallet != null &&
                  selectedWallet!['currency'] != selectedDestinationWallet!['currency']) ...[
                SizedBox(height: 12),
                TextFormField(
                  controller: destinationAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: decoration(
                    'Destination Amount (${selectedDestinationWallet!['currency']})',
                    icon: Icons.currency_exchange_rounded,
                  ),
                ),
              ],
              SizedBox(height: 12),
              _notesField(),
            ] else ...[
              Row(
                children: [
                  Expanded(child: _amountField()),
                  SizedBox(width: 10),
                  Expanded(child: _walletField()),
                ],
              ),
              SizedBox(height: 12),
              _categoryField(),
              SizedBox(height: 12),
              _notesField(),
            ],
            SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : save,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: saving
                  ? SizedBox(
                      height: 21,
                      width: 21,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(appText(context, "Save Transaction", "Save Transaction"),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
