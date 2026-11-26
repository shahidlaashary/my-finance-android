import 'package:my_finance/core/preferences/sound_settings_service.dart';

import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:my_finance/core/files/attachment_service.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/modules/finance/models/assets_model.dart';
import 'package:my_finance/modules/finance/models/loans_model.dart';
import 'package:my_finance/modules/finance/models/repayment_model.dart';
import 'package:my_finance/modules/finance/screens/asset_loan_repayment_entry_form.dart';
import 'package:my_finance/modules/finance/services/assets_service.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';
import 'package:my_finance/modules/finance/services/currency_service.dart';
import 'package:my_finance/modules/finance/screens/asset_valuation_entry_form.dart';
import 'package:my_finance/modules/finance/screens/asset_sale_entry_form.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';
import 'package:my_finance/modules/parties/services/party_service.dart';
import 'package:my_finance/modules/parties/screens/manage_parties_screen.dart';
import 'package:my_finance/modules/finance/screens/finance_graph_screens.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

/// Assets list, filters aur asset-related actions ki main screen hai.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => AssetsScreenState();
}

class AssetsScreenState extends State<AssetsScreen> {
  final AssetsService _service = AssetsService();

  List<AssetsModel> _assets = [];
  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _parties = [];
  Map<int, LoansModel> _linkedLoans = {};

  Map<String, double> _currentValues = {};
  Map<String, double> _purchaseValues = {};

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
        builder: (_) => ManageParties(
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

  void _onAppDataChanged() {
    if (mounted) _loadData();
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
    AppRefreshController.revision.removeListener(_onAppDataChanged);
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

      final wallets = await WalletService.getWallets(orderBy: 'name ASC');
      final parties = await PartyService.getParties();
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _message('Error loading assets: $e');
    }
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
          title: Text('Create Party'),
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
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );

    Map<String, dynamic>? createdParty;
    if (saved == true) {
      try {
        final id = await PartyService.addParty(
          name: name.text.trim(),
          phone: phone.text.trim(),
          address: address.text.trim(),
          currency: selectedCurrency,
        );
        final refreshed = await PartyService.getParties();
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
      ..._assets.map((asset) => asset.currency.toUpperCase()),
    };

    final result = currencies.toList()..sort();

    return result;
  }

  void _closeAssetForm(BuildContext sheetContext) {
    if (Navigator.of(sheetContext).canPop()) {
      Navigator.of(sheetContext).pop();
    }
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
    String selectedPaymentType = asset?.paymentType.toLowerCase() == 'loan' ? 'Loan' : 'Wallet';
    final defaultAssetCurrency = asset?.currency ?? await CurrencyService.getBaseCurrency();
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
    void disposeAssetControllers() {
      nameController.dispose();
      purchaseController.dispose();
      currentController.dispose();
      notesController.dispose();
      newPartyNameController.dispose();
      newPartyPhoneController.dispose();
    }

    InputDecoration fieldDecoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      isDense: true,
    );

    final assetForm = StatefulBuilder(
      builder: (context, setSheetState) {
          final sheetContext = context;
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
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
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
                          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(10)))),
                          SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: Text(asset == null ? 'Add Asset' : 'Edit Asset', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface))),
                            IconButton(onPressed: () => _closeAssetForm(sheetContext), icon: Icon(Icons.close_rounded), color: Theme.of(context).hintColor),
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
                              items: const ['Wallet', 'Loan'].map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
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
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
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
                                      Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 10),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(appText(context, 'Purchase Date', 'خریداری کی تاریخ'), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                                        const SizedBox(height: 3),
                                        Text(DateFormat('dd MMM yyyy').format(purchaseDate), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      ])),
                                      Icon(Icons.edit_calendar, size: 18, color: Theme.of(context).colorScheme.primary),
                                    ]),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(children: [
                                  Expanded(child: Text('Include in Consolidated Balance', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), maxLines: 2)),
                                  Transform.scale(
                                    scale: 0.85,
                                    child: Switch(
                                      value: includeInConsolidatedBalance,
                                      activeColor: Theme.of(context).colorScheme.primary,
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
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(children: [
                                  Icon(Icons.attach_file_rounded, color: Theme.of(context).colorScheme.primary, size: 18),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text('Asset Attachments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                                  Text('${pendingFiles.length} selected', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                                ]),
                                const SizedBox(height: 6),
                                Wrap(spacing: 8, runSpacing: 4, children: [
                                  _assetAttachmentButton(Icons.camera_alt_outlined, 'Camera', pickCamera, Theme.of(context).colorScheme.primary),
                                  _assetAttachmentButton(Icons.photo_library_outlined, 'Gallery', pickGallery, Theme.of(context).colorScheme.tertiary),
                                  _assetAttachmentButton(Icons.picture_as_pdf_outlined, 'PDFs', pickPdfs, Theme.of(context).colorScheme.error),
                                ]),
                                if (pendingFiles.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  ...pendingFiles.asMap().entries.map((entry) => Row(children: [
                                    Icon(entry.value['name']!.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image_outlined, size: 17, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 7),
                                    Expanded(child: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11))),
                                    IconButton(visualDensity: VisualDensity.compact, onPressed: saving ? null : () => setSheetState(() => pendingFiles.removeAt(entry.key)), icon: Icon(Icons.close, size: 17, color: Theme.of(context).colorScheme.error)),
                                  ])),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(children: [
                            Expanded(child: OutlinedButton(onPressed: () => _closeAssetForm(sheetContext), child: Text(appText(context, 'Cancel', 'منسوخ کریں')))),
                            SizedBox(width: 10),
                            Expanded(child: ElevatedButton.icon(
                              icon: Icon(Icons.check_rounded), label: Text(asset == null ? 'Save Asset' : 'Update Asset'),
                              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 13)),
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                try {
                                  if (createNewParty) {
                                    setSheetState(() => saving = true);
                                    final createdId = await PartyService.addParty(
                                      name: newPartyNameController.text.trim(),
                                      phone: newPartyPhoneController.text.trim(),
                                      currency: newPartyCurrency,
                                    );
                                    _parties = await PartyService.getParties();
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
                                    assetId = await _service.addAssetWithAttachments(
                                      model,
                                      pendingFiles,
                                    );
                                  } else {
                                    await _service.updateAsset(model);
                                    assetId = asset.id!;
                                    for (final file in pendingFiles) {
                                      await AttachmentService.addAttachment(
                                        ownerType: 'asset',
                                        ownerId: assetId,
                                        sourcePath: file['path']!,
                                        originalFileName: file['name'],
                                      );
                                    }
                                  }
                                  if (!sheetContext.mounted) return;
                                  _closeAssetForm(sheetContext);
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
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => assetForm,
    );
    disposeAssetControllers();
  }

  Future<void> _updateValuation(AssetsModel asset) async {
    if (asset.id == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AssetValuationEntryForm(asset: asset),
    );
    if (saved == true) {
      await _loadData();
      if (mounted) _message('Asset valuation updated.');
    }
  }

  Future<void> _sellAsset(AssetsModel asset) async {
    if (asset.id == null) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AssetSaleEntryForm(
        asset: asset,
        wallets: _wallets,
        parties: _parties,
        onCreateParty: _createParty,
      ),
    );
    if (result == null) return;
    try {
      await _service.sellAsset(
        assetId: asset.id!,
        salePrice: result['price'] as double,
        saleDate: result['date'] as DateTime,
        saleWalletId: result['walletId'] as int,
        paymentType: result['paymentType'] as String,
        partyId: result['partyId'] as int?,
        walletAmount: result['walletAmount'] as double?,
        walletCurrency: result['walletCurrency'] as String?,
        exchangeRate: (result['exchangeRate'] as num?)?.toDouble() ?? 1.0,
        isManualRate: result['isManualRate'] as bool? ?? false,
      );
      await SoundSettingsService.instance.play('income');
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
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(appText(context, "Delete", "Delete")),
            ),
          ],
        );
      },
    );

    if (confirm != true || asset.id == null) return;

    try {
      await SoundSettingsService.instance.play('delete_warning');
      await _service.deleteAsset(asset.id!);
      await SoundSettingsService.instance.play('delete_success');
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
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .82), fontSize: 10)),
        SizedBox(height: 5),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _assetAttachmentButton(IconData icon, String label, VoidCallback onPressed, Color color) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AssetLoanRepaymentEntryForm(loan: loan),
    );
    if (saved == true) {
      await _loadData();
      if (mounted) {
        _message(loan.loanType == 'given'
            ? 'Payment received successfully.'
            : 'Repayment saved successfully.');
      }
    }
  }


  // Naya comparison design hai; original asset card neeche available rehta hai.
  Widget _redesignedAssetCard(AssetsModel asset) {
    final currency = asset.currency.toUpperCase();
    final displayedValue = asset.isSold && asset.salePrice != null
        ? asset.salePrice!
        : asset.currentValue;
    final profitLoss = displayedValue - asset.purchasePrice;
    final purchaseLoan = asset.linkedLoanId == null ? null : _linkedLoans[asset.linkedLoanId!];
    final saleLoan = asset.saleLinkedLoanId == null ? null : _linkedLoans[asset.saleLinkedLoanId!];
    final showPurchaseProgress = asset.paymentType.toLowerCase() == 'loan' && purchaseLoan != null;
    final showSaleProgress = asset.isSold &&
        asset.salePaymentType.toLowerCase() == 'loan' && saleLoan != null;
    final purchaseProgress = purchaseLoan == null || purchaseLoan.amount <= 0
        ? 0.0
        : (purchaseLoan.repaidAmount / purchaseLoan.amount).clamp(0.0, 1.0).toDouble();
    final saleProgress = saleLoan == null || saleLoan.amount <= 0
        ? 0.0
        : (saleLoan.repaidAmount / saleLoan.amount).clamp(0.0, 1.0).toDouble();
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

    Widget progressSection({
      required String title,
      required String completedLabel,
      required double completed,
      required double total,
      required double remaining,
      required double progress,
      required Color color,
      required IconData icon,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFE5EBF3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF263B59)))),
              Text('${(progress * 100).round()}%', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: color)),
            ]),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: const Color(0xFFE8EDF4),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(child: Text('$completedLabel: $currency ${_money(completed)}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF536987), fontWeight: FontWeight.w600))),
              const SizedBox(width: 6),
              Expanded(child: Text('Remaining: $currency ${_money(remaining)}', textAlign: TextAlign.end,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: Color(0xFF536987), fontWeight: FontWeight.w600))),
            ]),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E5E9)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 9, offset: Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openAssetDetails(asset),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EEFA),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(categoryIcon, color: const Color(0xFF315F9B), size: 21),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF101D3A))),
                const SizedBox(height: 3),
                Text('${asset.category} • ${asset.paymentType.toUpperCase()} • ${DateFormat('dd MMM yyyy').format(asset.purchaseDate)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF5B6F91))),
              ])),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: asset.isSold ? const Color(0xFFFFE9ED) : const Color(0xFFE7F8ED),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(asset.isSold ? 'SOLD' : 'ACTIVE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: asset.isSold ? const Color(0xFFDA233C) : const Color(0xFF11864A))),
              ),
              PopupMenuButton<String>(
                tooltip: 'Manage Asset',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 160),
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF536987)),
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
                  if (!asset.isSold) const PopupMenuItem(value: 'edit', child: Text('Edit Asset')),
                  if (!asset.isSold) const PopupMenuItem(value: 'valuation', child: Text('Update Valuation')),
                  if (!asset.isSold) const PopupMenuItem(value: 'sell', child: Text('Sell Asset')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete Asset')),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFE5EBF3)),
            ),
            child: Row(children: [
              Expanded(child: _assetCardMetric('Purchase Value', '$currency ${_money(asset.purchasePrice)}',
                valueColor: const Color(0xFF263B59))),
              Container(width: 1, height: 31, color: const Color(0xFFE0E8F1)),
              const SizedBox(width: 10),
              Expanded(child: _assetCardMetric(asset.isSold ? 'Sale Value' : 'Current Value',
                '$currency ${_money(displayedValue)}', valueColor: const Color(0xFF263B59))),
              Container(width: 1, height: 31, color: const Color(0xFFE0E8F1)),
              const SizedBox(width: 10),
              Expanded(child: _assetCardMetric(asset.isSold ? 'Realized P/L' : 'Unrealized P/L',
                '$currency ${_money(profitLoss)}',
                valueColor: profitLoss >= 0 ? const Color(0xFF159B61) : const Color(0xFFDA3A50))),
            ]),
          ),
          if (showPurchaseProgress || showSaleProgress) ...[
            const SizedBox(height: 7),
            if (showPurchaseProgress)
              progressSection(
                title: 'Credit Purchase Progress',
                completedLabel: 'Paid',
                completed: purchaseLoan!.repaidAmount,
                total: purchaseLoan.amount,
                remaining: purchaseLoan.remainingAmount,
                progress: purchaseProgress,
                color: const Color(0xFF159B61),
                icon: Icons.payments_outlined,
              ),
            if (showPurchaseProgress && showSaleProgress) const SizedBox(height: 6),
            if (showSaleProgress)
              progressSection(
                title: 'Credit Sale Recovery',
                completedLabel: 'Received',
                completed: saleLoan!.repaidAmount,
                total: saleLoan.amount,
                remaining: saleLoan.remainingAmount,
                progress: saleProgress,
                color: const Color(0xFF2674E8),
                icon: Icons.call_received_rounded,
              ),
          ],
          const SizedBox(height: 7),
          Row(children: [
            if (purchaseLoan != null && purchaseLoan.remainingAmount > 0)
              TextButton.icon(
                onPressed: () => _addAssetRepayment(purchaseLoan),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF159B61),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                ),
                icon: const Icon(Icons.payments_outlined, size: 15),
                label: const Text('Pay Back', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
            if (saleLoan != null && saleLoan.remainingAmount > 0)
              TextButton.icon(
                onPressed: () => _addAssetRepayment(saleLoan),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2674E8),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                ),
                icon: const Icon(Icons.call_received_rounded, size: 15),
                label: const Text('Receive', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openAssetDetails(asset),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                minimumSize: const Size(0, 32),
              ),
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: const Text('View Entries', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _assetCard(AssetsModel asset) {
    return _redesignedAssetCard(asset);
  }

  Widget _assetCardMetric(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: valueColor ?? Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }



  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    AppRefreshController.revision.addListener(_onAppDataChanged);
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: GeneralPreferences.instance.personalizedHeaderTitle(context, Text(appText(context, "My Assets", "My Assets"), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface))),
        actions: buildSharedAppBarActions(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primaryContainer],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('${appText(context, 'TOTAL ASSET VALUE', 'کل اثاثوں کی مالیت')}  •  $primaryCurrency',
                                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .82), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
                            ),
                            IconButton(
                              tooltip: 'View asset analytics',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(builder: (_) => AssetGraphScreen(hideBalances: _hideBalances)),
                              ),
                              icon: Icon(Icons.trending_up_rounded, color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8), size: 22),
                            ),
                          ],
                        ),
                        SizedBox(height: 5),
                        Text('$primaryCurrency ${_money(currentTotal)}',
                          style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 25, fontWeight: FontWeight.w800)),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _heroMetric('Purchase Value', '$primaryCurrency ${_money(purchaseTotal)}')),
                            Container(width: 1, height: 28, color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .14)),
                            SizedBox(width: 14),
                            Expanded(child: _heroMetric('Unrealized P/L', '$primaryCurrency ${_money(unrealized)}', valueColor: unrealized >= 0 ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.errorContainer)),
                          ],
                        ),

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
                          decoration: BoxDecoration(color: _selectedCategory == item['name'] ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _selectedCategory == item['name'] ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant, width: _selectedCategory == item['name'] ? 1.5 : 1)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(item['icon'] as IconData, color: Theme.of(context).colorScheme.primary, size: 19),
                            SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(item['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
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
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '(${_visibleAssets.where((a) => !a.isSold).length} ${appText(context, 'Active', 'فعال')})',
                              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w700),
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
                  SizedBox(
                    height: 38,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          appText(context, "Show Sold Assets", "Show Sold Assets"),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18)),
                      child: Column(children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: Theme.of(context).hintColor),
                        SizedBox(height: 10),
                        Text(_selectedCategory == null ? 'No assets added yet' : 'No ${_selectedCategory!} assets found', style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text(_selectedCategory == null ? 'Add your first asset to start tracking its value.' : 'Add an asset in this category to see it here.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                      ]),
                    )
                  else
                    ..._visibleAssets.expand((asset) => [
                      _assetCard(asset),
                      const SizedBox(height: 8),
                    ]),
                ],
              ),
            ),
    );
  }
}


/// Selected asset ki details, linked entries aur available actions show karta hai.
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

  Widget _detailRow(context, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .82), fontSize: 11))),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.end, style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 11, fontWeight: FontWeight.w600))),
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
          'wallet_amount': asset.saleWalletAmount,
          'wallet_currency': asset.saleWalletCurrency,
          'exchange_rate': asset.saleExchangeRate,
          'type': 'credit',
          'icon': Icons.sell_outlined,
        },
      ...purchaseRepayments.map((payment) => {
        'date': DateTime.tryParse(payment.repaymentDate) ?? DateTime.now(),
        'title': 'Loan Repayment',
        'subtitle': '${_walletName(payment.walletId)} • ${payment.notes.isEmpty ? 'Payment to ${_partyName(purchaseLoan?.partyId)}' : payment.notes}',
        'amount': payment.amount,
        'wallet_amount': payment.walletAmount,
        'wallet_currency': payment.walletCurrency,
        'exchange_rate': payment.exchangeRate,
        'type': 'debit',
        'icon': Icons.payments_outlined,
      }),
      ...saleRepayments.map((payment) => {
        'date': DateTime.tryParse(payment.repaymentDate) ?? DateTime.now(),
        'title': 'Payment Received',
        'subtitle': '${_walletName(payment.walletId)} • ${payment.notes.isEmpty ? 'Received from ${_partyName(saleLoan?.partyId)}' : payment.notes}',
        'amount': payment.amount,
        'wallet_amount': payment.walletAmount,
        'wallet_currency': payment.walletCurrency,
        'exchange_rate': payment.exchangeRate,
        'type': 'credit',
        'icon': Icons.call_received_rounded,
      }),
    ];
    events.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    final currentValue = asset.isSold && asset.salePrice != null ? asset.salePrice! : asset.currentValue;
    final profitLoss = currentValue - asset.purchasePrice;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        title: Text('Asset Details', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: .14), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 42, height: 42,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .14), borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.surface, size: 23)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(
                      '${asset.category}${asset.paymentType.toLowerCase() == 'loan' ? ' • ${_partyName(asset.partyId)}' : ''} • ${DateFormat('dd MMM yyyy').format(asset.purchaseDate)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .82), fontSize: 11),
                    ),
                  ])),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: asset.isSold ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: .16) : Theme.of(context).colorScheme.onPrimary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(asset.isSold ? 'Sold' : 'Active',
                      style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 10),
                Text('CURRENT ASSET VALUE', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .82), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .5)),
                const SizedBox(height: 4),
                Text('$currency ${_money(currentValue)}', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 9),
                Row(children: [
                  Expanded(child: _metric(context, 'Purchase Value', '$currency ${_money(asset.purchasePrice)}')),
                  Container(width: 1, height: 30, color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .14)),
                  const SizedBox(width: 14),
                  Expanded(child: _metric(context, asset.isSold ? 'Realized P/L' : 'Unrealized P/L',
                    '$currency ${_money(profitLoss)}', color: profitLoss >= 0 ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.errorContainer)),
                ]),
                const SizedBox(height: 10),
                _detailRow(context, 'Purchase Payment Type', asset.paymentType),
                if (asset.paymentType.toLowerCase() == 'loan')
                  _detailRow(context, 'Payable Party', _partyName(asset.partyId)),
                _detailRow(context, 'Purchase Wallet', asset.paymentType.toLowerCase() == 'loan' ? 'Loan (no initial wallet debit)' : _walletName(asset.walletId)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Text('Related Entries', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface))),
            Text('${events.length} entries', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 9),
          if (events.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
              child: Center(child: Text('No entries found for this asset.')),
            )
          else
            ...events.map((event) {
              final isCredit = event['type'] == 'credit';
              final amount = event['amount'] as double;
              final date = event['date'] as DateTime;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                child: Row(children: [
                  Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: isCredit ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                    child: Icon(event['icon'] as IconData, color: isCredit ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.tertiary, size: 20)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(event['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 3),
                    Text(event['subtitle'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor)),
                    const SizedBox(height: 3),
                    Text(DateFormat('dd MMM yyyy').format(date),
                      style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
                  ])),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${isCredit ? '+' : '−'}$currency ${_money(amount)}',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                          color: isCredit ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.tertiary)),
                      if (event['wallet_amount'] is num &&
                          (event['wallet_currency']?.toString().toUpperCase() ?? currency) != currency) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${event['wallet_currency']} ${_money((event['wallet_amount'] as num).toDouble())}',
                          textAlign: TextAlign.end,
                          style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
                        ),
                        if (event['exchange_rate'] is num && (event['exchange_rate'] as num).toDouble() > 0)
                          Text(
                            'Rate: 1 $currency = ${event['wallet_currency']} ${((event['exchange_rate'] as num).toDouble()).toStringAsFixed(4)}',
                            textAlign: TextAlign.end,
                            style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor),
                          ),
                      ],
                    ],
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }

  Widget _metric(context, String label, String value, {Color color = Colors.white}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .82), fontSize: 10)),
      const SizedBox(height: 4),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
    ],
  );
}
