
import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:my_finance/core/services/attachment_service.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/models/repayment_model.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/features/finance/screens/loans_screen.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final AssetsService _service = AssetsService();

  List<AssetsModel> _assets = [];
  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _parties = [];
  Map<int, LoansModel> _linkedLoans = {};

  Map<String, double> _currentValues = {};
  Map<String, double> _purchaseValues = {};
  Map<String, double> _realizedProfitLoss = {};

  bool _loading = true;
  bool _hideBalances = false;
  bool _showSold = false;
  String? _selectedCategory;

  final NumberFormat _numberFormat =
      NumberFormat('#,##0.00');

  String _money(double value) {
    return _hideBalances ? '••••••' : _numberFormat.format(value);
  }

  Future<void> _showParties() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyManagementPage(
          hideBalances: _hideBalances,
          onLoanTap: (_) {
            _message('Open loan details from the Loans section.');
          },
        ),
      ),
    );
    await _loadData();
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _onPreferencesChanged() async {
    final hidden = await GeneralPreferences.instance.hideBalances;
    if (mounted && hidden != _hideBalances) {
      setState(() => _hideBalances = hidden);
    }
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final hideBalances = await GeneralPreferences.instance.hideBalances;
      final assets = await _service.getAssets(
        includeSold: _showSold,
      );

      final current =
          await _service.getTotalCurrentValueByCurrency();

      final purchase =
          await _service.getTotalPurchaseValueByCurrency();

      final realized =
          await _service.getTotalRealizedProfitLossByCurrency();

      final Database db = await TransactionsService.database;

      final wallets = await db.query(
        'wallets',
        orderBy: 'name ASC',
      );
      final parties = await LoansService.getParties();
      final linkedLoanIds = <int>{
        for (final asset in assets)
          if (asset.linkedLoanId != null) asset.linkedLoanId!,
        for (final asset in assets)
          if (asset.saleLinkedLoanId != null) asset.saleLinkedLoanId!,
      };
      final linkedLoans = <int, LoansModel>{};
      for (final loanId in linkedLoanIds) {
        final loan = await LoansService.getLoanById(loanId);
        if (loan != null) linkedLoans[loanId] = loan;
      }

      if (!mounted) return;

      setState(() {
        _hideBalances = hideBalances;
        _assets = assets;
        _wallets = wallets;
        _parties = parties;
        _linkedLoans = linkedLoans;
        _currentValues = current;
        _purchaseValues = purchase;
        _realizedProfitLoss = realized;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _message('Error loading assets: $e');
    }
  }

  String _walletName(int walletId) {
    final matches = _wallets.where(
      (wallet) =>
          (wallet['id'] as num).toInt() == walletId,
    );

    if (matches.isEmpty) return 'Unknown wallet';

    return matches.first['name'].toString();
  }

  String _partyName(int? partyId) {
    if (partyId == null) return '-';
    final matches = _parties.where((party) => (party['id'] as num).toInt() == partyId);
    return matches.isEmpty ? 'Unknown Party' : matches.first['name'].toString();
  }

  Future<Map<String, dynamic>?> _createParty({
    required String initialCurrency,
    bool lockCurrency = false,
  }) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final currencies = CurrencyCatalog.supported;
    String selectedCurrency = currencies.contains(initialCurrency.toUpperCase())
        ? initialCurrency.toUpperCase()
        : 'PKR';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Party'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  DropdownButtonFormField<String>(
                    value: selectedCurrency,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Party Currency *'),
                    items: currencies.map((currency) => DropdownMenuItem(
                      value: currency,
                      child: Text(currency),
                    )).toList(),
                    onChanged: lockCurrency ? null : (value) {
                      if (value != null) {
                        setDialogState(() => selectedCurrency = value);
                      }
                    },
                  ),
                ],
              ),
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
      ),
    );

    Map<String, dynamic>? createdParty;
    if (saved == true) {
      try {
        final id = await LoansService.addParty(
          name: name.text.trim(),
          phone: phone.text.trim(),
          address: address.text.trim(),
          currency: selectedCurrency,
        );
        final refreshed = await LoansService.getParties();
        if (!mounted) return null;
        setState(() => _parties = refreshed);
        createdParty = refreshed.firstWhere(
          (party) => (party['id'] as num).toInt() == id,
        );
      } catch (error) {
        _message('Could not create party: $error');
      }
    }
    name.dispose();
    phone.dispose();
    address.dispose();
    return createdParty;
  }

  List<AssetsModel> get _visibleAssets => _selectedCategory == null
      ? _assets
      : _assets.where((asset) => asset.category.trim().toLowerCase() == _selectedCategory!.toLowerCase()).toList();

  List<String> get _availableCurrencies {
    final currencies = <String>{
      ..._currentValues.keys,
      ..._purchaseValues.keys,
      ..._realizedProfitLoss.keys,
      ..._assets.map((asset) => asset.currency.toUpperCase()),
    };

    final result = currencies.toList()..sort();

    return result;
  }

  Future<void> _showAssetDialog({
    AssetsModel? asset,
    String? initialCategory,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: asset?.name ?? '');
    final purchaseController = TextEditingController(text: asset?.purchasePrice.toString() ?? '');
    final currentController = TextEditingController(text: asset?.currentValue.toString() ?? '');
    final notesController = TextEditingController(text: asset?.notes ?? '');
    int? selectedWallet = asset?.walletId;
    String selectedPaymentType = asset?.paymentType ?? 'Wallet';
    final defaultAssetCurrency = asset?.currency ?? await FinanceDB.instance.getBaseCurrency();
    String newPartyCurrency =
        CurrencyCatalog.supported.contains(defaultAssetCurrency.toUpperCase())
            ? defaultAssetCurrency.toUpperCase()
            : 'PKR';
    int? selectedPartyId = asset?.partyId;
    bool createNewParty = false;
    final newPartyNameController = TextEditingController();
    final newPartyPhoneController = TextEditingController();
    DateTime purchaseDate = asset?.purchaseDate ?? DateTime.now();
    bool includeInConsolidatedBalance = asset?.includeInConsolidatedBalance ?? false;
    String selectedCategory = asset?.category ?? initialCategory ?? 'Property';
    const categories = ['Property', 'Vehicles', 'Gold', 'Jewellery', 'Electronics', 'Investments', 'Livestock', 'Business'];
    final pendingFiles = <Map<String, String>>[];
    final imagePicker = ImagePicker();
    bool saving = false;

    InputDecoration fieldDecoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E9E5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF147D59), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      isDense: true,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickCamera() async {
            try {
              final photo = await imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
              if (photo != null) setSheetState(() => pendingFiles.add({'path': photo.path, 'name': photo.name}));
            } catch (e) { _message('Camera error: $e'); }
          }
          Future<void> pickGallery() async {
            try {
              final photos = await imagePicker.pickMultiImage(imageQuality: 85);
              for (final photo in photos) { setSheetState(() => pendingFiles.add({'path': photo.path, 'name': photo.name})); }
            } catch (e) { _message('Gallery error: $e'); }
          }
          Future<void> pickPdfs() async {
            try {
              final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
              if (result != null) for (final file in result.files) {
                if (file.path != null) setSheetState(() => pendingFiles.add({'path': file.path!, 'name': file.name}));
              }
            } catch (e) { _message('PDF select error: $e'); }
          }
          final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
          final screenHeight = MediaQuery.sizeOf(context).height;
          final keyboardOpen = keyboardHeight > 0;
          final maxHeight = keyboardOpen
              ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * .95
              : screenHeight * .72;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      primary: false,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD9E0DC), borderRadius: BorderRadius.circular(10)))),
                          SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: Text(asset == null ? 'Add Asset' : 'Edit Asset', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF202B25)))),
                            IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded), color: Colors.grey),
                          ]),
                          SizedBox(height: 10),
                          TextFormField(controller: nameController, decoration: fieldDecoration('Asset Name', Icons.inventory_2_outlined),
                            validator: (v) => v == null || v.trim().isEmpty ? appText(context, 'Enter asset name', 'اثاثے کا نام درج کریں') : null),
                          SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: DropdownButtonFormField<String>(
                              value: categories.contains(selectedCategory) ? selectedCategory : categories.first,
                              isExpanded: true,
                              decoration: fieldDecoration('Asset Property', Icons.category_outlined),
                              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) { if (v != null) setSheetState(() => selectedCategory = v); },
                            )),
                            SizedBox(width: 10),
                            Expanded(child: DropdownButtonFormField<String>(
                              value: selectedPaymentType,
                              isExpanded: true,
                              decoration: fieldDecoration('Payment Type', Icons.payments_outlined),
                              items: const ['Cash', 'Bank', 'Wallet', 'Loan'].map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                if (asset != null && ((v == 'Loan') != (asset.paymentType.toLowerCase() == 'loan'))) return;
                                setSheetState(() => selectedPaymentType = v);
                              },
                            )),
                          ]),
                          SizedBox(height: 10),
                          if (selectedPaymentType == 'Loan') ...[
                            DropdownButtonFormField<String>(
                              value: createNewParty
                                  ? '__new_party__'
                                  : selectedPartyId?.toString(),
                              isExpanded: true,
                              decoration: fieldDecoration('Select Party *', Icons.person_outline),
                              items: [
                                ..._parties.map((party) => DropdownMenuItem<String>(
                                  value: (party['id'] as num).toInt().toString(),
                                  child: Text('${party['name']} • ${(party['currency'] ?? 'PKR').toString().toUpperCase()}', overflow: TextOverflow.ellipsis),
                                )),
                                const DropdownMenuItem<String>(
                                  value: '__new_party__',
                                  child: Text('＋ Create Party'),
                                ),
                              ],
                              onChanged: (value) {
                                setSheetState(() {
                                  createNewParty = value == '__new_party__';
                                  if (createNewParty) {
                                    selectedPartyId = null;
                                    newPartyNameController.clear();
                                    newPartyPhoneController.clear();
                                    newPartyCurrency = CurrencyCatalog.supported.contains(defaultAssetCurrency.toUpperCase())
                                        ? defaultAssetCurrency.toUpperCase()
                                        : 'PKR';
                                  } else {
                                    selectedPartyId = int.tryParse(value ?? '');
                                  }
                                });
                              },
                              validator: (value) => value == null ? 'Select a party' : null,
                            ),
                            if (createNewParty) ...[
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: newPartyNameController,
                                      textCapitalization: TextCapitalization.words,
                                      decoration: fieldDecoration('Party Name *', Icons.person_outline),
                                      validator: (value) => createNewParty && (value == null || value.trim().isEmpty)
                                          ? 'Party name is required'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: newPartyPhoneController,
                                      keyboardType: TextInputType.phone,
                                      decoration: fieldDecoration('Phone Number', Icons.phone_outlined),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: newPartyCurrency,
                                isExpanded: true,
                                decoration: fieldDecoration('Party Currency *', Icons.currency_exchange),
                                items: CurrencyCatalog.supported.map((currency) => DropdownMenuItem(
                                  value: currency,
                                  child: Text(currency),
                                )).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setSheetState(() => newPartyCurrency = value);
                                  }
                                },
                              ),
                            ],
                            if (selectedPartyId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Loan currency: ${asset?.currency ?? _parties.firstWhere((p) => (p['id'] as num).toInt() == selectedPartyId)['currency'] ?? 'PKR'}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF147D59), fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                          ] else
                            DropdownButtonFormField<int>(
                              value: selectedWallet,
                              isExpanded: true,
                              decoration: fieldDecoration('Payment Wallet', Icons.account_balance_wallet_outlined),
                              items: _wallets.map((w) => DropdownMenuItem<int>(
                                value: (w['id'] as num).toInt(),
                                child: Text('${w['name']} (${w['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (v) => setSheetState(() => selectedWallet = v),
                              validator: (v) => v == null ? 'Select wallet' : null,
                            ),
                          SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: TextFormField(
                              controller: purchaseController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: fieldDecoration('Purchase Price', Icons.shopping_bag_outlined),
                              validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid purchase price' : null; },
                            )),
                            SizedBox(width: 10),
                            Expanded(child: TextFormField(
                              controller: currentController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: fieldDecoration('Current Value', Icons.trending_up_rounded),
                              validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 ? 'Enter a valid current value' : null; },
                            )),
                          ]),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    final picked = await showDatePicker(context: context, initialDate: purchaseDate, firstDate: DateTime(1950), lastDate: DateTime.now());
                                    if (picked != null) setSheetState(() => purchaseDate = picked);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(children: [
                                      const Icon(Icons.calendar_month, color: Color(0xFF147D59)),
                                      const SizedBox(width: 10),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(appText(context, 'Purchase Date', 'خریداری کی تاریخ'), style: const TextStyle(fontSize: 12, color: Color(0xFF66736C))),
                                        const SizedBox(height: 3),
                                        Text(DateFormat('dd MMM yyyy').format(purchaseDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      ])),
                                      const Icon(Icons.edit_calendar, size: 18, color: Color(0xFF147D59)),
                                    ]),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(children: [
                                  Expanded(child: Text('Include in Consolidated Balance', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), maxLines: 2)),
                                  Transform.scale(
                                    scale: 0.85,
                                    child: Switch(
                                      value: includeInConsolidatedBalance,
                                      activeColor: const Color(0xFF147D59),
                                      onChanged: (value) => setSheetState(() => includeInConsolidatedBalance = value),
                                    ),
                                  ),
                                ]),
                              ),
                            ],
                          ),
                          TextFormField(controller: notesController, maxLines: 2, decoration: fieldDecoration('Notes (optional)', Icons.notes_outlined)),
                          SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(color: const Color(0xFFF4FAF6), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFDCEBE2))),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                const Icon(Icons.attach_file_rounded, color: Color(0xFF147D59), size: 19),
                                const SizedBox(width: 7),
                                const Expanded(child: Text('Asset Attachments', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                                Text('${pendingFiles.length} selected', style: const TextStyle(color: Color(0xFF147D59), fontSize: 11, fontWeight: FontWeight.w700)),
                              ]),
                              const SizedBox(height: 4),
                              const Text('Add photos or PDF documents while entering this asset.', style: TextStyle(color: Colors.black54, fontSize: 11)),
                              const SizedBox(height: 10),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                _assetAttachmentButton(Icons.camera_alt_outlined, 'Camera', pickCamera, const Color(0xFF147D59)),
                                _assetAttachmentButton(Icons.photo_library_outlined, 'Gallery', pickGallery, const Color(0xFF3978C5)),
                                _assetAttachmentButton(Icons.picture_as_pdf_outlined, 'PDFs', pickPdfs, const Color(0xFFD34D4D)),
                              ]),
                              if (pendingFiles.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...pendingFiles.asMap().entries.map((entry) => Row(children: [
                                  Icon(entry.value['name']!.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image_outlined, size: 17, color: const Color(0xFF147D59)),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
                                  IconButton(visualDensity: VisualDensity.compact, onPressed: saving ? null : () => setSheetState(() => pendingFiles.removeAt(entry.key)), icon: const Icon(Icons.close, size: 17, color: Colors.redAccent)),
                                ])),
                              ],
                              if (asset?.id != null) ...[
                                const Divider(height: 18),
                                AttachmentSection(ownerType: 'asset', ownerId: asset!.id!),
                              ],
                            ]),
                          ),
                          SizedBox(height: 16),
                          Row(children: [
                            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext), child: Text(appText(context, 'Cancel', 'منسوخ کریں')))),
                            SizedBox(width: 10),
                            Expanded(child: ElevatedButton.icon(
                              icon: const Icon(Icons.check_rounded), label: Text(asset == null ? 'Save Asset' : 'Update Asset'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF147D59), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                try {
                                  if (createNewParty) {
                                    setSheetState(() => saving = true);
                                    final createdId = await LoansService.addParty(
                                      name: newPartyNameController.text.trim(),
                                      phone: newPartyPhoneController.text.trim(),
                                      currency: newPartyCurrency,
                                    );
                                    _parties = await LoansService.getParties();
                                    selectedPartyId = createdId;
                                  }
                                  final model = AssetsModel(id: asset?.id, name: nameController.text.trim(), category: selectedCategory,
                                    purchasePrice: double.parse(purchaseController.text), currentValue: double.parse(currentController.text),
                                    purchaseDate: purchaseDate, walletId: selectedWallet ?? 0, paymentType: selectedPaymentType, partyId: selectedPaymentType == 'Loan' ? selectedPartyId : null, currency: selectedPaymentType == 'Loan' && selectedPartyId != null
                                         ? (_parties.firstWhere((p) => (p['id'] as num).toInt() == selectedPartyId)['currency']?.toString() ?? defaultAssetCurrency).toUpperCase()
                                         : defaultAssetCurrency.toUpperCase(), linkedLoanId: asset?.linkedLoanId, notes: notesController.text.trim(),
                                    isSold: asset?.isSold ?? false, includeInConsolidatedBalance: includeInConsolidatedBalance, saleDate: asset?.saleDate, salePrice: asset?.salePrice,
                                    createdAt: asset?.createdAt ?? DateTime.now());
                                  setSheetState(() => saving = true);
                                  final int assetId;
                                  if (asset == null) {
                                    assetId = await _service.addAsset(model);
                                  } else {
                                    await _service.updateAsset(model);
                                    assetId = asset.id!;
                                  }
                                  for (final file in pendingFiles) {
                                    await AttachmentService.addAttachment(
                                      ownerType: 'asset',
                                      ownerId: assetId,
                                      sourcePath: file['path']!,
                                      originalFileName: file['name'],
                                    );
                                  }
                                  if (!sheetContext.mounted) return;
                                  Navigator.pop(sheetContext);
                                  await _loadData();
                                  _message(asset == null ? 'Asset added successfully.' : 'Asset updated successfully.');
                                } catch (e) { if (sheetContext.mounted) setSheetState(() => saving = false); _message('Error: $e'); }
                              },
                            )),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    nameController.dispose();
    purchaseController.dispose();
    currentController.dispose();
    notesController.dispose();
    newPartyNameController.dispose();
    newPartyPhoneController.dispose();
  }

  Future<void> _updateValuation(AssetsModel asset) async {
    final controller = TextEditingController(
      text: asset.currentValue.toString(),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText(context, 'Update Current Value', 'موجودہ قیمت اپ ڈیٹ کریں')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: appText(context, "New Current Value", "New Current Value"),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            ElevatedButton(
              onPressed: () {
                final value =
                    double.tryParse(controller.text);

                if (value == null ||
                    !value.isFinite ||
                    value < 0) {
                  return;
                }

                Navigator.pop(context, value);
              },
              child: Text(appText(context, 'Update', 'اپ ڈیٹ کریں')),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || asset.id == null) return;

    try {
      await _service.updateCurrentValue(asset.id!, result);
      await _loadData();
      _message('Asset valuation updated.');
    } catch (e) {
      _message('Error: $e');
    }
  }

  Future<void> _sellAsset(AssetsModel asset) async {
    final controller = TextEditingController(
      text: asset.currentValue.toString(),
    );

    DateTime saleDate = DateTime.now();
    int? selectedSaleWallet = asset.walletId;
    String selectedSalePaymentType = 'Wallet';
    int? selectedBuyerParty;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(appText(context, 'Sell Asset', 'اثاثہ فروخت کریں')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: appText(context, "Sale Price", "Sale Price"),
                    ),
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedSalePaymentType,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Payment Type'),
                    items: const ['Cash', 'Bank', 'Wallet', 'Loan'].map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                    onChanged: (value) => setDialogState(() => selectedSalePaymentType = value ?? 'Wallet'),
                  ),
                  const SizedBox(height: 8),
                  if (selectedSalePaymentType == 'Loan')
                    DropdownButtonFormField<int>(
                      value: selectedBuyerParty,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Buyer Party *'),
                      items: _parties.where((party) => (party['currency']?.toString() ?? 'PKR').toUpperCase() == asset.currency.toUpperCase()).map((party) => DropdownMenuItem<int>(
                        value: (party['id'] as num).toInt(),
                        child: Text('${party['name']} • ${party['currency'] ?? 'PKR'}', overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (value) => setDialogState(() => selectedBuyerParty = value),
                    ),
                  if (selectedSalePaymentType == 'Loan')
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          final created = await _createParty(
                            initialCurrency: asset.currency,
                            lockCurrency: true,
                          );
                          if (created != null &&
                              (created['currency']?.toString() ?? 'PKR').toUpperCase() == asset.currency.toUpperCase()) {
                            setDialogState(() {
                              selectedBuyerParty = (created['id'] as num).toInt();
                            });
                          } else if (created != null) {
                            _message('Buyer party currency must match ' + asset.currency + '.');
                          }
                        },
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Create Party'),
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: selectedSaleWallet,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sale Wallet'),
                      items: _wallets.where((wallet) => (wallet['currency']?.toString() ?? 'PKR').toUpperCase() == asset.currency.toUpperCase()).map((wallet) => DropdownMenuItem<int>(
                        value: (wallet['id'] as num).toInt(),
                        child: Text('${wallet['name']} (${wallet['currency'] ?? 'PKR'})'),
                      )).toList(),
                      onChanged: (value) => setDialogState(() => selectedSaleWallet = value),
                    ),
                  SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(appText(context, 'Sale Date', 'فروخت کی تاریخ')),
                    subtitle: Text(
                      DateFormat('dd MMM yyyy')
                          .format(saleDate),
                    ),
                    trailing:
                        const Icon(Icons.calendar_month),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: saleDate,
                        firstDate: asset.purchaseDate,
                        lastDate: DateTime.now(),
                      );

                      if (selected != null) {
                        setDialogState(() {
                          saleDate = selected;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final price =
                        double.tryParse(controller.text);

                    if (price == null ||
                        !price.isFinite ||
                        price < 0) {
                      return;
                    }

                    if (selectedSalePaymentType == 'Loan' && selectedBuyerParty == null) {
                      _message('Select a buyer party with ' + asset.currency + ' currency.');
                      return;
                    }
                    if (selectedSalePaymentType != 'Loan' && selectedSaleWallet == null) {
                      _message('Select a sale wallet in ' + asset.currency + '.');
                      return;
                    }
                    Navigator.pop(context, {
                      'price': price,
                      'date': saleDate,
                      'walletId': selectedSaleWallet ?? 0,
                      'paymentType': selectedSalePaymentType,
                      'partyId': selectedBuyerParty,
                    });
                  },
                  child: Text(appText(context, 'Confirm Sale', 'فروخت کی تصدیق کریں')),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (result == null || asset.id == null) return;

    try {
      await _service.sellAsset(
        assetId: asset.id!,
        salePrice: result['price'] as double,
        saleDate: result['date'] as DateTime,
        saleWalletId: result['walletId'] as int,
        paymentType: result['paymentType'] as String,
        partyId: result['partyId'] as int?,
      );

      await _loadData();
      _message('Asset sold successfully.');
    } catch (e) {
      _message('Error selling asset: $e');
    }
  }

  Future<void> _deleteAsset(AssetsModel asset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText(context, 'Delete Asset', 'اثاثہ حذف کریں')),
          content: Text(
            'Are you sure you want to delete "${asset.name}"? Any linked asset loan entries and repayments will also be removed and their wallet effects reversed.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: Text(appText(context, "Delete", "Delete")),
            ),
          ],
        );
      },
    );

    if (confirm != true || asset.id == null) return;

    try {
      await _service.deleteAsset(asset.id!);
      await _loadData();
      _message('Asset deleted successfully.');
    } catch (e) {
      _message('Error deleting asset: $e');
    }
  }

  Widget _heroMetric(String label, String value, {Color valueColor = Colors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFD6F5E7), fontSize: 10)),
        SizedBox(height: 5),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _summaryCard(
    String title,
    String currency,
    double amount,
    IconData icon, {
    Color color = const Color(0xFF147D59),
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 25),
            SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 5),
            Text(
              '$currency ${_money(amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _assetAttachmentButton(IconData icon, String label, VoidCallback onPressed, Color color) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: .35)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _openAssetDetails(AssetsModel asset) async {
    final purchaseLoan = asset.linkedLoanId == null
        ? null
        : _linkedLoans[asset.linkedLoanId!];
    final saleLoan = asset.saleLinkedLoanId == null
        ? null
        : _linkedLoans[asset.saleLinkedLoanId!];
    final purchaseRepayments = purchaseLoan?.id == null
        ? <RepaymentModel>[]
        : await LoansService.getRepayments(purchaseLoan!.id!);
    final saleRepayments = saleLoan?.id == null
        ? <RepaymentModel>[]
        : await LoansService.getRepayments(saleLoan!.id!);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssetDetailsScreen(
          asset: asset,
          purchaseLoan: purchaseLoan,
          saleLoan: saleLoan,
          purchaseRepayments: purchaseRepayments,
          saleRepayments: saleRepayments,
          wallets: _wallets,
          parties: _parties,
          hideBalances: _hideBalances,
        ),
      ),
    );
    if (mounted) await _loadData();
  }

  Future<void> _addAssetRepayment(LoansModel loan) async {
    if (loan.id == null || loan.remainingAmount <= 0) return;
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final matchingWallets = _wallets.where((wallet) =>
      (wallet['currency']?.toString() ?? 'PKR').toUpperCase() == loan.currency.toUpperCase()
    ).toList();
    if (matchingWallets.isEmpty) {
      _message('Create a ${loan.currency} wallet first.');
      return;
    }
    int selectedWalletId = (matchingWallets.first['id'] as num).toInt();
    DateTime paymentDate = DateTime.now();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loan.loanType == 'given' ? 'Receive Payment' : 'Pay Back',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Remaining: ${loan.currency} ${_money(loan.remainingAmount)}',
                  style: const TextStyle(color: Color(0xFF65736C), fontSize: 12)),
                const SizedBox(height: 14),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '${loan.currency} ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedWalletId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: loan.loanType == 'given' ? 'Receiving Wallet' : 'Payment Wallet',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: matchingWallets.map((wallet) => DropdownMenuItem<int>(
                    value: (wallet['id'] as num).toInt(),
                    child: Text('${wallet['name']} (${wallet['currency']})', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (value) { if (value != null) setSheetState(() => selectedWalletId = value); },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Payment Date'),
                  subtitle: Text(DateFormat('dd MMM yyyy').format(paymentDate)),
                  trailing: const Icon(Icons.calendar_month_rounded),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: paymentDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setSheetState(() => paymentDate = picked);
                  },
                ),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: 'Notes (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final amount = double.tryParse(amountController.text.trim());
                      if (amount == null || !amount.isFinite || amount <= 0 || amount > loan.remainingAmount) {
                        _message('Enter a valid amount not greater than the remaining balance.');
                        return;
                      }
                      Navigator.pop(sheetContext, true);
                    },
                    child: Text(loan.loanType == 'given' ? 'Save Received Payment' : 'Save Repayment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true) {
      try {
        final amount = double.parse(amountController.text.trim());
        await LoansService.addRepayment(RepaymentModel(
          loanId: loan.id!,
          amount: amount,
          walletId: selectedWalletId,
          repaymentDate: paymentDate.toIso8601String().split('T').first,
          paymentMethod: 'wallet',
          notes: notesController.text.trim(),
          createdAt: DateTime.now().toIso8601String(),
        ));
        await _loadData();
        _message(loan.loanType == 'given' ? 'Payment received successfully.' : 'Repayment saved successfully.');
      } catch (error) {
        _message(error.toString().replaceFirst('Exception: ', ''));
      }
    }
    amountController.dispose();
    notesController.dispose();
  }

  Widget _assetDesignLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
          color: Color(0xFF829087),
        ),
      ),
    );
  }

  Widget _legacyAssetCard(AssetsModel asset) {
    final purchaseCurrency = asset.currency.toUpperCase();
    final saleCurrency = asset.currency.toUpperCase();
    final currency = asset.isSold ? saleCurrency : purchaseCurrency;
    final value = asset.isSold && asset.salePrice != null ? asset.salePrice! : asset.currentValue;
    final profitLoss = asset.isSold && asset.salePrice != null ? asset.salePrice! - asset.purchasePrice : asset.currentValue - asset.purchasePrice;
    final categoryIcon = <String, IconData>{
      'Property': Icons.home_work_outlined, 'Vehicles': Icons.directions_car_outlined,
      'Gold': Icons.diamond_outlined, 'Jewellery': Icons.watch_outlined,
      'Electronics': Icons.devices_other_outlined, 'Investments': Icons.trending_up_rounded,
      'Livestock': Icons.pets_outlined, 'Business': Icons.storefront_outlined,
    }[asset.category] ?? Icons.inventory_2_outlined;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFFE7EEEA))),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFE8F4EE), borderRadius: BorderRadius.circular(12)), child: Icon(categoryIcon, color: const Color(0xFF147D59), size: 21)),
          title: Row(children: [
            Expanded(child: Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            if (asset.isSold) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFFFE9E9), borderRadius: BorderRadius.circular(7)), child: const Text('SOLD', style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.w800))),
          ]),
          subtitle: Padding(padding: const EdgeInsets.only(top: 3), child: Text('${asset.category} • ${asset.paymentType.toLowerCase() == 'loan' ? '${_partyName(asset.partyId)} • ' : ''}${DateFormat('dd MMM yyyy').format(asset.purchaseDate)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black54))),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Text('$currency ${_money(value)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF147D59))),
            const Text('Value', style: TextStyle(fontSize: 9, color: Colors.black45)),
          ]),
          children: [
            const Divider(height: 8),
            _detailRow('Purchase Price', '$purchaseCurrency ${_money(asset.purchasePrice)}'),
            const SizedBox(height: 6),
            if (!asset.isSold) _detailRow('Current Value', '$currency ${_money(asset.currentValue)}', bold: true),
            if (asset.isSold && asset.salePrice != null) _detailRow('Sale Price', '$saleCurrency ${_money(asset.salePrice!)}', bold: true),
            const SizedBox(height: 6),
            _detailRow(asset.isSold ? 'Realized Profit/Loss' : 'Unrealized Profit/Loss', '$currency ${_money(profitLoss)}', valueColor: profitLoss >= 0 ? Colors.green : Colors.red, bold: true),
            const SizedBox(height: 6),
            _detailRow('Purchase Payment Type', asset.paymentType),
            if (asset.paymentType.toLowerCase() == 'loan') _detailRow('Payable Party', _partyName(asset.partyId)),
            _detailRow('Purchase Wallet', asset.paymentType.toLowerCase() == 'loan' ? 'Loan (no initial wallet debit)' : _walletName(asset.walletId)),
            if (asset.isSold) _detailRow('Sale Payment Type', asset.salePaymentType),
            if (asset.isSold && asset.salePaymentType.toLowerCase() == 'loan') _detailRow('Receivable Party', _partyName(asset.salePartyId)),
            if (asset.isSold && asset.salePaymentType.toLowerCase() != 'loan') _detailRow('Sale Wallet', _walletName(asset.saleWalletId ?? asset.walletId)),
            const SizedBox(height: 6),
            _detailRow('Purchase Date', DateFormat('dd MMM yyyy').format(asset.purchaseDate)),
            if (asset.isSold && asset.saleDate != null) _detailRow('Sale Date', DateFormat('dd MMM yyyy').format(asset.saleDate!)),
            if (asset.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: Text(asset.notes, style: const TextStyle(color: Colors.black54, fontSize: 11)))),
            Align(alignment: Alignment.centerRight, child: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit' && !asset.isSold) { _showAssetDialog(asset: asset); }
                else if (value == 'valuation' && !asset.isSold) { _updateValuation(asset); }
                else if (value == 'sell' && !asset.isSold) { _sellAsset(asset); }
                else if (value == 'delete') { _deleteAsset(asset); }
              },
              itemBuilder: (context) => [
                if (!asset.isSold) PopupMenuItem(value: 'edit', child: Text(appText(context, 'Edit Asset', 'اثاثے میں ترمیم کریں'))),
                if (!asset.isSold) PopupMenuItem(value: 'valuation', child: Text(appText(context, 'Update Valuation', 'قیمت اپ ڈیٹ کریں'))),
                if (!asset.isSold) PopupMenuItem(value: 'sell', child: Text(appText(context, 'Sell Asset', 'اثاثہ فروخت کریں'))),
                PopupMenuItem(value: 'delete', child: Text(appText(context, 'Delete Asset', 'اثاثہ حذف کریں'))),
              ],
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7), decoration: BoxDecoration(color: const Color(0xFFF1F7F3), borderRadius: BorderRadius.circular(9)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.tune_rounded, size: 15, color: Color(0xFF147D59)), SizedBox(width: 5), Text('Manage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF147D59)))])),
            )),
          ],
        ),
      ),
    );
  }


  Widget _assetCard(AssetsModel asset) {
    final currency = asset.currency.toUpperCase();
    final displayedValue = asset.isSold && asset.salePrice != null
        ? asset.salePrice!
        : asset.currentValue;
    final profitLoss = asset.isSold && asset.salePrice != null
        ? asset.salePrice! - asset.purchasePrice
        : asset.currentValue - asset.purchasePrice;
    final purchaseLoan = asset.linkedLoanId == null ? null : _linkedLoans[asset.linkedLoanId!];
    final saleLoan = asset.saleLinkedLoanId == null ? null : _linkedLoans[asset.saleLinkedLoanId!];
    final payableOutstanding = purchaseLoan != null && purchaseLoan.remainingAmount > 0;
    final receivableOutstanding = saleLoan != null && saleLoan.remainingAmount > 0;
    final categoryIcon = <String, IconData>{
      'Property': Icons.home_work_outlined,
      'Vehicles': Icons.directions_car_outlined,
      'Gold': Icons.diamond_outlined,
      'Jewellery': Icons.watch_outlined,
      'Electronics': Icons.devices_other_outlined,
      'Investments': Icons.trending_up_rounded,
      'Livestock': Icons.pets_outlined,
      'Business': Icons.storefront_outlined,
    }[asset.category] ?? Icons.inventory_2_outlined;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1EAE5)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF173F30).withValues(alpha: .055), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _openAssetDetails(asset),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 11),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F4EE),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(categoryIcon, color: const Color(0xFF147D59), size: 22),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF172B25))),
                            const SizedBox(height: 3),
                            Text('${asset.category}  •  ${asset.paymentType.toLowerCase() == 'loan' ? 'Loan  •  ' : ''}${DateFormat('dd MMM yyyy').format(asset.purchaseDate)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFFD6F5E7), fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Transform.translate(
                        offset: const Offset(19, -9),
                        child: PopupMenuButton<String>(
                        tooltip: 'Manage Asset',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 160),
                        icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF87968E)),
                        onSelected: (value) {
                          if (value == 'edit' && !asset.isSold) {
                            _showAssetDialog(asset: asset);
                          } else if (value == 'valuation' && !asset.isSold) {
                            _updateValuation(asset);
                          } else if (value == 'sell' && !asset.isSold) {
                            _sellAsset(asset);
                          } else if (value == 'delete') {
                            _deleteAsset(asset);
                          }
                        },
                        itemBuilder: (context) => [
                          if (!asset.isSold)
                            const PopupMenuItem(value: 'edit', child: Text('Edit Asset')),
                          if (!asset.isSold)
                            const PopupMenuItem(value: 'valuation', child: Text('Update Valuation')),
                          if (!asset.isSold)
                            const PopupMenuItem(value: 'sell', child: Text('Sell Asset')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete Asset')),
                        ],
                      ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      Expanded(child: _assetCardMetric('Purchase Value', '$currency ${_money(asset.purchasePrice)}')),
                      Container(width: 1, height: 30, color: const Color(0xFFE5ECE8)),
                      const SizedBox(width: 12),
                      Expanded(child: _assetCardMetric(asset.isSold ? 'Sale Value' : 'Current Value', '$currency ${_money(displayedValue)}')),
                      Container(width: 1, height: 30, color: const Color(0xFFE5ECE8)),
                      const SizedBox(width: 12),
                      Expanded(child: _assetCardMetric(asset.isSold ? 'Realized P/L' : 'Unrealized P/L',
                        '$currency ${_money(profitLoss)}', valueColor: profitLoss >= 0 ? const Color(0xFF15945D) : const Color(0xFFD94747))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _assetStatusChip(
                              asset.isSold ? 'SOLD' : asset.paymentType.toUpperCase(),
                              asset.isSold ? const Color(0xFFFFEEEE) : const Color(0xFFEAF5EF),
                              asset.isSold ? const Color(0xFFC23D3D) : const Color(0xFF147D59),
                            ),
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('View Entries', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF147D59))),
                                SizedBox(width: 2),
                                Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF147D59)),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (payableOutstanding)
                              OutlinedButton(
                                onPressed: () => _addAssetRepayment(purchaseLoan!),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF1763A8),
                                  side: const BorderSide(color: Color(0xFFBBD5EA)),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                                  minimumSize: const Size(0, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.payments_outlined, size: 12),
                                  SizedBox(width: 3),
                                  Text('Pay Back', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                                ]),
                              ),
                            if (payableOutstanding && receivableOutstanding) const SizedBox(width: 4),
                            if (receivableOutstanding)
                              OutlinedButton(
                                onPressed: () => _addAssetRepayment(saleLoan!),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF168451),
                                  side: const BorderSide(color: Color(0xFFB9E2CB)),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                                  minimumSize: const Size(0, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.call_received_rounded, size: 12),
                                  SizedBox(width: 3),
                                  Text('Receive', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                                ]),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assetCardMetric(String label, String value, {Color valueColor = const Color(0xFF24362E)}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9.5, color: Color(0xFF819087), fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: valueColor)),
      ],
    );
  }

  Widget _assetStatusChip(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: foreground, letterSpacing: .3)),
    );
  }

  Widget _detailRow(
    String title,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Text(title),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Text(
            value,
            textAlign: TextAlign.end,
            softWrap: true,
            style: TextStyle(
              color: valueColor,
              fontWeight:
                  bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _currencySummary(String currency) {
    final current = _currentValues[currency] ?? 0;
    final purchase = _purchaseValues[currency] ?? 0;
    final realized = _realizedProfitLoss[currency] ?? 0;

    final unrealized = current - purchase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            currency,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.65,
            children: [
              _summaryCard(
                'Current Value',
                currency,
                current,
                Icons.account_balance,
              ),
              _summaryCard(
                'Purchase Value',
                currency,
                purchase,
                Icons.shopping_bag,
                color: Colors.blue,
              ),
              _summaryCard(
                'Realized Profit/Loss',
                currency,
                realized,
                Icons.trending_up,
                color: realized >= 0
                    ? Colors.green
                    : Colors.red,
              ),
              _summaryCard(
                'Unrealized Profit/Loss',
                currency,
                unrealized,
                Icons.show_chart,
                color: unrealized >= 0
                    ? Colors.green
                    : Colors.red,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final currencies = _availableCurrencies;

    final primaryCurrency = currencies.contains('PKR')
        ? 'PKR'
        : (currencies.isNotEmpty ? currencies.first : 'PKR');
    final currentTotal = _currentValues[primaryCurrency] ?? 0;
    final purchaseTotal = _purchaseValues[primaryCurrency] ?? 0;
    final unrealized = currentTotal - purchaseTotal;
    final categoryItems = <Map<String, dynamic>>[
      {'name': 'Business', 'icon': Icons.storefront_outlined},
      {'name': 'Electronics', 'icon': Icons.devices_other_outlined},
      {'name': 'Gold', 'icon': Icons.diamond_outlined},
      {'name': 'Investments', 'icon': Icons.trending_up_rounded},
      {'name': 'Jewellery', 'icon': Icons.watch_outlined},
      {'name': 'Livestock', 'icon': Icons.pets_outlined},
      {'name': 'Property', 'icon': Icons.home_work_outlined},
      {'name': 'Vehicles', 'icon': Icons.directions_car_outlined},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202A26),
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: GeneralPreferences.instance.personalizedHeaderTitle(context, Text(appText(context, "My Assets", "My Assets"), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF202A26)))),
        actions: buildSharedAppBarActions(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE7EEEA)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAssetDialog,
        backgroundColor: const Color(0xFF147D59),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(appText(context, 'Add Asset', 'اثاثہ شامل کریں')),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF147D59), Color(0xFF0B6245)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${appText(context, 'TOTAL ASSET VALUE', 'کل اثاثوں کی مالیت')}  •  $primaryCurrency',
                          style: const TextStyle(color: Color(0xFFD6F5E7), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
                        SizedBox(height: 5),
                        Text('$primaryCurrency ${_money(currentTotal)}',
                          style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _heroMetric('Purchase Value', '$primaryCurrency ${_money(purchaseTotal)}')),
                            Container(width: 1, height: 28, color: Colors.white24),
                            SizedBox(width: 14),
                            Expanded(child: _heroMetric('Unrealized P/L', '$primaryCurrency ${_money(unrealized)}', valueColor: unrealized >= 0 ? const Color(0xFFB9F6D3) : const Color(0xFFFFC5C5))),
                          ],
                        ),
                        if (currencies.length > 1) ...[
                          SizedBox(height: 7),
                          Text(appText(context, "Totals shown for this currency; other currencies below.", "Totals shown for this currency; other currencies below."),
                            style: TextStyle(color: Color(0xFFD6F5E7), fontSize: 10)),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 10),
                  SizedBox(height: 10),
                  GridView.builder(
                    itemCount: categoryItems.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, crossAxisSpacing: 7, mainAxisSpacing: 7, childAspectRatio: 1.70),
                    itemBuilder: (context, index) {
                      final item = categoryItems[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _selectedCategory = _selectedCategory == item['name'] ? null : item['name'] as String),
                        child: Container(
                          decoration: BoxDecoration(color: _selectedCategory == item['name'] ? const Color(0xFFE5F4EC) : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _selectedCategory == item['name'] ? const Color(0xFF147D59) : const Color(0xFFE7EEEA), width: _selectedCategory == item['name'] ? 1.5 : 1)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(item['icon'] as IconData, color: const Color(0xFF147D59), size: 19),
                            SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(item['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                _selectedCategory == null ? 'My Assets' : '${_selectedCategory!} Assets',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '(${_visibleAssets.where((a) => !a.isSold).length} ${appText(context, 'Active', 'فعال')})',
                              style: const TextStyle(color: Color(0xFF147D59), fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _showParties,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_alt_outlined, size: 16),
                            const SizedBox(width: 3),
                            Text('Manage Party (${_parties.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (currencies.isNotEmpty)
                    ...currencies.where((c) => c != primaryCurrency).map(_currencySummary),
                  SizedBox(
                    height: 38,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          appText(context, "Show Sold Assets", "Show Sold Assets"),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Transform.scale(
                          scale: 0.82,
                          child: Switch(
                            value: _showSold,
                            onChanged: (value) {
                              setState(() => _showSold = value);
                              _loadData();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_visibleAssets.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                      child: Column(children: [
                        const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 10),
                        Text(_selectedCategory == null ? 'No assets added yet' : 'No ${_selectedCategory!} assets found', style: const TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text(_selectedCategory == null ? 'Add your first asset to start tracking its value.' : 'Add an asset in this category to see it here.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ]),
                    )
                  else
                    ..._visibleAssets.expand((asset) => [
                      _assetDesignLabel('NEW DESIGN'),
                      _assetCard(asset),
                      _assetDesignLabel('PREVIOUS DESIGN'),
                      _legacyAssetCard(asset),
                      const SizedBox(height: 8),
                    ]),
                ],
              ),
            ),
    );
  }
}


class AssetDetailsScreen extends StatelessWidget {
  final AssetsModel asset;
  final LoansModel? purchaseLoan;
  final LoansModel? saleLoan;
  final List<RepaymentModel> purchaseRepayments;
  final List<RepaymentModel> saleRepayments;
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> parties;
  final bool hideBalances;

  const AssetDetailsScreen({
    super.key,
    required this.asset,
    required this.purchaseLoan,
    required this.saleLoan,
    required this.purchaseRepayments,
    required this.saleRepayments,
    required this.wallets,
    required this.parties,
    required this.hideBalances,
  });

  String _money(double value) => hideBalances ? '••••••' : NumberFormat('#,##0.00').format(value);

  String _walletName(int? id) {
    if (id == null) return 'Wallet';
    for (final wallet in wallets) {
      if ((wallet['id'] as num).toInt() == id) return wallet['name'].toString();
    }
    return 'Wallet';
  }

  String _partyName(int? id) {
    if (id == null) return 'Party';
    for (final party in parties) {
      if ((party['id'] as num).toInt() == id) return party['name'].toString();
    }
    return 'Party';
  }

  Widget _detailRow(String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(title, style: const TextStyle(color: Color(0xFFD6F5E7), fontSize: 11))),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = asset.currency.toUpperCase();
    final events = <Map<String, dynamic>>[
      {
        'date': asset.purchaseDate,
        'title': 'Asset Purchased',
        'subtitle': asset.paymentType.toLowerCase() == 'loan'
            ? 'Loan taken from ${_partyName(asset.partyId)}'
            : 'Paid from ${_walletName(asset.walletId)}',
        'amount': asset.purchasePrice,
        'type': 'debit',
        'icon': Icons.shopping_bag_outlined,
      },
      if (asset.isSold && asset.saleDate != null)
        {
          'date': asset.saleDate!,
          'title': 'Asset Sold',
          'subtitle': asset.salePaymentType.toLowerCase() == 'loan'
              ? 'Sold on credit to ${_partyName(asset.salePartyId)}'
              : 'Received in ${_walletName(asset.saleWalletId ?? asset.walletId)}',
          'amount': asset.salePrice ?? 0.0,
          'type': 'credit',
          'icon': Icons.sell_outlined,
        },
      ...purchaseRepayments.map((payment) => {
        'date': DateTime.tryParse(payment.repaymentDate) ?? DateTime.now(),
        'title': 'Loan Repayment',
        'subtitle': '${_walletName(payment.walletId)} • ${payment.notes.isEmpty ? 'Payment to ${_partyName(purchaseLoan?.partyId)}' : payment.notes}',
        'amount': payment.amount,
        'type': 'debit',
        'icon': Icons.payments_outlined,
      }),
      ...saleRepayments.map((payment) => {
        'date': DateTime.tryParse(payment.repaymentDate) ?? DateTime.now(),
        'title': 'Payment Received',
        'subtitle': '${_walletName(payment.walletId)} • ${payment.notes.isEmpty ? 'Received from ${_partyName(saleLoan?.partyId)}' : payment.notes}',
        'amount': payment.amount,
        'type': 'credit',
        'icon': Icons.call_received_rounded,
      }),
    ];
    events.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    final currentValue = asset.isSold && asset.salePrice != null ? asset.salePrice! : asset.currentValue;
    final profitLoss = currentValue - asset.purchasePrice;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202A26),
        elevation: 0,
        title: const Text('Asset Details', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF123F35), Color(0xFF176B52), Color(0xFF218565)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: const Color(0xFF123F35).withValues(alpha: .14), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 42, height: 42,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 23)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('${asset.category} • ${DateFormat('dd MMM yyyy').format(asset.purchaseDate)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFD6F5E7), fontSize: 11)),
                  ])),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: asset.isSold ? Colors.white.withValues(alpha: .16) : const Color(0xFFB9F6D3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(asset.isSold ? 'Sold' : 'Active',
                      style: TextStyle(color: asset.isSold ? Colors.white : const Color(0xFF145B43), fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 10),
                const Text('CURRENT ASSET VALUE', style: TextStyle(color: Color(0xFFD6F5E7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .5)),
                const SizedBox(height: 4),
                Text('$currency ${_money(currentValue)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 9),
                Row(children: [
                  Expanded(child: _metric('Purchase Value', '$currency ${_money(asset.purchasePrice)}')),
                  Container(width: 1, height: 30, color: Colors.white24),
                  const SizedBox(width: 14),
                  Expanded(child: _metric(asset.isSold ? 'Realized P/L' : 'Unrealized P/L',
                    '$currency ${_money(profitLoss)}', color: profitLoss >= 0 ? const Color(0xFFB9F6D3) : const Color(0xFFFFC5C5))),
                ]),
                const SizedBox(height: 10),
                _detailRow('Purchase Wallet', asset.paymentType.toLowerCase() == 'loan' ? 'Loan (no initial wallet debit)' : _walletName(asset.walletId)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Text('Related Entries', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF172B25)))),
            Text('${events.length} entries', style: const TextStyle(fontSize: 11, color: Color(0xFF7A8981), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 9),
          if (events.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Center(child: Text('No entries found for this asset.')),
            )
          else
            ...events.map((event) {
              final isCredit = event['type'] == 'credit';
              final amount = event['amount'] as double;
              final date = event['date'] as DateTime;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFE7EEEA))),
                child: Row(children: [
                  Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: isCredit ? const Color(0xFFE9F6EF) : const Color(0xFFFFF1E9), borderRadius: BorderRadius.circular(12)),
                    child: Icon(event['icon'] as IconData, color: isCredit ? const Color(0xFF168451) : const Color(0xFFB96A35), size: 20)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(event['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF24362E))),
                    const SizedBox(height: 3),
                    Text(event['subtitle'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF7A8981))),
                    const SizedBox(height: 3),
                    Text(DateFormat('dd MMM yyyy').format(date),
                      style: const TextStyle(fontSize: 10, color: Color(0xFF929D97))),
                  ])),
                  const SizedBox(width: 8),
                  Text('${isCredit ? '+' : '−'}$currency ${_money(amount)}',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                      color: isCredit ? const Color(0xFF168451) : const Color(0xFFB96A35))),
                ]),
              );
            }),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, {Color color = Colors.white}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Color(0xFFD6F5E7), fontSize: 10)),
      const SizedBox(height: 4),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
    ],
  );
}
