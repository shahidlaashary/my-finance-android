import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:my_finance/modules/finance/models/loans_model.dart';
import 'package:my_finance/modules/parties/services/party_service.dart';

class ManageParties extends StatefulWidget {
  final bool hideBalances;
  final ValueChanged<LoansModel> onLoanTap;

  const ManageParties({
    super.key,
    required this.hideBalances,
    required this.onLoanTap,
  });

  @override
  State<ManageParties> createState() => _ManagePartiesState();
}

class _ManagePartiesState extends State<ManageParties> {
  List<Map<String, dynamic>> _parties = [];
  Map<String, double> _receivableByCurrency = {};
  Map<String, double> _payableByCurrency = {};
  int _partiesWithBalance = 0;
  bool _loading = true;
  bool _searchVisible = false;
  bool _showArchived = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _loadParties();
  }

  void _onAppDataChanged() { if (mounted) _loadParties(); }

  @override
  void dispose() {
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    super.dispose();
  }

  Future<void> _loadParties() async {
    final parties = await PartyService.getParties(includeArchived: true);
    final receivable = <String, double>{};
    final payable = <String, double>{};
    var partiesWithBalance = 0;
    for (final party in parties) {
      if ((party['is_archived'] as num?)?.toInt() == 1) continue;
      final summary = await PartyService.getPartySummary((party['id'] as num).toInt());
      final balances = (summary['balances'] as List<dynamic>?) ?? [];
      var hasBalance = false;
      for (final item in balances) {
        final currency = item['currency']?.toString().toUpperCase() ?? 'PKR';
        final amount = (item['outstanding'] as num?)?.toDouble() ?? 0;
        if (amount <= 0) continue;
        hasBalance = true;
        final target = item['loan_type'] == 'given' ? receivable : payable;
        target[currency] = (target[currency] ?? 0) + amount;
      }
      if (hasBalance) partiesWithBalance++;
    }
    if (!mounted) return;
    setState(() {
      _parties = parties;
      _receivableByCurrency = receivable;
      _payableByCurrency = payable;
      _partiesWithBalance = partiesWithBalance;
      _loading = false;
    });
  }

  Widget _overviewAmount(String label, Map<String, double> values, Color color, Color background) {
    final entries = values.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(13)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          if (entries.isEmpty)
            Text('—', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color))
          else
            ...entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('${entry.key} ${_money(entry.value)}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
            )),
        ]),
      ),
    );
  }

  Widget _partyOverviewCard() {
    final activeParties = _parties.where((p) => (p['is_archived'] as num?)?.toInt() != 1).toList();
    final archivedCount = _parties.length - activeParties.length;
    final individuals = activeParties.where((p) => (p['party_type']?.toString() ?? 'Individual').toLowerCase() != 'business').length;
    final businesses = activeParties.length - individuals;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF126B4B), Color(0xFF20966A)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF126B4B).withValues(alpha: .17), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 38, height: 38,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.groups_2_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 21)),
          const SizedBox(width: 10),
          Expanded(child: Text('Parties Overview', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 15, fontWeight: FontWeight.w800))),
          Text('${activeParties.length} Active • $archivedCount Archived', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .9), fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: _overviewCount('Individuals', individuals, Icons.person_outline_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _overviewCount('Businesses', businesses, Icons.business_outlined)),
          const SizedBox(width: 8),
          Expanded(child: _overviewCount('With Balance', _partiesWithBalance, Icons.account_balance_wallet_outlined)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _overviewAmount('RECEIVABLE', _receivableByCurrency, const Color(0xFF167447), const Color(0xFFE7F5EC)),
          const SizedBox(width: 8),
          _overviewAmount('PAYABLE', _payableByCurrency, const Color(0xFF9A5726), const Color(0xFFFFF0E3)),
        ]),
      ]),
    );
  }

  Widget _overviewCount(String label, int value, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .13), borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Icon(icon, color: Theme.of(context).colorScheme.onPrimary, size: 15),
      const SizedBox(width: 5),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$value', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 14, fontWeight: FontWeight.w900)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .85), fontSize: 9, fontWeight: FontWeight.w600)),
      ])),
    ]),
  );

  String _money(num value) =>
      widget.hideBalances ? '••••••' : value.toStringAsFixed(2);

  Future<void> _editParty([Map<String, dynamic>? party]) async {
    final name = TextEditingController(text: party?['name']?.toString() ?? '');
    final phone = TextEditingController(text: party?['phone']?.toString() ?? '');
    final email = TextEditingController(text: party?['email']?.toString() ?? '');
    final cnic = TextEditingController(text: party?['cnic']?.toString() ?? '');
    final referencePerson = TextEditingController(text: party?['reference_person']?.toString() ?? '');
    final country = TextEditingController(text: party?['country']?.toString() ?? '');
    final city = TextEditingController(text: party?['city']?.toString() ?? '');
    final address = TextEditingController(text: party?['address']?.toString() ?? '');
    final postalCode = TextEditingController(text: party?['postal_code']?.toString() ?? '');
    final openingBalance = TextEditingController(text: (party?['opening_balance'] ?? 0).toString());
    final creditLimit = TextEditingController(text: (party?['credit_limit'] ?? 0).toString());
    final notes = TextEditingController(text: party?['notes']?.toString() ?? '');
    final baseCurrency = await FinanceDB.instance.getBaseCurrency();
    String currency = (party?['currency']?.toString() ?? baseCurrency).toUpperCase();
    String partyType = party?['party_type']?.toString() ?? 'Individual';
    String paymentTerms = party?['payment_terms']?.toString() ?? 'Due on Receipt';
    String profilePath = party?['profile_image_path']?.toString() ?? '';
    XFile? pickedPhoto;
    final List<PlatformFile> pendingNoteAttachments = [];
    final existingPartyAttachments = party == null ? <dynamic>[] : await AttachmentService.getAttachments(ownerType: AttachmentOwnerTypes.party, ownerId: (party['id'] as num).toInt());
    const terms = ['Due on Receipt', '7 Days', '15 Days', '30 Days'];
    final formKey = GlobalKey<FormState>();
    final picker = ImagePicker();

    InputDecoration inputDecoration(String label, IconData icon) => InputDecoration(
      labelText: label, prefixIcon: Icon(icon, size: 15), isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      prefixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 40),
      isCollapsed: false,
      filled: true,
      fillColor: const Color(0xFFFBFDFC),
      constraints: const BoxConstraints(minHeight: 42),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE1E9E4))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.4)),
    );
    Widget field(TextEditingController c, String label, IconData icon, {TextInputType? type, int lines = 1, String? Function(String?)? validator}) => TextFormField(
      controller: c, keyboardType: type, maxLines: lines, validator: validator,
      decoration: inputDecoration(label, icon),
    );
    Widget section(String label, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 11, bottom: 6),
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 17),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF263B32))),
      ]),
    );
    Widget pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: a), const SizedBox(width: 7), Expanded(child: b),
    ]);

    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useSafeArea: true,
      showDragHandle: false, backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final screen = MediaQuery.sizeOf(context).height;
          final photo = pickedPhoto?.path ?? profilePath;
          final photoExists = photo.isNotEmpty && File(photo).existsSync();
          Future<void> choosePhoto(ImageSource source) async {
            try {
              final selected = await picker.pickImage(source: source, imageQuality: 82, maxWidth: 900);
              if (selected != null) setSheetState(() => pickedPhoto = selected);
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Photo select error: $e')));
            }
          }
          return Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SizedBox(
              height: (screen - keyboard).clamp(300.0, screen) * .94,
              child: Form(
                key: formKey,
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 10, 6),
                    child: Row(children: [
                      Expanded(child: Text(party == null ? 'Add New Party' : 'Edit Party', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                      IconButton(onPressed: () => Navigator.pop(sheetContext, false), icon: Icon(Icons.close_rounded)),
                    ]),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Center(child: Column(children: [
                          Stack(alignment: Alignment.bottomRight, children: [
                            CircleAvatar(radius: 32, backgroundColor: const Color(0xFFEAF3EE),
                              backgroundImage: photoExists ? FileImage(File(photo)) : null,
                              child: photoExists ? null : Icon(Icons.person_outline_rounded, size: 32, color: Theme.of(context).colorScheme.primary)),
                            Container(
                              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                icon: Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                                onPressed: () => showModalBottomSheet<void>(
                                  context: context, showDragHandle: true,
                                  builder: (photoContext) => SafeArea(child: Wrap(children: [
                                    ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('Choose from Gallery'), onTap: () { Navigator.pop(photoContext); choosePhoto(ImageSource.gallery); }),
                                    ListTile(leading: Icon(Icons.camera_alt_outlined), title: Text('Take Photo'), onTap: () { Navigator.pop(photoContext); choosePhoto(ImageSource.camera); }),
                                    if (photoExists) ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), title: Text('Remove Photo'), onTap: () { Navigator.pop(photoContext); setSheetState(() { pickedPhoto = null; profilePath = ''; }); }),
                                  ])),
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 3),
                          Text('Party Profile Photo', style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
                        ])),
                        section('Basic Information', Icons.person_outline_rounded),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: DropdownButtonFormField<String>(
                                value: partyType == 'Business' ? 'Business' : 'Individual',
                                isExpanded: true,
                                decoration: inputDecoration('Party Type', Icons.category_outlined),
                                items: const [
                                  DropdownMenuItem(value: 'Individual', child: Text('Individual', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 'Business', child: Text('Business', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (value) { if (value != null) setSheetState(() => partyType = value); },
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              flex: 6,
                              child: field(name, 'Party Name *', Icons.badge_outlined, validator: (v) => v == null || v.trim().isEmpty ? 'Party name is required' : null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        pair(field(phone, 'Phone Number', Icons.phone_outlined, type: TextInputType.phone), field(email, 'Email Address', Icons.email_outlined, type: TextInputType.emailAddress)),
                        const SizedBox(height: 10),
                        pair(field(cnic, 'CNIC / ID Number', Icons.credit_card_outlined), field(referencePerson, 'Reference Person', Icons.contacts_outlined)),
                        section('Address Information', Icons.location_on_outlined),
                        pair(field(country, 'Country', Icons.public_outlined), field(city, 'City', Icons.location_city_outlined)),
                        const SizedBox(height: 10),
                        pair(field(address, 'Complete Address', Icons.home_outlined, lines: 1), field(postalCode, 'Postal Code', Icons.markunread_mailbox_outlined)),
                        section('Financial Settings', Icons.account_balance_wallet_outlined),
                        pair(
                          DropdownButtonFormField<String>(
                            value: CurrencyCatalog.supported.contains(currency) ? currency : 'PKR',
                            isExpanded: true, decoration: inputDecoration('Currency *', Icons.currency_exchange_rounded),
                            items: CurrencyCatalog.supported.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                            onChanged: (v) { if (v != null) setSheetState(() => currency = v); },
                          ),
                          DropdownButtonFormField<String>(
                            value: terms.contains(paymentTerms) ? paymentTerms : terms.first,
                            isExpanded: true, decoration: inputDecoration('Payment Terms', Icons.event_note_outlined),
                            items: terms.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                            onChanged: (v) { if (v != null) setSheetState(() => paymentTerms = v); },
                          ),
                        ),
                        const SizedBox(height: 10),
                        pair(field(openingBalance, 'Opening Balance', Icons.account_balance_outlined, type: const TextInputType.numberWithOptions(decimal: true)), field(creditLimit, 'Credit Limit', Icons.speed_outlined, type: const TextInputType.numberWithOptions(decimal: true))),
                        section('Additional Information', Icons.notes_rounded),
                        TextFormField(
                          controller: notes,
                          maxLines: 2,
                          decoration: inputDecoration('Notes', Icons.sticky_note_2_outlined).copyWith(
                            suffixIcon: IconButton(
                              tooltip: 'Attach Files',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.attach_file_rounded, size: 19),
                              onPressed: () async {
                                try {
                                  final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true, withData: false);
                                  if (result != null) {
                                    setSheetState(() => pendingNoteAttachments.addAll(result.files.where((file) => file.path != null)));
                                  }
                                } catch (error) {
                                  if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Attachment select error: $error')));
                                }
                              },
                            ),
                            suffixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 40),
                          ),
                        ),
                        if (existingPartyAttachments.isNotEmpty || pendingNoteAttachments.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(color: const Color(0xFFF5F8F6), borderRadius: BorderRadius.circular(10)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...existingPartyAttachments.map((item) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(children: [
                                    Icon(Icons.attach_file, size: 15),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text('Saved', style: TextStyle(fontSize: 10, color: Color(0xFF16865B))),
                                  ]),
                                )),
                                ...pendingNoteAttachments.asMap().entries.map((entry) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(children: [
                                    Icon(Icons.insert_drive_file_outlined, size: 15),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(entry.value.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                      padding: EdgeInsets.zero,
                                      onPressed: () => setSheetState(() => pendingNoteAttachments.removeAt(entry.key)),
                                      icon: Icon(Icons.close_rounded, size: 16),
                                    ),
                                  ]),
                                )),
                              ],
                            ),
                          ),
                      ]),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 7, 16, 9 + MediaQuery.paddingOf(context).bottom),
                    child: SizedBox(width: double.infinity, child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
                      onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(sheetContext, true); },
                      icon: Icon(Icons.check_rounded, size: 18),
                      label: Text(party == null ? 'Save Party' : 'Update Party', style: TextStyle(fontWeight: FontWeight.w700)),
                    )),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );

    if (saved == true) {
      try {
        final opening = double.tryParse(openingBalance.text.trim()) ?? 0;
        final limit = double.tryParse(creditLimit.text.trim()) ?? 0;
        if (!opening.isFinite || !limit.isFinite || opening < 0 || limit < 0) throw Exception('Opening balance and credit limit must be valid non-negative amounts.');
        var storedPhoto = profilePath;
        if (pickedPhoto != null) {
          final docs = await getApplicationDocumentsDirectory();
          final folder = Directory(p.join(docs.path, 'party_profiles'));
          if (!await folder.exists()) await folder.create(recursive: true);
          final ext = p.extension(pickedPhoto!.path);
          final fileName = 'party_${party?['id'] ?? DateTime.now().microsecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}';
          storedPhoto = (await File(pickedPhoto!.path).copy(p.join(folder.path, fileName))).path;
        }
        int partyId;
        if (party == null) {
          partyId = await PartyService.addParty(name: name.text, phone: phone.text, address: address.text, currency: currency,
            email: email.text, partyType: partyType, country: country.text, city: city.text, postalCode: postalCode.text,
            openingBalance: opening, creditLimit: limit, paymentTerms: paymentTerms, cnic: cnic.text,
            businessName: '', taxNumber: '', referencePerson: referencePerson.text,
            notes: notes.text, profileImagePath: storedPhoto);
        } else {
          partyId = (party['id'] as num).toInt();
          await PartyService.updateParty(id: partyId, name: name.text, phone: phone.text,
            address: address.text, currency: currency, email: email.text, partyType: partyType, country: country.text,
            city: city.text, postalCode: postalCode.text, openingBalance: opening, creditLimit: limit,
            paymentTerms: paymentTerms, cnic: cnic.text,
            businessName: party['business_name']?.toString() ?? '',
            taxNumber: party['tax_number']?.toString() ?? '',
            referencePerson: referencePerson.text, notes: notes.text, profileImagePath: storedPhoto);
        }
        for (final attachment in pendingNoteAttachments) {
          if (attachment.path == null) continue;
          await AttachmentService.addAttachment(
            ownerType: AttachmentOwnerTypes.party,
            ownerId: partyId,
            sourcePath: attachment.path!,
            originalFileName: attachment.name,
          );
        }
        await _loadParties();
      } catch (error) {
        if (mounted) {
          final message = error.toString();
          if (message.toLowerCase().contains('already exists under')) {
            await showDialog<void>(
              context: this.context,
              builder: (dialogContext) => AlertDialog(
                icon: const Icon(Icons.error_outline_rounded),
                title: const Text('Party Already Exists'),
                content: Text(message.replaceFirst('Exception: ', '')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else {
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(content: Text('Could not save party: $error')),
            );
          }
        }
      }
    }
    for (final c in [name, phone, email, cnic, referencePerson, country, city, address, postalCode, openingBalance, creditLimit, notes]) {
      c.dispose();
    }
  }

  Future<void> _togglePartyArchive(Map<String, dynamic> party, {required bool archive}) async {
    try {
      await PartyService.setPartyArchived((party['id'] as num).toInt(), archived: archive);
      await _loadParties();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(archive ? 'Party moved to Archived.' : 'Party restored to Active.')),
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

  Future<void> _deleteParty(Map<String, dynamic> party) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Party?'),
        content: Text(
          'Delete "${party['name']}"? Parties linked to any loan cannot be deleted, so loan history remains safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PartyService.deleteParty((party['id'] as num).toInt());
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
    final loans = await PartyService.getLoansForParty(id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '${party['name']} • Ledger',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: Icon(Icons.close),
                  ),
                ]),
              ),
              Expanded(
                child: loans.isEmpty
                    ? Center(child: Text('No loan history for this party.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                        itemCount: loans.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (_, index) {
                          final loan = loans[index];
                          final isGiven = loan.loanType == 'given';
                          final color = isGiven ? const Color(0xFF168451) : const Color(0xFFB66A35);
                          final icon = isGiven ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.pop(context);
                                widget.onLoanTap(loan);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.11),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(icon, color: color, size: 21),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isGiven ? 'Loan Given' : 'Loan Taken',
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
                                            'Outstanding: ${loan.currency.toUpperCase()} ${_money(loan.remainingAmount)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            loan.lendingDate,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${isGiven ? '+' : '-'} ${loan.currency.toUpperCase()} ${_money(loan.amount)}',
                                      maxLines: 1,
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
    final query = _search.trim().toLowerCase();
    final tabParties = _parties.where((party) =>
      ((party['is_archived'] as num?)?.toInt() == 1) == _showArchived).toList();
    final filtered = tabParties.where((party) {
      if (query.isEmpty) return true;
      final searchable = [
        party['name'], party['phone'], party['email'], party['business_name'],
        party['city'], party['country'], party['cnic'], party['tax_number'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return searchable.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        title: Text('Manage Parties'),
        actions: [
          IconButton(
            tooltip: _searchVisible ? 'Close search' : 'Search parties',
            onPressed: () => setState(() {
              _searchVisible = !_searchVisible;
              if (!_searchVisible) _search = '';
            }),
            icon: Icon(_searchVisible ? Icons.close_rounded : Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Add Party',
            onPressed: () => _editParty(),
            icon: Icon(Icons.person_add_alt_1_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  hintText: 'Search name, phone, email or city',
                  prefixIcon: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.primary),
                  suffixIcon: _search.isEmpty ? null : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(() => _search = ''),
                    icon: Icon(Icons.close_rounded),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE2EBE5))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.3)),
                ),
              ),
            ),
          if (!_loading && _parties.isNotEmpty) _partyOverviewCard(),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.onPrimary, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE3ECE6))),
                child: Row(children: [
                  Expanded(child: _partyTabButton('Active', _parties.where((p) => (p['is_archived'] as num?)?.toInt() != 1).length, !_showArchived,
                    () => setState(() => _showArchived = false))),
                  const SizedBox(width: 4),
                  Expanded(child: _partyTabButton('Archived', _parties.where((p) => (p['is_archived'] as num?)?.toInt() == 1).length, _showArchived,
                    () => setState(() => _showArchived = true))),
                ]),
              ),
            ),

          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_search.isEmpty ? Icons.people_outline_rounded : Icons.search_off_rounded,
                                size: 42, color: const Color(0xFF9AA9A0)),
                            const SizedBox(height: 10),
                            Text(_search.isNotEmpty ? 'No matching parties found.' : (_showArchived ? 'No archived parties.' : 'No active parties added yet.'),
                                style: TextStyle(color: Color(0xFF748279), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final party = filtered[index];
                          return FutureBuilder<Map<String, dynamic>>(
                            future: PartyService.getPartySummary((party['id'] as num).toInt()),
                            builder: (context, snapshot) {
                              final balances = (snapshot.data?['balances'] as List<dynamic>?) ?? [];
                              final phone = (party['phone'] ?? '').toString().trim();
                              final email = (party['email'] ?? '').toString().trim();
                              final city = (party['city'] ?? '').toString().trim();
                              final country = (party['country'] ?? '').toString().trim();
                              final currency = (party['currency']?.toString() ?? 'PKR').toUpperCase();
                              final partyType = (party['party_type']?.toString() ?? 'Individual');
                              final business = (party['business_name'] ?? '').toString().trim();
                              final photo = party['profile_image_path']?.toString() ?? '';
                              final hasPhoto = photo.isNotEmpty && File(photo).existsSync();
                              final opening = (party['opening_balance'] as num?)?.toDouble() ?? 0;
                              final creditLimit = (party['credit_limit'] as num?)?.toDouble() ?? 0;
                              return Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  borderRadius: BorderRadius.circular(19),
                                  border: Border.all(color: const Color(0xFFE3ECE6)),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0xFF173F30).withValues(alpha: .055),
                                      blurRadius: 14, offset: const Offset(0, 5)),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(19),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(19),
                                    onTap: () => _openLedger(party),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(colors: [Color(0xFF16865D), Color(0xFFB9E2CB)]),
                                                ),
                                                child: CircleAvatar(
                                                  radius: 23,
                                                  backgroundColor: const Color(0xFFEAF5EF),
                                                  backgroundImage: hasPhoto ? FileImage(File(photo)) : null,
                                                  child: hasPhoto ? null : Icon(Icons.person_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
                                                ),
                                              ),
                                              const SizedBox(width: 11),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(party['name']?.toString() ?? '',
                                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF20352B))),
                                                    const SizedBox(height: 4),
                                                    Row(children: [
                                                      Flexible(child: Text(business.isNotEmpty ? business : partyType,
                                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(fontSize: 10, color: Color(0xFF78877E), fontWeight: FontWeight.w500))),
                                                      const SizedBox(width: 6),
                                                      Container(width: 3, height: 3, decoration: BoxDecoration(color: Color(0xFFB4C0B8), shape: BoxShape.circle)),
                                                      const SizedBox(width: 6),
                                                      Text(currency, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                                                    ]),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                padding: EdgeInsets.zero,
                                                onSelected: (value) {
                                                  if (value == 'edit') _editParty(party);
                                                  if (value == 'archive') _togglePartyArchive(party, archive: true);
                                                  if (value == 'restore') _togglePartyArchive(party, archive: false);
                                                  if (value == 'delete') _deleteParty(party);
                                                },
                                                itemBuilder: (_) => [
                                                  const PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                                                  if (_showArchived)
                                                    PopupMenuItem(value: 'restore', child: ListTile(dense: true, leading: Icon(Icons.unarchive_outlined, color: Theme.of(context).colorScheme.primary), title: Text('Restore to Active')))
                                                  else
                                                    const PopupMenuItem(value: 'archive', child: ListTile(dense: true, leading: Icon(Icons.archive_outlined), title: Text('Archive'))),
                                                  PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), title: Text('Delete'))),
                                                ],
                                              ),
                                            ],
                                          ),
                                          if (phone.isNotEmpty || email.isNotEmpty || city.isNotEmpty || country.isNotEmpty) ...[
                                            const SizedBox(height: 11),
                                            Wrap(
                                              spacing: 13, runSpacing: 6,
                                              children: [
                                                if (phone.isNotEmpty) _partyInfo(Icons.phone_outlined, phone),
                                                if (email.isNotEmpty) _partyInfo(Icons.mail_outline_rounded, email),
                                                if (city.isNotEmpty || country.isNotEmpty) _partyInfo(Icons.location_on_outlined, [city, country].where((v) => v.isNotEmpty).join(', ')),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 12),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F8F6),
                                              borderRadius: BorderRadius.circular(13),
                                            ),
                                            child: balances.isEmpty
                                                ? Row(children: const [
                                                    Icon(Icons.receipt_long_outlined, size: 16, color: Color(0xFF87958D)),
                                                    SizedBox(width: 7),
                                                    Text('No loan history yet', style: TextStyle(fontSize: 11, color: Color(0xFF78877E), fontWeight: FontWeight.w600)),
                                                  ])
                                                : Wrap(
                                                    spacing: 7, runSpacing: 7,
                                                    children: balances.map((item) {
                                                      final isReceivable = item['loan_type'] == 'given';
                                                      final amount = (item['outstanding'] as num?) ?? 0;
                                                      final color = isReceivable ? const Color(0xFF168451) : const Color(0xFFB66A35);
                                                      final bg = isReceivable ? const Color(0xFFE6F4EB) : const Color(0xFFFFF0E5);
                                                      final label = isReceivable ? 'Receivable' : 'Payable';
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                                        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
                                                        child: Text(item['currency'].toString() + ' ' + label + '  ' + _money(amount.toDouble()),
                                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
                                                      );
                                                    }).toList(),
                                                  ),
                                          ),
                                          if (opening > 0 || creditLimit > 0) ...[
                                            const SizedBox(height: 9),
                                            Row(children: [
                                              if (opening > 0) Expanded(child: _partyMeta('Opening balance', currency + ' ' + _money(opening))),
                                              if (opening > 0 && creditLimit > 0) const SizedBox(width: 8),
                                              if (creditLimit > 0) Expanded(child: _partyMeta('Credit limit', currency + ' ' + _money(creditLimit))),
                                            ]),
                                          ],
                                          const SizedBox(height: 7),
                                          Row(children: const [
                                            Icon(Icons.menu_book_outlined, size: 13, color: Color(0xFF87958D)),
                                            SizedBox(width: 5),
                                            Text('Tap to view ledger', style: TextStyle(fontSize: 9, color: Color(0xFF87958D), fontWeight: FontWeight.w600)),
                                            Spacer(),
                                            Text('PARTY', style: TextStyle(fontSize: 9, letterSpacing: 1.0, color: Color(0xFFA1AEA6), fontWeight: FontWeight.w800)),
                                            SizedBox(width: 7),
                                          ]),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _partyTabButton(String label, int count, bool selected, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(11),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
          color: selected ? Colors.white : const Color(0xFF65756C))),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: .18) : const Color(0xFFF0F4F1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF65756C))),
        ),
      ]),
    ),
  );

  Widget _partyInfo(IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: const Color(0xFF84938A)),
      const SizedBox(width: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: Color(0xFF6F7E75))),
      ),
    ],
  );

  Widget _partyMeta(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFFAFBFA),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 9, color: Color(0xFF87958D))),
      const SizedBox(height: 2),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: Color(0xFF42564B), fontWeight: FontWeight.w800)),
    ]),
  );

}
