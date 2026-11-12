import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/models/attachment_model.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/finance/services/finance_transaction_operations.dart';

class TransactionEntryForm extends StatefulWidget {
  final String transactionType;

  const TransactionEntryForm({
    super.key,
    required this.transactionType,
  });

  @override
  State<TransactionEntryForm> createState() =>
      _TransactionEntryFormState();
}

class _TransactionEntryFormState extends State<TransactionEntryForm> {
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

  bool saving = false;
  bool loading = true;
  bool transferFeeEnabled = false;

  String selectedCategory = '';
  String _dateFormat = 'dd/MM/yyyy';
  String _weekStart = 'Monday';

  bool get isTransfer => widget.transactionType == 'Transfer';

  @override
  void initState() {
    super.initState();
    loadWallets();
  }

  @override
  void dispose() {
    amountController.dispose();
    destinationAmountController.dispose();
    transferFeeController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> loadWallets() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberWallet = await GeneralPreferences.instance.rememberWallet;
    final defaultDate = await GeneralPreferences.instance.defaultDate;
    final weekStart = await GeneralPreferences.instance.weekStart;
    final savedDate = prefs.getString('general_last_transaction_date');
    final result = await FinanceDB.instance.getWallets();
    final categories = isTransfer
        ? <Map<String, dynamic>>[]
        : await FinanceDB.instance.getCategories(widget.transactionType);

    if (!mounted) return;

    setState(() {
      wallets = result;
      transactionCategories = categories;
      loading = false;

      _dateFormat = prefs.getString('general_date_format') ?? 'dd/MM/yyyy';
      _weekStart = weekStart;
      if (defaultDate == 'Last Selected Date' && savedDate != null) {
        selectedDate = DateTime.tryParse(savedDate) ?? DateTime.now();
      }
      if (wallets.isNotEmpty) {
        final savedWalletId = rememberWallet ? prefs.getInt('general_last_wallet_id') : null;
        selectedWalletId = wallets.any((w) => w['id'] == savedWalletId)
            ? savedWalletId : wallets.first['id'] as int;
        if (isTransfer && wallets.length > 1) {
          selectedDestinationWalletId = wallets[1]['id'] as int;
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
                  color: AppColors.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 15),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recurring',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              ...options.map(
                (option) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option),
                  trailing: selectedRecurring == option
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : const Icon(Icons.circle_outlined, color: AppColors.muted),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Date', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 15),
                        const SizedBox(width: 5),
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
          Container(width: 1, height: 34, color: Theme.of(context).dividerColor),
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('Time', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.access_time_rounded, size: 15),
                        const SizedBox(width: 5),
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
          Container(width: 1, height: 34, color: Theme.of(context).dividerColor),
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _showRecurringOptions,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Recurring', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(Icons.repeat_rounded, size: 15),
                        const SizedBox(width: 4),
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
        if (amount == null || amount <= 0) {
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

  Widget _categoryField() {
    return DropdownButtonFormField<String>(
      value: transactionCategories.any(
        (category) => category['name'] == selectedCategory,
      ) ? selectedCategory : null,
      isExpanded: true,
      decoration: decoration('Category', icon: Icons.category_outlined),
      hint: const Text('Select Category'),
      items: transactionCategories.map((category) {
        final iconCode = category['icon'] as int;
        return DropdownMenuItem<String>(
          value: category['name'] as String,
          child: Row(
            children: [
              Icon(
                IconData(iconCode, fontFamily: 'MaterialIcons'),
                size: 19,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
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
        suffixIcon: IconButton(
          tooltip: selectedNoteImage == null ? 'Attach image' : 'Change image',
          icon: Icon(
            selectedNoteImage == null
                ? Icons.add_photo_alternate_outlined
                : Icons.image_rounded,
            color: AppColors.primary,
          ),
          onPressed: _pickNoteImage,
        ),
      ),
    );
  }

  Future<void> _pickNoteImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
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

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) return;

    if (selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallet select karein.')),
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
            const SnackBar(content: Text('Valid transfer fee enter karein.')),
          );
          return;
        }
      }
      if (selectedDestinationWalletId == null ||
          selectedDestinationWalletId == selectedWalletId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Different destination wallet select karein.')),
        );
        return;
      }

      final sourceCurrency = selectedWallet?['currency'];
      final destinationCurrency = selectedDestinationWallet?['currency'];

      if (sourceCurrency != destinationCurrency) {
        destinationAmount = double.tryParse(destinationAmountController.text.trim());
        if (destinationAmount == null || destinationAmount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Destination amount enter karein.')),
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
      final transactionId = await FinanceDB.instance.addTransaction(
        type: widget.transactionType,
        amount: amount,
        walletId: selectedWalletId!,
        toWalletId: isTransfer ? selectedDestinationWalletId : null,
        toAmount: destinationAmount,
        transferFee: transferFee,
        category: isTransfer ? '' : selectedCategory,
        note: noteController.text.trim(),
        date: selectedDate,
      );

      await FinanceDB.instance.db.insert(
        'app_settings',
        {
          'setting_key': 'transaction_recurrence_$transactionId',
          'setting_value': selectedRecurring,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      String? attachmentWarning;
      if (selectedNoteImage != null) {
        try {
          await AttachmentService.addAttachment(
            ownerType: AttachmentOwnerTypes.transaction,
            ownerId: transactionId,
            sourcePath: selectedNoteImage!.path,
            originalFileName: selectedNoteImage!.name,
          );
        } catch (e) {
          attachmentWarning = e.toString().replaceFirst('Exception: ', '');
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            attachmentWarning == null
                ? 'Transaction successfully saved.'
                : 'Transaction saved, but image could not be attached: $attachmentWarning',
          ),
        ),
      );

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
    final isIncome = widget.transactionType == 'Income';
    final accentColor = isIncome
        ? AppColors.income
        : isTransfer
            ? AppColors.primary
            : AppColors.expense;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (wallets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Pehle ek wallet add karein.'),
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
            const SizedBox(height: 14),
            if (isTransfer) ...[
              Row(
                children: [
                  Expanded(child: _walletField()),
                  const SizedBox(width: 10),
                  Expanded(child: _destinationWalletField()),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _amountField()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _notesField(),
                  ),
                ],
              ),
              
              if (selectedWallet != null &&
                  selectedDestinationWallet != null &&
                  selectedWallet!['currency'] != selectedDestinationWallet!['currency']) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: destinationAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: decoration(
                    'Destination Amount (${selectedDestinationWallet!['currency']})',
                    icon: Icons.currency_exchange_rounded,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (isTransfer) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFE2E9E5)),
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Transfer Fee',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Add an optional fee to this transfer',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: transferFeeEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (value) => setState(() {
                      transferFeeEnabled = value;
                      if (!value) transferFeeController.clear();
                    }),
                  ),
                ),
                if (transferFeeEnabled) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: transferFeeController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: decoration(
                      'Fee Amount (${selectedWallet?['currency'] ?? ''})',
                      icon: Icons.payments_outlined,
                    ),
                  ),
                ],
              ],
            ] else ...[
              Row(
                children: [
                  Expanded(child: _amountField()),
                  const SizedBox(width: 10),
                  Expanded(child: _walletField()),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _categoryField()),
                  const SizedBox(width: 10),
                  Expanded(child: _notesField()),
                ],
              ),
            ],
            const SizedBox(height: 20),
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
                  ? const SizedBox(
                      height: 21,
                      width: 21,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save Transaction',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
