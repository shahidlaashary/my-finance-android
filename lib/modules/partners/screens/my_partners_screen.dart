import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/modules/partners/services/my_partners_service.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';

class MyPartnersScreen extends StatefulWidget {
  const MyPartnersScreen({super.key});
  @override
  State<MyPartnersScreen> createState() => _MyPartnersScreenState();
}

class _MyPartnersScreenState extends State<MyPartnersScreen> {
  final _service = MyPartnersService.instance;
  List<Map<String, dynamic>> _partners = [];
  bool _loading = true;
  bool _searchVisible = false;
  String _search = '';
  String _filter = 'All';

  @override
  void initState() { super.initState(); AppRefreshController.revision.addListener(_onAppDataChanged); _load(); }
  void _onAppDataChanged() { if (mounted) _load(); }
  @override
  void dispose() { AppRefreshController.revision.removeListener(_onAppDataChanged); super.dispose(); }

  Future<void> _load() async {
    try {
      final rows = await _service.getPartners();
      if (!mounted) return;
      setState(() { _partners = rows; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Unable to load partners: ' + e.toString());
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _money(dynamic value) => 'PKR ' + ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);

  Future<T?> _sheet<T>({
    required String title,
    required String saveLabel,
    required Widget Function(BuildContext, StateSetter) body,
    required VoidCallback onSave,
  }) => showModalBottomSheet<T>(
    context: context, isScrollControlled: true, useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sc) => StatefulBuilder(builder: (context, setS) {
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final height = MediaQuery.sizeOf(context).height;
      final maxHeight = keyboard > 0 ? (height - keyboard).clamp(180.0, height) * .96 : height * .82;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(top: false, child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
            child: Column(children: [
              const SizedBox(height: 10),
              Container(width: 38, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(8))),
              Padding(padding: const EdgeInsets.fromLTRB(18, 10, 10, 8), child: Row(children: [
                Expanded(child: Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => Navigator.pop(sc), icon: Icon(Icons.close_rounded)),
              ])),
              Expanded(child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                child: body(context, setS),
              )),
              Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 14), child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sc), child: Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: onSave, child: Text(saveLabel))),
              ])),
            ]),
          ),
        )),
      );
    }),
  );

  Future<void> _editPartner([Map<String, dynamic>? partner]) async {
    final name = TextEditingController(text: partner?['name']?.toString() ?? '');
    final phone = TextEditingController(text: partner?['phone']?.toString() ?? '');
    final notes = TextEditingController(text: partner?['notes']?.toString() ?? '');
    final opening = TextEditingController(text: partner?['opening_balance']?.toString() ?? '0');
    final share = TextEditingController(text: partner?['profit_share']?.toString() ?? '50');
    final key = GlobalKey<FormState>();
    String type = partner?['type']?.toString() ?? 'Business';
    final saved = await _sheet<bool>(
      title: partner == null ? 'Add Partner' : 'Edit Partner',
      saveLabel: 'Save Partner',
      onSave: () { if (key.currentState?.validate() == true) Navigator.pop(context, true); },
      body: (context, setS) => Form(key: key, child: Column(children: [
        DropdownButtonFormField<String>(
          value: type, decoration: const InputDecoration(labelText: 'Partner Type'),
          items: const [DropdownMenuItem(value: 'Business', child: Text('Business Partner')), DropdownMenuItem(value: 'Personal', child: Text('Personal Partner'))],
          onChanged: (v) => setS(() => type = v ?? type),
        ),
        TextFormField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Partner Name *'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter partner name.' : null),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number (optional)')),
        if (type == 'Business') TextFormField(controller: share, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Profit Share (%)'), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n < 0 || n > 100 ? 'Enter 0–100%.' : null; }),
        TextFormField(controller: opening, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Opening Balance')),
        TextFormField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes / Memo')),
      ])),
    );
    if (saved == true) {
      try {
        await _service.savePartner(id: partner?['id'] as int?, name: name.text, type: type, phone: phone.text, notes: notes.text, profitShare: double.tryParse(share.text) ?? 50, openingBalance: double.tryParse(opening.text) ?? 0);
        await SoundSettingsService.instance.play(partner == null ? 'save' : 'update');
        await _load();
      } catch (e) { _message(e.toString()); }
    }
    name.dispose(); phone.dispose(); notes.dispose(); opening.dispose(); share.dispose();
  }

  Future<void> _open(Map<String, dynamic> partner) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PartnerDetailScreen(partnerId: partner['id'] as int)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final visible = _partners.where((p) {
      final matchesType = _filter == 'All' || p['type'] == _filter;
      final searchable = [
        p['name'], p['phone'], p['notes'], p['type'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return matchesType && (query.isEmpty || searchable.contains(query));
    }).toList();
    final businesses = _partners.where((p) => p['type'] == 'Business').length;
    final personals = _partners.where((p) => p['type'] == 'Personal').length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Partners', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: _searchVisible ? 'Close search' : 'Search partners',
            onPressed: () => setState(() {
              _searchVisible = !_searchVisible;
              if (!_searchVisible) _search = '';
            }),
            icon: Icon(_searchVisible ? Icons.close_rounded : Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Add Partner',
            onPressed: () => _editPartner(),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(
        children: [
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  hintText: 'Search name, phone or notes',
                  prefixIcon: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.primary),
                  suffixIcon: _search.isEmpty ? null : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(() => _search = ''),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .45))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.3)),
                ),
              ),
            ),
          Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
          Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: .78)]), borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Partner Overview', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .78), fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_partners.length.toString() + ' Partners', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _overview('Business', businesses, Icons.business_center_outlined)),
              Expanded(child: _overview('Personal', personals, Icons.people_alt_outlined)),
            ]),
          ])),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: ['All', 'Business', 'Personal'].map((v) => ChoiceChip(label: Text(v), selected: _filter == v, onSelected: (_) => setState(() => _filter = v))).toList()),
          const SizedBox(height: 8),
          if (visible.isEmpty) Padding(padding: EdgeInsets.only(top: 55), child: Column(children: [
            Icon(Icons.handshake_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            SizedBox(height: 12),
            Text('No partners added yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            SizedBox(height: 5),
            Text('Add a business or personal partner to get started.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ])) else ...visible.map((p) => Card(
            color: Theme.of(context).colorScheme.surface, margin: const EdgeInsets.only(bottom: 9),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .11), child: Icon(p['type'] == 'Business' ? Icons.business_center_outlined : Icons.person_outline, color: Theme.of(context).colorScheme.primary)),
              title: Text(p['name'].toString(), style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(p['type'].toString() + ' Partner • ' + p['transaction_count'].toString() + ' transactions'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_money(p['current_balance']), style: TextStyle(fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_right_rounded, size: 18),
              ]),
              onTap: () => _open(p),
              onLongPress: () => _editPartner(p),
            ),
          )),
        ]),
      )),
        ],
      ),
    );
  }

  Widget _overview(String label, int value, IconData icon) => Row(children: [
    Icon(icon, color: Theme.of(context).colorScheme.surface, size: 20), const SizedBox(width: 7),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value.toString(), style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 18)),
      Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .78), fontSize: 11)),
    ]),
  ]);
}

class PartnerDetailScreen extends StatefulWidget {
  final int partnerId;
  const PartnerDetailScreen({super.key, required this.partnerId});
  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> {
  final _service = MyPartnersService.instance;
  Map<String, dynamic>? _partner;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _linked = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); AppRefreshController.revision.addListener(_onAppDataChanged); _load(); }
  void _onAppDataChanged() { if (mounted) _load(); }
  @override
  void dispose() { AppRefreshController.revision.removeListener(_onAppDataChanged); super.dispose(); }

  Future<void> _load() async {
    try {
      final partners = await _service.getPartners();
      final p = partners.firstWhere((v) => v['id'] == widget.partnerId);
      final tx = await _service.getTransactions(widget.partnerId);
      final wallets = await WalletService.getWallets();
      final linked = await _service.getWalletLinks(widget.partnerId);
      if (!mounted) return;
      setState(() { _partner = p; _transactions = tx; _wallets = wallets; _linked = linked; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load partner: ' + e.toString())));
    }
  }

  String _money(dynamic value, [String currency = 'PKR']) => currency + ' ' + ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);

  Future<T?> _sheet<T>({required String title, required String save, required Widget Function(BuildContext, StateSetter) body, required VoidCallback onSave}) =>
    showModalBottomSheet<T>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent, builder: (sc) => StatefulBuilder(builder: (context, setS) {
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final h = MediaQuery.sizeOf(context).height;
      return AnimatedPadding(duration: const Duration(milliseconds: 220), padding: EdgeInsets.only(bottom: keyboard), child: SafeArea(top: false, child: ConstrainedBox(constraints: BoxConstraints(maxHeight: keyboard > 0 ? (h-keyboard).clamp(180.0,h)*.96 : h*.82), child: Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(25))), child: Column(children: [
        const SizedBox(height: 10), Container(width: 38,height: 4,decoration: BoxDecoration(color: Theme.of(context).dividerColor,borderRadius: BorderRadius.circular(8))),
        Padding(padding: const EdgeInsets.fromLTRB(18,10,10,8), child: Row(children: [Expanded(child: Text(title,style: TextStyle(fontSize:19,fontWeight:FontWeight.w800))),IconButton(onPressed:()=>Navigator.pop(sc),icon:Icon(Icons.close_rounded))])),
        Expanded(child: SingleChildScrollView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,padding: const EdgeInsets.fromLTRB(18,4,18,18),child: body(context,setS))),
        Padding(padding: const EdgeInsets.fromLTRB(18,8,18,14),child: Row(children: [Expanded(child: OutlinedButton(onPressed:()=>Navigator.pop(sc),child:Text('Cancel'))),const SizedBox(width:10),Expanded(child:FilledButton(onPressed:onSave,child:Text(save)))])),
      ])))));
    }));

  Future<void> _manageWallets() async {
    final selected = _linked.map((w) => w['id'] as int).toSet();
    final result = await _sheet<bool>(title: 'Link Wallets', save: 'Save Wallet Links', onSave: () => Navigator.pop(context, true), body: (context, setS) => Column(children: [
      Align(alignment: Alignment.centerLeft, child: Text('Select wallets used for this partner.', style: TextStyle(color: Theme.of(context).hintColor))),
      const SizedBox(height: 8),
      ..._wallets.map((w) => CheckboxListTile(contentPadding: EdgeInsets.zero, value: selected.contains(w['id']), title: Text(w['name'].toString()), subtitle: Text(w['currency'].toString()), onChanged: (v) => setS(() { if (v == true) { selected.add(w['id'] as int); } else { selected.remove(w['id']); } }))),
      if (_wallets.isEmpty) Text('Create a wallet first.'),
    ]));
    if (result == true) { await _service.setWalletLinks(widget.partnerId, selected.toList()); await _load(); }
  }

  Future<void> _transfer() async {
    if (_linked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link at least one wallet to this partner first.')));
      return;
    }
    final amount = TextEditingController();
    final note = TextEditingController();
    int? walletId = _linked.first['id'] as int;
    bool walletToPartner = true;
    DateTime date = DateTime.now();
    final result = await _sheet<bool>(
      title: 'Transfer with Partner',
      save: 'Confirm Transfer',
      onSave: () {
        final value = double.tryParse(amount.text);
        if (value == null || !value.isFinite || value <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
          return;
        }
        Navigator.pop(context, true);
      },
      body: (context, setS) => Column(children: [
        DropdownButtonFormField<bool>(
          value: walletToPartner,
          decoration: const InputDecoration(labelText: 'Transfer Direction'),
          items: const [
            DropdownMenuItem(value: true, child: Text('Existing Wallet → Partner')),
            DropdownMenuItem(value: false, child: Text('Partner → Existing Wallet')),
          ],
          onChanged: (v) => setS(() => walletToPartner = v ?? walletToPartner),
        ),
        TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount *')),
        DropdownButtonFormField<int>(
          value: walletId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Linked Wallet'),
          items: _linked.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text(w['name'].toString() + ' (' + w['currency'].toString() + ')'))).toList(),
          onChanged: (v) => setS(() => walletId = v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Transfer Date'),
          subtitle: Text(date.toIso8601String().split('T').first),
          trailing: Icon(Icons.calendar_month),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (d != null) setS(() => date = d);
          },
        ),
        TextFormField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes / Memo')),
      ]),
    );
    if (result == true && walletId != null) {
      try {
        await _service.transferWithPartner(
          partnerId: widget.partnerId,
          walletId: walletId!,
          amount: double.parse(amount.text),
          walletToPartner: walletToPartner,
          note: note.text,
          date: date,
        );
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partner transfer saved successfully.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    amount.dispose();
    note.dispose();
  }

  Future<void> _addTransaction() async {
    if (_wallets.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a wallet first.'))); return; }
    final amount = TextEditingController();
    final note = TextEditingController();
    final category = TextEditingController();
    String type = 'Money Given';
    int? walletId = _linked.isNotEmpty ? _linked.first['id'] as int : _wallets.first['id'] as int;
    DateTime date = DateTime.now();
    const types = ['Money Given','Money Received','Partner Contribution','Shared Expense','Partner Withdrawal','Profit Received','Profit Paid'];
    final result = await _sheet<bool>(title: 'Add Partner Transaction', save: 'Save Transaction', onSave: () {
      final n = double.tryParse(amount.text);
      if (n == null || !n.isFinite || n <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.'))); return; }
      Navigator.pop(context, true);
    }, body: (context, setS) => Column(children: [
      DropdownButtonFormField<String>(value: type, decoration: const InputDecoration(labelText: 'Transaction Type'), items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (v) => setS(() => type = v ?? type)),
      TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount *')),
      DropdownButtonFormField<int>(value: walletId, isExpanded: true, decoration: const InputDecoration(labelText: 'Wallet'), items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text(w['name'].toString() + ' (' + w['currency'].toString() + ')'))).toList(), onChanged: (v) => setS(() => walletId = v)),
      TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
      ListTile(contentPadding: EdgeInsets.zero, title: Text('Transaction Date'), subtitle: Text(date.toIso8601String().split('T').first), trailing: Icon(Icons.calendar_month), onTap: () async { final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setS(() => date = d); }),
      TextFormField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes / Memo')),
    ]));
    if (result == true) {
      try { await _service.addTransaction(partnerId: widget.partnerId, type: type, amount: double.parse(amount.text), walletId: walletId, category: category.text, note: note.text, date: date); await SoundSettingsService.instance.play(type.toLowerCase() == 'income' ? 'income' : 'expense'); await _load(); }
      catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    }
    amount.dispose(); note.dispose(); category.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _partner;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(p?['name']?.toString() ?? 'Partner Details', style: TextStyle(fontWeight: FontWeight.w800)), actions: [
        PopupMenuButton<String>(onSelected: (v) async {
          if (v == 'active') { await _service.setActive(widget.partnerId, (p?['is_active'] as int? ?? 1) == 0); await _load(); }
          if (v == 'delete') {
            final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Move partner to Recycle Bin?'),
              content: const Text('Partner profile, wallet links and transaction history will be archived. Linked wallet balances will be reversed.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))],
            ));
            if (confirmed == true) {
              try { await SoundSettingsService.instance.play('delete_warning'); await _service.deletePartner(widget.partnerId); await SoundSettingsService.instance.play('delete_success'); if (mounted) Navigator.pop(context); }
              catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete partner: $e'))); }
            }
          }
        }, itemBuilder: (_) => [
          PopupMenuItem(value: 'active', child: Text((p?['is_active'] as int? ?? 1) == 1 ? 'Deactivate Partner' : 'Activate Partner')),
          const PopupMenuItem(value: 'delete', child: Text('Move to Recycle Bin')),
        ]),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addTransaction, backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary, icon: Icon(Icons.add), label: Text('Add Transaction')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : p == null ? const Center(child: Text('Partner not found')) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16,12,16,16), children: [
        Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(17)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p['type'].toString() + ' Partner', style: TextStyle(color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(_money(p['current_balance']), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
          Text('Net partner balance', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11)),
          if ((p['phone'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p['phone'].toString())),
          if (p['type'] == 'Business') Padding(padding: const EdgeInsets.only(top: 6), child: Text('Profit share: ' + p['profit_share'].toString() + '%')),
        ])),
        const SizedBox(height: 12),
        Card(color: Theme.of(context).colorScheme.surface, child: ListTile(leading: Icon(Icons.account_balance_wallet_outlined, color: Theme.of(context).colorScheme.primary), title: Text('Linked Wallets', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(_linked.isEmpty ? 'No wallets linked' : _linked.length.toString() + ' wallet(s) linked'), trailing: Icon(Icons.chevron_right_rounded), onTap: _manageWallets)),
        Card(color: Theme.of(context).colorScheme.surface, child: ListTile(
          leading: Icon(Icons.swap_horiz_rounded, color: Theme.of(context).colorScheme.primary),
          title: Text('Transfer Between Wallet & Partner', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Move money in either direction'),
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: _transfer,
        )),
        Padding(padding: EdgeInsets.fromLTRB(4,16,4,8), child: Text('Transaction History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        if (_transactions.isEmpty) Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No transactions yet', style: TextStyle(color: Theme.of(context).hintColor)))),
        ..._transactions.map((t) {
          // History direction is CASH movement, not partner receivable balance.
          // A received payment reduces the partner's outstanding ledger (negative
          // balance_delta) but must still be shown as money IN (+) in history.
          const cashInTypes = {
            'Money Given',
            'Partner Contribution',
            'Profit Received',
            'Wallet Transfer Out',
          };
          const cashOutTypes = {
            'Money Received',
            'Shared Expense',
            'Partner Withdrawal',
            'Profit Paid',
            'Wallet Transfer In',
          };
          final transactionType = t['type']?.toString() ?? '';
          final incoming = cashInTypes.contains(transactionType)
              ? true
              : cashOutTypes.contains(transactionType)
                  ? false
                  : ((t['balance_delta'] as num?)?.toDouble() ?? 0) < 0;
          final currency = t['currency']?.toString() ?? 'PKR';
          return Card(color: Theme.of(context).colorScheme.surface, margin: const EdgeInsets.only(bottom: 8), child: ListTile(
            leading: CircleAvatar(backgroundColor: (incoming ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.error).withValues(alpha: .12), child: Icon(incoming ? Icons.south_west_rounded : Icons.north_east_rounded, color: incoming ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.error)),
            title: Text(t['type'].toString(), style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text((t['wallet_name'] ?? 'No wallet').toString() + ' • ' + (t['date'] ?? '').toString().split('T').first),
            trailing: Text((incoming ? '+' : '−') + _money(t['amount'], currency), style: TextStyle(fontWeight: FontWeight.w800, color: incoming ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.error)),
          ));
        }),
      ])),
    );
  }
}
