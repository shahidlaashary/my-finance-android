import 'package:flutter/material.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/modules/vehicles/services/vehicle_service.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/modules/vehicles/services/vehicle_export_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  bool _hideBalances = false;
  bool _saving = false;
  String _reportRange = 'All Time';
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _fuel = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _reminders = [];
  List<Map<String, dynamic>> _wallets = [];

  Color get _green => Theme.of(context).colorScheme.primary;
  Color get _ink => Theme.of(context).colorScheme.onSurface;
  Color get _muted => Theme.of(context).hintColor;
  static const _expenseCategories = [
    'Oil Change', 'Mechanical Repair', 'Tyres & Puncture', 'Battery',
    'Car Wash', 'Service & Tuning', 'AC Maintenance', 'Spare Parts',
    'Registration / Token Tax', 'Insurance', 'Parking / Toll Tax', 'Other',
  ];
  static const _vehicleTypes = ['Car', 'Bike', 'Van', 'Truck', 'Other'];
  static const _fuelTypes = ['Petrol', 'Diesel', 'CNG', 'Hybrid', 'Electric'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this)..addListener(_tabChanged);
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _load();
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (mounted) setState(() {});
  }

  void _onAppDataChanged() { if (mounted) _load(); }

  void _onPreferencesChanged() async {
    final hidden = await GeneralPreferences.instance.hideBalances;
    if (mounted && hidden != _hideBalances) {
      setState(() => _hideBalances = hidden);
    }
  }

  Future<void> _load() async {
    try {
      final hideBalances = await GeneralPreferences.instance.hideBalances;
      final values = await Future.wait([
        VehicleService.getVehicles(), VehicleService.getFuelLogs(),
        VehicleService.getExpenses(), VehicleService.getReminders(),
        VehicleService.getWallets(),
      ]);
      if (!mounted) return;
      setState(() {
        _hideBalances = hideBalances;
        _vehicles = values[0] as List<Map<String, dynamic>>;
        _fuel = values[1] as List<Map<String, dynamic>>;
        _expenses = values[2] as List<Map<String, dynamic>>;
        _reminders = values[3] as List<Map<String, dynamic>>;
        _wallets = values[4] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Unable to load vehicle data: $e');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _vehicleName(dynamic id) {
    for (final v in _vehicles) {
      if (v['id'] == id) return (v['name'] ?? 'Vehicle').toString();
    }
    return 'Vehicle';
  }

  String _walletCurrency(dynamic id) {
    for (final w in _wallets) { if (w['id'] == id) return (w['currency'] ?? 'PKR').toString(); }
    return 'PKR';
  }

  String _mileageUnit(int vehicleId) {
    final v = _vehicles.where((e) => e['id'] == vehicleId).toList();
    return v.isNotEmpty && v.first['fuel_type'] == 'Electric' ? 'km/kWh' : 'km/L';
  }

  String _vehicleCost(int vehicleId, {required bool fuelOnly}) {
    final totals = <String, double>{};
    final rows = fuelOnly ? _fuel.where((e) => e['vehicle_id'] == vehicleId) : _expenses.where((e) => e['vehicle_id'] == vehicleId);
    for (final r in rows) {
      final currency = _walletCurrency(r['wallet_id']);
      final amount = ((r[fuelOnly ? 'total' : 'amount'] as num?)?.toDouble() ?? 0);
      totals[currency] = (totals[currency] ?? 0) + amount;
    }
    if (totals.isEmpty) return '0.00';
    return totals.entries.map((e) => '${e.key} ${_moneyAmount(e.value)}').join(' • ');
  }

  String _costPerKm(int vehicleId) {
    final distance = _distanceFor(vehicleId);
    if (distance <= 0) return '—';
    final totals = <String, double>{};
    for (final r in _fuel.where((e) => e['vehicle_id'] == vehicleId)) {
      final currency = _walletCurrency(r['wallet_id']);
      totals[currency] = (totals[currency] ?? 0) + ((r['total'] as num?)?.toDouble() ?? 0);
    }
    for (final r in _expenses.where((e) => e['vehicle_id'] == vehicleId)) {
      final currency = _walletCurrency(r['wallet_id']);
      totals[currency] = (totals[currency] ?? 0) + ((r['amount'] as num?)?.toDouble() ?? 0);
    }
    if (totals.isEmpty) return '—';
    return totals.entries.map((e) => '${e.key} ${_moneyAmount(e.value / distance)}/km').join(' • ');
  }

  String _monthlySpend() {
    final now = DateTime.now();
    final totals = <String, double>{};
    for (final r in _fuel) {
      final d = DateTime.tryParse(r['date']?.toString() ?? '');
      if (d != null && d.year == now.year && d.month == now.month) {
        final currency = _walletCurrency(r['wallet_id']);
        totals[currency] = (totals[currency] ?? 0) + ((r['total'] as num?)?.toDouble() ?? 0);
      }
    }
    for (final r in _expenses) {
      final d = DateTime.tryParse(r['date']?.toString() ?? '');
      if (d != null && d.year == now.year && d.month == now.month) {
        final currency = _walletCurrency(r['wallet_id']);
        totals[currency] = (totals[currency] ?? 0) + ((r['amount'] as num?)?.toDouble() ?? 0);
      }
    }
    if (totals.isEmpty) return '0.00';
    return totals.entries.map((e) => '${e.key} ${_moneyAmount(e.value)}').join(' • ');
  }

  String _walletName(dynamic id) {
    for (final w in _wallets) {
      if (w['id'] == id) return '${w['name']} (${w['currency']})';
    }
    return 'Wallet';
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? '—' : DateFormat('dd MMM yyyy').format(parsed);
  }

  String _amount(dynamic value) => NumberFormat('#,##0.00').format((value as num?)?.toDouble() ?? 0);

  String _moneyAmount(dynamic value) => _hideBalances ? '••••••' : _amount(value);

  String _moneyByCurrency(List<Map<String, dynamic>> records, String amountKey) {
    final totals = <String, double>{};
    for (final r in records) {
      final wallet = _wallets.where((w) => w['id'] == r['wallet_id']).toList();
      final currency = wallet.isEmpty ? 'PKR' : (wallet.first['currency'] ?? 'PKR').toString();
      totals[currency] = (totals[currency] ?? 0) + ((r[amountKey] as num?)?.toDouble() ?? 0);
    }
    if (totals.isEmpty) return '0.00';
    return totals.entries.map((e) => '${e.key} ${_moneyAmount(e.value)}').join('  •  ');
  }

  double _distanceFor(int vehicleId) {
    final rows = _fuel.where((e) => e['vehicle_id'] == vehicleId).toList()
      ..sort((a,b) {
        final byDate = (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString());
        return byDate != 0 ? byDate : ((a['id'] as num?)?.toInt() ?? 0).compareTo((b['id'] as num?)?.toInt() ?? 0);
      });
    if (rows.length < 2) return 0;
    final first = (rows.first['odometer'] as num?)?.toDouble() ?? 0;
    final last = (rows.last['odometer'] as num?)?.toDouble() ?? 0;
    return last >= first ? last - first : 0;
  }

  double? _averageMileage(int vehicleId) {
    final all = _fuel.where((e) => e['vehicle_id'] == vehicleId).toList()
      ..sort((a,b) {
        final byDate = (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString());
        return byDate != 0 ? byDate : ((a['id'] as num?)?.toInt() ?? 0).compareTo((b['id'] as num?)?.toInt() ?? 0);
      });
    final fullTanks = all.where((e) => e['full_tank'] == true).toList();
    if (fullTanks.length < 2) return null;
    double? result;
    for (var i = 1; i < fullTanks.length; i++) {
      final previousId = (fullTanks[i - 1]['id'] as num).toInt();
      final currentId = (fullTanks[i]['id'] as num).toInt();
      final start = (fullTanks[i - 1]['odometer'] as num?)?.toDouble() ?? 0;
      final end = (fullTanks[i]['odometer'] as num?)?.toDouble() ?? 0;
      final consumed = all.where((f) {
        final id = (f['id'] as num).toInt();
        return id > previousId && id <= currentId;
      }).fold<double>(0, (sum, f) => sum + ((f['quantity'] as num?)?.toDouble() ?? 0));
      if (end > start && consumed > 0) result = (end - start) / consumed;
    }
    return result;
  }

  double _latestOdometer(int vehicleId) {
    final rows = <Map<String, dynamic>>[
      ..._fuel.where((e) => e['vehicle_id'] == vehicleId),
      ..._expenses.where((e) => e['vehicle_id'] == vehicleId),
    ];
    if (rows.isEmpty) return 0;
    return rows.fold<double>(0, (maxValue, row) {
      final reading = (row['odometer'] as num?)?.toDouble() ?? 0;
      return reading > maxValue ? reading : maxValue;
    });
  }

  List<Map<String, dynamic>> _dueReminders() {
    final now = DateTime.now();
    return _reminders.where((r) {
      final due = DateTime.tryParse(r['due_date']?.toString() ?? '');
      final dateDue = due != null && !due.isAfter(DateTime(now.year, now.month, now.day));
      final odo = (r['due_odometer'] as num?)?.toDouble();
      final odoDue = odo != null && odo > 0 && _latestOdometer((r['vehicle_id'] as num).toInt()) >= odo;
      return dateDue || odoDue;
    }).toList();
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, size: 19),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _green, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13), isDense: true,
  );

  Widget _sheetFrame(BuildContext context, Widget child) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height;
    final maxHeight = keyboard > 0 ? (height - keyboard).clamp(0.0, height) * .95 : height * .82;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220), curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(top: false, child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: child,
        ),
      )),
    );
  }

  Widget _sheetHeader(String title, BuildContext context) => Column(children: [
    Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(10)))),
    SizedBox(height: 12),
    Row(children: [
      Expanded(child: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink))),
      IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded), color: Theme.of(context).hintColor),
    ]),
    SizedBox(height: 8),
  ]);

  Future<void> _showVehicleForm({Map<String, dynamic>? vehicle}) async {
    final key = GlobalKey<FormState>();
    final name = TextEditingController(text: vehicle?['name']?.toString() ?? '');
    final model = TextEditingController(text: vehicle?['model']?.toString() ?? '');
    final registration = TextEditingController(text: vehicle?['registration']?.toString() ?? '');
    final price = TextEditingController(text: vehicle?['purchase_price']?.toString() ?? '');
    final notes = TextEditingController(text: vehicle?['notes']?.toString() ?? '');
    var type = (vehicle?['type'] ?? 'Car').toString();
    var fuelType = (vehicle?['fuel_type'] ?? 'Petrol').toString();
    var purchaseDate = DateTime.tryParse(vehicle?['purchase_date']?.toString() ?? '') ?? DateTime.now();
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent, elevation: 0,
      builder: (sheet) => StatefulBuilder(builder: (context, setSheet) => _sheetFrame(context,
        Form(key: key, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHeader(vehicle == null ? 'Add Vehicle' : 'Edit Vehicle', sheet),
            TextFormField(controller: name, decoration: _decoration('Vehicle Name', Icons.directions_car_outlined), validator: (v) => v == null || v.trim().isEmpty ? 'Enter vehicle name' : null),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(value: type, isExpanded: true, decoration: _decoration('Vehicle Type', Icons.category_outlined), items: _vehicleTypes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setSheet(() => type = v); })),
              SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(value: fuelType, isExpanded: true, decoration: _decoration('Fuel Type', Icons.local_gas_station_outlined), items: _fuelTypes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setSheet(() => fuelType = v); })),
            ]),
            SizedBox(height: 12),
            TextFormField(controller: model, decoration: _decoration('Company / Model', Icons.directions_car_filled_outlined)),
            SizedBox(height: 12),
            TextFormField(controller: registration, textCapitalization: TextCapitalization.characters, decoration: _decoration('Registration Number', Icons.confirmation_number_outlined)),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Purchase Price (optional)', Icons.payments_outlined), validator: (v) { if ((v ?? '').trim().isEmpty) return null; final n = double.tryParse(v!); return n == null || !n.isFinite || n < 0 ? 'Enter a valid price' : null; })),
              SizedBox(width: 10),
              Expanded(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () async { final d = await showDatePicker(context: context, initialDate: purchaseDate, firstDate: DateTime(1950), lastDate: DateTime(2100)); if (d != null) setSheet(() => purchaseDate = d); }, child: InputDecorator(decoration: _decoration('Purchase Date', Icons.calendar_month_outlined), child: Text(DateFormat('dd MMM yyyy').format(purchaseDate), style: TextStyle(fontSize: 13))))),
            ]),
            SizedBox(height: 12),
            TextFormField(controller: notes, maxLines: 2, decoration: _decoration('Notes', Icons.notes_rounded)),
            SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: Text(appText(context, "Cancel", "Cancel")))),
              SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(onPressed: _saving ? null : () async {
                if (!key.currentState!.validate()) return;
                setSheet(() => _saving = true);
                try {
                  await VehicleService.saveVehicle({
                    'id': vehicle?['id'], 'name': name.text.trim(), 'type': type,
                    'fuel_type': fuelType, 'model': model.text.trim(),
                    'registration': registration.text.trim(),
                    'purchase_price': double.tryParse(price.text) ?? 0,
                    'purchase_date': purchaseDate.toIso8601String(), 'notes': notes.text.trim(),
                  });
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet); await _load();
                  _message(vehicle == null ? 'Vehicle added.' : 'Vehicle updated.');
                } catch (e) { _message('Unable to save vehicle: $e'); }
                finally { if (mounted) setState(() => _saving = false); }
              }, icon: Icon(Icons.check_rounded), label: Text(vehicle == null ? 'Save Vehicle' : 'Update Vehicle'), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Theme.of(context).colorScheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 13)))),
            ]),
          ]),
        )),
      )),
    );
    name.dispose(); model.dispose(); registration.dispose(); price.dispose(); notes.dispose();
  }

  Future<void> _showFuelForm({Map<String, dynamic>? record}) async {
    if (_vehicles.isEmpty || _wallets.isEmpty) { _message(_vehicles.isEmpty ? 'Please add a vehicle first.' : 'Please add a wallet first.'); return; }
    final key = GlobalKey<FormState>();
    final odo = TextEditingController(text: record?['odometer']?.toString() ?? '');
    final quantity = TextEditingController(text: record?['quantity']?.toString() ?? '');
    final unitPrice = TextEditingController(text: record?['unit_price']?.toString() ?? '');
    final station = TextEditingController(text: record?['station']?.toString() ?? '');
    final notes = TextEditingController(text: record?['notes']?.toString() ?? '');
    var vehicleId = (record?['vehicle_id'] as int?) ?? (_vehicles.first['id'] as int);
    var walletId = (record?['wallet_id'] as int?) ?? (_wallets.first['id'] as int);
    var date = DateTime.tryParse(record?['date']?.toString() ?? '') ?? DateTime.now();
    var fullTank = (record?['full_tank'] as bool?) ?? true;
    String unit = (record?['unit'] ?? (_vehicles.firstWhere((v) => v['id'] == vehicleId)['fuel_type'] == 'Electric' ? 'kWh' : 'L')).toString();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent, elevation: 0,
      builder: (sheet) => StatefulBuilder(builder: (context, setSheet) => _sheetFrame(context,
        Form(key: key, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHeader(record == null ? 'Add Fuel Entry' : 'Edit Fuel Entry', sheet),
            DropdownButtonFormField<int>(value: vehicleId, isExpanded: true, decoration: _decoration('Vehicle', Icons.directions_car_outlined),
              items: _vehicles.map((v) => DropdownMenuItem(value: v['id'] as int, child: Text(v['name'].toString()))).toList(),
              onChanged: (v) { if (v != null) setSheet(() { vehicleId = v; final selected = _vehicles.firstWhere((e) => e['id'] == v); unit = selected['fuel_type'] == 'Electric' ? 'kWh' : 'L'; }); }),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: odo, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Odometer (KM)', Icons.speed_rounded), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 ? 'Enter KM reading' : null; })),
              SizedBox(width: 10),
              Expanded(child: InkWell(onTap: () async { final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setSheet(() => date = d); }, child: InputDecorator(decoration: _decoration('Date', Icons.calendar_month), child: Text(DateFormat('dd MMM yyyy').format(date), style: TextStyle(fontSize: 13))))),
            ]),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Quantity ($unit)', Icons.local_gas_station), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter quantity' : null; }, onChanged: (_) => setSheet(() {}))),
              SizedBox(width: 10),
              Expanded(child: TextFormField(controller: unitPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Price per $unit (${_walletCurrency(walletId)})', Icons.price_change_outlined), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter price' : null; }, onChanged: (_) => setSheet(() {}))),
            ]),
            SizedBox(height: 8),
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Text('Total Fuel Cost: ${_amount((double.tryParse(quantity.text) ?? 0) * (double.tryParse(unitPrice.text) ?? 0))}', style: TextStyle(color: _green, fontWeight: FontWeight.w800))),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: fullTank, onChanged: (v) => setSheet(() => fullTank = v ?? false), title: Text(unit == 'kWh' ? 'Full charge' : 'Full tank fill-up'), controlAffinity: ListTileControlAffinity.leading, dense: true),
            TextFormField(controller: station, decoration: _decoration('Fuel Station (optional)', Icons.storefront_outlined)),
            SizedBox(height: 12),
            DropdownButtonFormField<int>(value: walletId, isExpanded: true, decoration: _decoration('Pay from Wallet', Icons.account_balance_wallet_outlined),
              items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text('${w['name']} • ${w['currency']}'))).toList(),
              onChanged: (v) { if (v != null) setSheet(() => walletId = v); }),
            SizedBox(height: 12),
            TextFormField(controller: notes, maxLines: 2, decoration: _decoration('Notes / Memo', Icons.notes_rounded)),
            SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: Text(appText(context, "Cancel", "Cancel")))),
              SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(onPressed: _saving ? null : () async {
                if (!key.currentState!.validate()) return;
                setSheet(() => _saving = true);
                try {
                  final v = _vehicles.firstWhere((e) => e['id'] == vehicleId);
                  if (record == null) {
                    await VehicleService.addFuel(vehicleId: vehicleId, vehicleName: v['name'].toString(), date: date,
                      odometer: double.parse(odo.text), quantity: double.parse(quantity.text), unitPrice: double.parse(unitPrice.text),
                      fullTank: fullTank, walletId: walletId, station: station.text.trim(), notes: notes.text.trim(), unit: unit);
                  } else {
                    await VehicleService.updateFuel(id: record['id'] as int, vehicleId: vehicleId, vehicleName: v['name'].toString(), date: date,
                      odometer: double.parse(odo.text), quantity: double.parse(quantity.text), unitPrice: double.parse(unitPrice.text),
                      fullTank: fullTank, walletId: walletId, station: station.text.trim(), notes: notes.text.trim(), unit: unit);
                  }
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet); await _load(); _message(record == null ? 'Fuel entry saved and linked to Finance expenses.' : 'Fuel entry updated.');
                } catch (e) { _message('Unable to save fuel entry: $e'); }
                finally { if (mounted) setState(() => _saving = false); }
              }, icon: Icon(Icons.check_rounded), label: Text(record == null ? 'Save Fuel Entry' : 'Update Fuel Entry'), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Theme.of(context).colorScheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 13)))),
            ]),
          ]),
        )),
      )),
    );
    odo.dispose(); quantity.dispose(); unitPrice.dispose(); station.dispose(); notes.dispose();
  }

  Future<void> _showExpenseForm({Map<String, dynamic>? record}) async {
    if (_vehicles.isEmpty || _wallets.isEmpty) { _message(_vehicles.isEmpty ? 'Please add a vehicle first.' : 'Please add a wallet first.'); return; }
    final key = GlobalKey<FormState>();
    final amount = TextEditingController(text: record?['amount']?.toString() ?? '');
    final odo = TextEditingController(text: record?['odometer']?.toString() ?? '');
    final vendor = TextEditingController(text: record?['vendor']?.toString() ?? '');
    final notes = TextEditingController(text: record?['notes']?.toString() ?? '');
    var vehicleId = (record?['vehicle_id'] as int?) ?? (_vehicles.first['id'] as int);
    var walletId = (record?['wallet_id'] as int?) ?? (_wallets.first['id'] as int);
    var category = (record?['category'] ?? _expenseCategories.first).toString();
    var date = DateTime.tryParse(record?['date']?.toString() ?? '') ?? DateTime.now();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent, elevation: 0,
      builder: (sheet) => StatefulBuilder(builder: (context, setSheet) => _sheetFrame(context,
        Form(key: key, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHeader(record == null ? 'Add Vehicle Expense' : 'Edit Vehicle Expense', sheet),
            DropdownButtonFormField<int>(value: vehicleId, isExpanded: true, decoration: _decoration('Vehicle', Icons.directions_car_outlined),
              items: _vehicles.map((v) => DropdownMenuItem(value: v['id'] as int, child: Text(v['name'].toString()))).toList(), onChanged: (v) { if (v != null) setSheet(() => vehicleId = v); }),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Amount', Icons.currency_exchange), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter amount' : null; })),
              SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(value: category, isExpanded: true, decoration: _decoration('Category', Icons.category_outlined),
                items: _expenseCategories.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) { if (v != null) setSheet(() => category = v); })),
            ]),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: odo, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Odometer (KM)', Icons.speed_rounded), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 ? 'Enter KM' : null; })),
              SizedBox(width: 10),
              Expanded(child: InkWell(onTap: () async { final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setSheet(() => date = d); }, child: InputDecorator(decoration: _decoration('Date', Icons.calendar_month), child: Text(DateFormat('dd MMM yyyy').format(date), style: TextStyle(fontSize: 13))))),
            ]),
            SizedBox(height: 12),
            TextFormField(controller: vendor, decoration: _decoration('Workshop / Vendor', Icons.storefront_outlined)),
            SizedBox(height: 12),
            DropdownButtonFormField<int>(value: walletId, isExpanded: true, decoration: _decoration('Pay from Wallet', Icons.account_balance_wallet_outlined),
              items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text('${w['name']} • ${w['currency']}'))).toList(), onChanged: (v) { if (v != null) setSheet(() => walletId = v); }),
            SizedBox(height: 12),
            TextFormField(controller: notes, maxLines: 2, decoration: _decoration('Notes / Memo', Icons.notes_rounded)),
            SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: Text(appText(context, "Cancel", "Cancel")))),
              SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(onPressed: _saving ? null : () async {
                if (!key.currentState!.validate()) return;
                setSheet(() => _saving = true);
                try {
                  final v = _vehicles.firstWhere((e) => e['id'] == vehicleId);
                  if (record == null) {
                    await VehicleService.addExpense(vehicleId: vehicleId, vehicleName: v['name'].toString(), date: date,
                      amount: double.parse(amount.text), odometer: double.parse(odo.text), walletId: walletId,
                      category: category, vendor: vendor.text.trim(), notes: notes.text.trim());
                  } else {
                    await VehicleService.updateExpense(id: record['id'] as int, vehicleId: vehicleId, vehicleName: v['name'].toString(), date: date,
                      amount: double.parse(amount.text), odometer: double.parse(odo.text), walletId: walletId,
                      category: category, vendor: vendor.text.trim(), notes: notes.text.trim());
                  }
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet); await _load(); _message(record == null ? 'Expense saved and linked to Finance transactions.' : 'Vehicle expense updated.');
                } catch (e) { _message('Unable to save expense: $e'); }
                finally { if (mounted) setState(() => _saving = false); }
              }, icon: Icon(Icons.check_rounded), label: Text(record == null ? 'Save Expense' : 'Update Expense'), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Theme.of(context).colorScheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 13)))),
            ]),
          ]),
        )),
      )),
    );
    amount.dispose(); odo.dispose(); vendor.dispose(); notes.dispose();
  }

  Future<void> _showReminderForm({Map<String, dynamic>? reminder}) async {
    if (_vehicles.isEmpty) { _message('Please add a vehicle first.'); return; }
    final key = GlobalKey<FormState>();
    final title = TextEditingController(text: reminder?['title']?.toString() ?? '');
    final dueOdo = TextEditingController(text: reminder?['due_odometer']?.toString() ?? '');
    final notes = TextEditingController(text: reminder?['notes']?.toString() ?? '');
    var vehicleId = (reminder?['vehicle_id'] as int?) ?? (_vehicles.first['id'] as int);
    var dueDate = DateTime.tryParse(reminder?['due_date']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 30));
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent, elevation: 0,
      builder: (sheet) => StatefulBuilder(builder: (context, setSheet) => _sheetFrame(context,
        Form(key: key, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHeader(reminder == null ? 'Add Service Reminder' : 'Edit Service Reminder', sheet),
            DropdownButtonFormField<int>(value: vehicleId, isExpanded: true, decoration: _decoration('Vehicle', Icons.directions_car_outlined),
              items: _vehicles.map((v) => DropdownMenuItem(value: v['id'] as int, child: Text(v['name'].toString()))).toList(), onChanged: (v) { if (v != null) setSheet(() => vehicleId = v); }),
            SizedBox(height: 12),
            TextFormField(controller: title, decoration: _decoration('Reminder Title', Icons.notifications_active_outlined), validator: (v) => v == null || v.trim().isEmpty ? 'Enter reminder title' : null),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: InkWell(onTap: () async { final d = await showDatePicker(context: context, initialDate: dueDate, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setSheet(() => dueDate = d); }, child: InputDecorator(decoration: _decoration('Due Date', Icons.calendar_month), child: Text(DateFormat('dd MMM yyyy').format(dueDate), style: TextStyle(fontSize: 13))))),
              SizedBox(width: 10),
              Expanded(child: TextFormField(controller: dueOdo, keyboardType: TextInputType.number, decoration: _decoration('Due at KM (optional)', Icons.speed_rounded), validator: (v) { if ((v ?? '').trim().isEmpty) return null; final n = double.tryParse(v!); return n == null || !n.isFinite || n <= 0 ? 'Enter valid KM' : null; })),
            ]),
            SizedBox(height: 12),
            TextFormField(controller: notes, maxLines: 2, decoration: _decoration('Notes', Icons.notes_rounded)),
            SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: Text(appText(context, "Cancel", "Cancel")))),
              SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(onPressed: _saving ? null : () async {
                if (!key.currentState!.validate()) return;
                setSheet(() => _saving = true);
                try {
                  await VehicleService.saveReminder({'id': reminder?['id'], 'vehicle_id': vehicleId, 'title': title.text.trim(),
                    'due_date': dueDate.toIso8601String(), 'due_odometer': double.tryParse(dueOdo.text),
                    'notes': notes.text.trim()});
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet); await _load(); _message('Reminder saved.');
                } catch (e) { _message('Unable to save reminder: $e'); }
                finally { if (mounted) setState(() => _saving = false); }
              }, icon: Icon(Icons.check_rounded), label: Text(reminder == null ? 'Save Reminder' : 'Update Reminder'), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Theme.of(context).colorScheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 13)))),
            ]),
          ]),
        )),
      )),
    );
    title.dispose(); dueOdo.dispose(); notes.dispose();
  }

  Future<void> _deleteRecord(Future<void> Function() action, String label) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Delete $label?'), content: Text(appText(context, "This record and any linked financial transaction will be removed. This cannot be undone.", "This record and any linked financial transaction will be removed. This cannot be undone.")),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(appText(context, "Cancel", "Cancel"))),
        FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), child: Text(appText(context, "Delete", "Delete")))]));
    if (yes != true) return;
    try { await action(); await _load(); _message('$label deleted.'); }
    catch (e) { _message('Unable to delete $label: $e'); }
  }

  Future<void> _export(bool excel) async {
    final reportFuel = _rangeRows(_fuel);
    final reportExpenses = _rangeRows(_expenses);
    final reportReminders = _rangeRows(_reminders);
    try {
      final file = excel
        ? await VehicleExportService.exportExcel(vehicles: _vehicles, fuel: reportFuel, expenses: reportExpenses, reminders: reportReminders)
        : await VehicleExportService.exportPdf(vehicles: _vehicles, fuel: reportFuel, expenses: reportExpenses, reminders: reportReminders);
      if (!mounted) return;
      _message('Report saved: ${file.path}');
      await OpenFilex.open(file.path);
    } catch (e) { _message('Report export failed: $e'); }
  }

  Widget _metric(String title, String value, IconData icon, Color color, {String? subtitle}) => Expanded(child: Container(
    padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(15), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 21), SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink), maxLines: 2, overflow: TextOverflow.ellipsis),
      SizedBox(height: 3), Text(title, style: TextStyle(fontSize: 11, color: _muted)),
      if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 10, color: _muted)),
    ]),
  ));

  Widget _empty(String title, String detail, IconData icon) => Center(child: Padding(
    padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: _green.withOpacity(.65)), SizedBox(height: 12),
      Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
      SizedBox(height: 5), Text(detail, textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
    ]),
  ));

  Widget _dashboard() {
    final due = _dueReminders();
    final distance = _vehicles.fold<double>(0, (sum, v) => sum + _distanceFor(v['id'] as int));
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(12, 14, 12, 100), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_green, Theme.of(context).colorScheme.primaryContainer], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(appText(context, "Vehicle Overview", "Vehicle Overview"), style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 19, fontWeight: FontWeight.w800)),
            SizedBox(height: 5), Text(appText(context, "Fuel, mileage and running costs in one place", "Fuel, mileage and running costs in one place"), style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .78), fontSize: 12)),
          ])),
          CircleAvatar(radius: 25, backgroundColor: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .14), child: Icon(Icons.directions_car_filled_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 27)),
        ]),
      ),
      SizedBox(height: 13),
      Row(children: [
        _metric('Vehicles', '${_vehicles.length}', Icons.directions_car_outlined, _green),
        SizedBox(width: 10), _metric('Distance tracked', '${_amount(distance)} km', Icons.speed_rounded, Theme.of(context).colorScheme.primary),
      ]),
      SizedBox(height: 10),
      Row(children: [
        _metric('Fuel spending', _moneyByCurrency(_fuel, 'total'), Icons.local_gas_station_outlined, Theme.of(context).colorScheme.tertiary),
        SizedBox(width: 10), _metric('Other expenses', _moneyByCurrency(_expenses, 'amount'), Icons.build_outlined, Theme.of(context).colorScheme.error),
      ]),
      SizedBox(height: 10),
      Row(children: [
        _metric('This month', _monthlySpend(), Icons.calendar_month_outlined, Theme.of(context).colorScheme.secondary),
        SizedBox(width: 10), _metric('Due alerts', '${due.length}', Icons.notifications_active_outlined, due.isEmpty ? _green : Theme.of(context).colorScheme.error),
      ]),
      SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(appText(context, "Reminders & Alerts", "Reminders & Alerts"), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
        Text('${due.length} due', style: TextStyle(color: due.isEmpty ? _muted : Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
      SizedBox(height: 8),
      if (due.isEmpty) Card(child: ListTile(leading: Icon(Icons.check_circle_outline, color: _green), title: Text(appText(context, 'No overdue reminders', 'کوئی تاخیر شدہ یاددہانی نہیں')), subtitle: Text(appText(context, 'Your service schedule is up to date.', 'آپ کی سروس کا شیڈول اپ ڈیٹ ہے۔'))))
      else ...due.map((r) => Card(child: ListTile(
        leading: Icon(Icons.notifications_active_outlined, color: Theme.of(context).colorScheme.error),
        title: Text(r['title'].toString(), style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_vehicleName(r['vehicle_id'])} • Due ${_date(r['due_date'])}'),
        trailing: IconButton(icon: Icon(Icons.delete_outline), onPressed: () => _deleteRecord(() => VehicleService.deleteReminder(r['id'] as int), 'reminder')),
      ))),
      SizedBox(height: 14),
      Text(appText(context, "Your Vehicles", "Your Vehicles"), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      SizedBox(height: 8),
      if (_vehicles.isEmpty) _empty('No vehicles added', 'Add your car or bike to start tracking fuel and expenses.', Icons.directions_car_outlined)
      else ..._vehicles.map(_vehicleCard),
    ]));
  }

  Widget _vehicleCard(Map<String, dynamic> v) {
    final id = v['id'] as int;
    final avg = _averageMileage(id);
    final expenses = _expenses.where((e) => e['vehicle_id'] == id).toList();
    final fuel = _fuel.where((e) => e['vehicle_id'] == id).toList();
    return Card(margin: const EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(v['type'] == 'Bike' ? Icons.two_wheeler_rounded : Icons.directions_car_rounded, color: _green)),
        title: Text(v['name'].toString(), style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
        subtitle: Text('${v['model'] ?? ''} • ${v['registration'] ?? 'No registration'} • ${v['fuel_type']}'),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              _smallStat('Odometer', '${_amount(_latestOdometer(id))} km'),
              _smallStat('Distance', '${_amount(_distanceFor(id))} km'),
              _smallStat('Mileage', avg == null ? '—' : '${_amount(avg)} ${_mileageUnit(id)}'),
              _smallStat('Cost / KM', _costPerKm(id)),
              _smallStat('Fuel fills', '${fuel.length}'),
              _smallStat('Fuel used', '${_amount(fuel.fold<double>(0, (s, f) => s + ((f['quantity'] as num?)?.toDouble() ?? 0)))} ${v['fuel_type'] == 'Electric' ? 'kWh' : 'L'}'),
              _smallStat('Service costs', '${expenses.length}'),
            ]),
            if ((v['notes'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(v['notes'].toString(), style: TextStyle(color: _muted, fontSize: 12))),
            Row(children: [
              TextButton.icon(onPressed: () => _showVehicleForm(vehicle: v), icon: Icon(Icons.edit_outlined), label: Text(appText(context, "Edit", "Edit"))),
              TextButton.icon(onPressed: () => _deleteRecord(() async { await VehicleService.deleteVehicle(id); await AttachmentService.deleteOwnerAttachments(ownerType: 'vehicle', ownerId: id); }, 'vehicle'), icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), label: Text(appText(context, "Delete", "Delete"), style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ]),
            AttachmentSection(ownerType: 'vehicle', ownerId: id),
          ])),
        ],
      ),
    );
  }

  Widget _smallStat(String title, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: _muted, fontSize: 10)),
      SizedBox(height: 2), Text(value, style: TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _vehiclesTab() => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
    if (_vehicles.isEmpty) _empty('No vehicles yet', 'Use Add Vehicle to create your first vehicle profile.', Icons.directions_car_outlined)
    else ..._vehicles.map(_vehicleCard),
  ]));

  Widget _fuelTab() => RefreshIndicator(onRefresh: _load, child: _fuel.isEmpty
    ? _empty('No fuel records', 'Add a fuel fill-up to track consumption and cost per kilometre.', Icons.local_gas_station_outlined)
    : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: _fuel.map((f) => Card(
      margin: const EdgeInsets.only(bottom: 9), child: ExpansionTile(
        leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.tertiaryContainer, child: Icon(Icons.local_gas_station_outlined, color: Theme.of(context).colorScheme.tertiary)),
        title: Text('${_vehicleName(f['vehicle_id'])} • ${_walletCurrency(f['wallet_id'])} ${_moneyAmount(f['total'])}', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${_date(f['date'])} • ${_amount(f['quantity'])} ${f['unit']} • ${_amount(f['odometer'])} km'),
        trailing: PopupMenuButton<String>(onSelected: (v) {
          if (v == 'edit') _showFuelForm(record: f);
          if (v == 'delete') _deleteRecord(() async { final id = f['id'] as int; await VehicleService.deleteFuel(id); await AttachmentService.deleteOwnerAttachments(ownerType: 'vehicle_fuel', ownerId: id); }, 'fuel entry');
        }, itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(appText(context, 'Edit Fuel Entry', 'ایندھن کے اندراج میں ترمیم کریں'))),
          PopupMenuItem(value: 'delete', child: Text(appText(context, 'Delete Fuel Entry', 'ایندھن کا اندراج حذف کریں'))),
        ]),
        children: [
          ListTile(dense: true, title: Text(appText(context, 'Price per unit', 'فی یونٹ قیمت')), trailing: Text(_moneyAmount(f['unit_price']))),
          ListTile(dense: true, title: Text(appText(context, 'Fuel station', 'پیٹرول پمپ')), trailing: Text((f['station'] ?? '—').toString())),
          ListTile(dense: true, title: Text(appText(context, 'Tank fill', 'ٹینک بھرنا')), trailing: Text(f['full_tank'] == true ? 'Full tank' : 'Partial')),
          if ((f['notes'] ?? '').toString().isNotEmpty) ListTile(dense: true, title: Text(appText(context, 'Notes', 'نوٹس')), subtitle: Text(f['notes'].toString())),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: AttachmentSection(ownerType: 'vehicle_fuel', ownerId: f['id'] as int)),
        ],
      ),
    )).toList()));

  Widget _expensesTab() => RefreshIndicator(onRefresh: _load, child: _expenses.isEmpty
    ? _empty('No vehicle expenses', 'Record servicing, repairs, tyres, insurance and other costs.', Icons.build_outlined)
    : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: _expenses.map((e) => Card(
      margin: const EdgeInsets.only(bottom: 9), child: ExpansionTile(
        leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.errorContainer, child: Icon(Icons.build_outlined, color: Theme.of(context).colorScheme.error)),
        title: Text('${e['category']} • ${_walletCurrency(e['wallet_id'])} ${_moneyAmount(e['amount'])}', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${_vehicleName(e['vehicle_id'])} • ${_date(e['date'])} • ${_amount(e['odometer'])} km'),
        trailing: PopupMenuButton<String>(onSelected: (v) {
          if (v == 'edit') _showExpenseForm(record: e);
          if (v == 'delete') _deleteRecord(() async { final id = e['id'] as int; await VehicleService.deleteExpense(id); await AttachmentService.deleteOwnerAttachments(ownerType: 'vehicle_expense', ownerId: id); }, 'vehicle expense');
        }, itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(appText(context, 'Edit Expense', 'اخراجات میں ترمیم کریں'))),
          PopupMenuItem(value: 'delete', child: Text(appText(context, 'Delete Expense', 'اخراجات حذف کریں'))),
        ]),
        children: [
          ListTile(dense: true, title: Text(appText(context, 'Paid from', 'ادائیگی کا اکاؤنٹ')), trailing: Text(_walletName(e['wallet_id']))),
          ListTile(dense: true, title: Text(appText(context, 'Workshop / Vendor', 'ورکشاپ / فروخت کنندہ')), trailing: Text((e['vendor'] ?? '—').toString())),
          if ((e['notes'] ?? '').toString().isNotEmpty) ListTile(dense: true, title: Text(appText(context, 'Notes', 'نوٹس')), subtitle: Text(e['notes'].toString())),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: AttachmentSection(ownerType: 'vehicle_expense', ownerId: e['id'] as int)),
        ],
      ),
    )).toList()));

  Widget _remindersTab() => RefreshIndicator(onRefresh: _load, child: _reminders.isEmpty
    ? _empty('No service reminders', 'Create reminders for oil changes, servicing, tyres, insurance and documents.', Icons.notifications_none_rounded)
    : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: _reminders.map((r) {
      final due = DateTime.tryParse(r['due_date']?.toString() ?? '');
      final dueByDate = due != null && !due.isAfter(DateTime.now());
      final dueKm = (r['due_odometer'] as num?)?.toDouble();
      final overdue = dueByDate || (dueKm != null && dueKm > 0 && _latestOdometer((r['vehicle_id'] as num).toInt()) >= dueKm);
      return Card(margin: const EdgeInsets.only(bottom: 9), child: ListTile(
        leading: Icon(Icons.notifications_active_outlined, color: overdue ? Theme.of(context).colorScheme.error : _green),
        title: Text(r['title'].toString(), style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_vehicleName(r['vehicle_id'])} • ${_date(r['due_date'])}${r['due_odometer'] == null ? '' : ' • ${_amount(r['due_odometer'])} km'}'),
        trailing: PopupMenuButton<String>(onSelected: (v) {
          if (v == 'edit') _showReminderForm(reminder: r);
          if (v == 'delete') _deleteRecord(() => VehicleService.deleteReminder(r['id'] as int), 'reminder');
        }, itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(appText(context, 'Edit Reminder', 'یاددہانی میں ترمیم کریں'))),
          PopupMenuItem(value: 'delete', child: Text(appText(context, 'Delete Reminder', 'یاددہانی حذف کریں'))),
        ]),
      ));
    }).toList()));

  List<Map<String, dynamic>> _rangeRows(List<Map<String, dynamic>> rows) {
    if (_reportRange == 'All Time') return rows;
    final now = DateTime.now();
    return rows.where((r) {
      final date = DateTime.tryParse(r['date']?.toString() ?? r['due_date']?.toString() ?? '');
      if (date == null) return false;
      if (_reportRange == 'Daily') return date.year == now.year && date.month == now.month && date.day == now.day;
      if (_reportRange == 'Weekly') return !date.isBefore(now.subtract(const Duration(days: 7)));
      if (_reportRange == 'Monthly') return date.year == now.year && date.month == now.month;
      if (_reportRange == 'Yearly') return date.year == now.year;
      return true;
    }).toList();
  }

  Widget _reportsTab() {
    final reportFuel = _rangeRows(_fuel);
    final sortedFuel = [...reportFuel]..sort((a,b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
      DropdownButtonFormField<String>(value: _reportRange, decoration: _decoration('Report Period', Icons.date_range_outlined),
        items: const ['Daily', 'Weekly', 'Monthly', 'Yearly', 'All Time'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _reportRange = v ?? 'All Time')),
      SizedBox(height: 12),
      Text(appText(context, "Vehicle Comparison", "Vehicle Comparison"), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      SizedBox(height: 8),
      if (_vehicles.isEmpty) _empty('No comparison data', 'Add vehicles and fuel records to compare running costs.', Icons.compare_arrows_rounded)
      else ..._vehicles.map((v) {
        final id = v['id'] as int; final mileage = _averageMileage(id);
        final distance = _distanceFor(id);
        return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v['name'].toString(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _smallStat('Distance', '${_amount(distance)} km'),
            _smallStat('Mileage', mileage == null ? '—' : '${_amount(mileage)} ${_mileageUnit(id)}'),
            _smallStat('Cost / KM', _costPerKm(id)),
            _smallStat('Fuel cost', _vehicleCost(id, fuelOnly: true)),
            _smallStat('Other cost', _vehicleCost(id, fuelOnly: false)),
          ]),
        ])));
      }),
      SizedBox(height: 14),
      Text(appText(context, "Fuel Price History", "Fuel Price History"), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      SizedBox(height: 8),
      if (sortedFuel.isEmpty) Card(child: ListTile(title: Text(appText(context, "No fuel price history yet.", "No fuel price history yet."))))
      else ...sortedFuel.take(30).map((f) => Card(child: ListTile(
        dense: true, leading: Icon(Icons.price_change_outlined, color: Theme.of(context).colorScheme.tertiary),
        title: Text('${_vehicleName(f['vehicle_id'])} • ${_walletCurrency(f['wallet_id'])} ${_moneyAmount(f['unit_price'])} / ${f['unit']}'),
        subtitle: Text('${_date(f['date'])} • ${f['station'] ?? 'Station not entered'}'),
        trailing: Text('${_amount(f['quantity'])} ${f['unit']}'),
      ))),
      SizedBox(height: 16),
      Text(appText(context, "Export Reports", "Export Reports"), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      SizedBox(height: 8),
      Card(child: Column(children: [
        ListTile(leading: Icon(Icons.table_view_rounded, color: _green), title: Text(appText(context, 'Excel Workbook', 'ایکسل فائل')), subtitle: Text(appText(context, "Vehicles, fuel log, expenses and reminders", "Vehicles, fuel log, expenses and reminders")), trailing: Icon(Icons.download_rounded), onTap: () => _export(true)),
        const Divider(height: 1),
        ListTile(leading: Icon(Icons.picture_as_pdf_rounded, color: Theme.of(context).colorScheme.error), title: Text(appText(context, 'PDF Report', 'پی ڈی ایف رپورٹ')), subtitle: Text(appText(context, "Shareable summary of all vehicle records", "Shareable summary of all vehicle records")), trailing: Icon(Icons.download_rounded), onTap: () => _export(false)),
      ])),
      SizedBox(height: 8),
      Text(appText(context, "Reports are saved in the app documents folder and opened with a compatible app.", "Reports are saved in the app documents folder and opened with a compatible app."), style: TextStyle(color: _muted, fontSize: 11)),
    ]);
  }

  Widget _vehicleNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final selected = _tabs.index == index;
    return Expanded(
      child: InkWell(
        onTap: () => _tabs.animateTo(index),
        child: SizedBox(
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Icon(
                    selected ? activeIcon : icon,
                    size: 21,
                    color: selected ? _green : _muted,
                  ),
                ),
              ),
              SizedBox(height: 2),
              SizedBox(
                height: 14,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: selected ? _green : _muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openVehiclePlusSheet() async {
    var tab = 'Fuel';
    final keys = {for (final t in ['Vehicle','Fuel','Expense','Reminder']) t: GlobalKey<FormState>()};
    final cs = List.generate(17, (_) => TextEditingController());
    var vehicleType='Car', vehicleFuel='Petrol', fuelVehicle=_vehicles.isEmpty?0:_vehicles.first['id'] as int, fuelWallet=_wallets.isEmpty?0:_wallets.first['id'] as int, expenseVehicle=_vehicles.isEmpty?0:_vehicles.first['id'] as int, expenseWallet=_wallets.isEmpty?0:_wallets.first['id'] as int, reminderVehicle=_vehicles.isEmpty?0:_vehicles.first['id'] as int;
    var vehicleDate=DateTime.now(), fuelDate=DateTime.now(), expenseDate=DateTime.now(), reminderDate=DateTime.now().add(const Duration(days:30));
    var fullTank=true, unit='L', category=_expenseCategories.first;
    Widget gap([double h=12])=>SizedBox(height:h);
    Widget date(String label,DateTime value,void Function(DateTime) set,BuildContext c)=>InkWell(onTap:()async{final d=await showDatePicker(context:c,initialDate:value,firstDate:DateTime(1950),lastDate:DateTime(2100));if(d!=null)set(d);},child:InputDecorator(decoration:_decoration(label,Icons.calendar_month),child:Text(DateFormat('dd MMM yyyy').format(value))));
    String heading()=>switch(tab){'Vehicle'=>'Add Vehicle','Fuel'=>'Add Fuel Entry','Expense'=>'Add Vehicle Expense','Reminder'=>'Add Service Reminder',_=>'Add'};
    Widget form(BuildContext c,StateSetter upd){
      if(tab=='Vehicle')return Form(key:keys[tab],child:Column(children:[
        TextFormField(controller:cs[0],decoration:_decoration('Vehicle Name',Icons.directions_car_outlined),validator:(v)=>(v??'').trim().isEmpty?'Enter vehicle name':null),
        gap(),Row(children:[Expanded(child:DropdownButtonFormField<String>(value:vehicleType,decoration:_decoration('Vehicle Type',Icons.category),items:_vehicleTypes.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x){if(x!=null)upd(()=>vehicleType=x);})),gap(8),Expanded(child:DropdownButtonFormField<String>(value:vehicleFuel,decoration:_decoration('Fuel Type',Icons.local_gas_station),items:_fuelTypes.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x){if(x!=null)upd(()=>vehicleFuel=x);} ))]),
        gap(),TextFormField(controller:cs[1],decoration:_decoration('Company / Model',Icons.car_repair)),
        gap(),TextFormField(controller:cs[2],decoration:_decoration('Registration Number',Icons.confirmation_number)),
        gap(),Row(children:[Expanded(child:TextFormField(controller:cs[3],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:_decoration('Purchase Price (optional)',Icons.payments),validator:(v){if((v??'').isEmpty)return null;final n=double.tryParse(v!);return n==null||n<0?'Invalid price':null;})),gap(8),Expanded(child:date('Purchase Date',vehicleDate,(d)=>upd(()=>vehicleDate=d),c))]),
        gap(),TextFormField(controller:cs[4],maxLines:2,decoration:_decoration('Notes',Icons.notes)),
      ]));
      if(tab=='Fuel')return Form(key:keys[tab],child:Column(children:[
        if(_vehicles.isEmpty||_wallets.isEmpty)Text(_vehicles.isEmpty?'Please add a vehicle first.':'Please add a wallet first.')
        else DropdownButtonFormField<int>(value:fuelVehicle,decoration:_decoration('Vehicle',Icons.directions_car),items:_vehicles.map((v)=>DropdownMenuItem(value:v['id'] as int,child:Text(v['name'].toString()))).toList(),onChanged:(v){if(v!=null)upd((){fuelVehicle=v;unit=_vehicles.firstWhere((e)=>e['id']==v)['fuel_type']=='Electric'?'kWh':'L';});}),
        gap(),Row(children:[Expanded(child:TextFormField(controller:cs[5],keyboardType:TextInputType.number,decoration:_decoration('Odometer (KM)',Icons.speed),validator:(v){final n=double.tryParse(v??'');return n==null||n<0?'Enter KM':null;})),gap(8),Expanded(child:date('Date',fuelDate,(d)=>upd(()=>fuelDate=d),c))]),
        gap(),Row(children:[Expanded(child:TextFormField(controller:cs[6],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:_decoration('Quantity ('+unit+')',Icons.local_gas_station),validator:(v){final n=double.tryParse(v??'');return n==null||n<=0?'Enter quantity':null;},onChanged:(_)=>upd((){}))),gap(8),Expanded(child:TextFormField(controller:cs[7],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:_decoration('Unit Price',Icons.price_change),validator:(v){final n=double.tryParse(v??'');return n==null||n<=0?'Enter price':null;},onChanged:(_)=>upd((){})))]),
        gap(6),Text('Total Fuel Cost: '+_amount((double.tryParse(cs[6].text)??0)*(double.tryParse(cs[7].text)??0)),style:TextStyle(color:_green,fontWeight:FontWeight.bold)),
        CheckboxListTile(contentPadding:EdgeInsets.zero,value:fullTank,onChanged:(v)=>upd(()=>fullTank=v??false),title:Text('Full tank / charge'),dense:true),
        TextFormField(controller:cs[8],decoration:_decoration('Fuel Station (optional)',Icons.store)),
        gap(),DropdownButtonFormField<int>(value:fuelWallet,decoration:_decoration('Pay from Wallet',Icons.account_balance_wallet),items:_wallets.map((w)=>DropdownMenuItem(value:w['id'] as int,child:Text(w['name'].toString()+' • '+w['currency'].toString()))).toList(),onChanged:(v){if(v!=null)upd(()=>fuelWallet=v);}),
        gap(),TextFormField(controller:cs[9],maxLines:2,decoration:_decoration('Notes / Memo',Icons.notes)),
      ]));
      if(tab=='Expense')return Form(key:keys[tab],child:Column(children:[
        if(_vehicles.isEmpty||_wallets.isEmpty)Text(_vehicles.isEmpty?'Please add a vehicle first.':'Please add a wallet first.')
        else DropdownButtonFormField<int>(value:expenseVehicle,decoration:_decoration('Vehicle',Icons.directions_car),items:_vehicles.map((v)=>DropdownMenuItem(value:v['id'] as int,child:Text(v['name'].toString()))).toList(),onChanged:(v){if(v!=null)upd(()=>expenseVehicle=v);}),
        gap(),Row(children:[Expanded(child:TextFormField(controller:cs[10],keyboardType:TextInputType.number,decoration:_decoration('Amount',Icons.currency_exchange),validator:(v){final n=double.tryParse(v??'');return n==null||n<=0?'Enter amount':null;})),gap(8),Expanded(child:DropdownButtonFormField<String>(value:category,decoration:_decoration('Category',Icons.category),items:_expenseCategories.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x){if(x!=null)upd(()=>category=x);} ))]),
        gap(),Row(children:[Expanded(child:TextFormField(controller:cs[11],keyboardType:TextInputType.number,decoration:_decoration('Odometer (KM)',Icons.speed),validator:(v){final n=double.tryParse(v??'');return n==null||n<0?'Enter KM':null;})),gap(8),Expanded(child:date('Date',expenseDate,(d)=>upd(()=>expenseDate=d),c))]),
        gap(),TextFormField(controller:cs[12],decoration:_decoration('Workshop / Vendor',Icons.store)),
        gap(),DropdownButtonFormField<int>(value:expenseWallet,decoration:_decoration('Pay from Wallet',Icons.account_balance_wallet),items:_wallets.map((w)=>DropdownMenuItem(value:w['id'] as int,child:Text(w['name'].toString()+' • '+w['currency'].toString()))).toList(),onChanged:(v){if(v!=null)upd(()=>expenseWallet=v);}),
        gap(),TextFormField(controller:cs[13],maxLines:2,decoration:_decoration('Notes / Memo',Icons.notes)),
      ]));
      return Form(key:keys[tab],child:Column(children:[
        if(_vehicles.isEmpty)Text('Please add a vehicle first.')
        else DropdownButtonFormField<int>(value:reminderVehicle,decoration:_decoration('Vehicle',Icons.directions_car),items:_vehicles.map((v)=>DropdownMenuItem(value:v['id'] as int,child:Text(v['name'].toString()))).toList(),onChanged:(v){if(v!=null)upd(()=>reminderVehicle=v);}),
        gap(),TextFormField(controller:cs[14],decoration:_decoration('Reminder Title',Icons.notifications_active),validator:(v)=>(v??'').trim().isEmpty?'Enter title':null),
        gap(),Row(children:[Expanded(child:date('Due Date',reminderDate,(d)=>upd(()=>reminderDate=d),c)),gap(8),Expanded(child:TextFormField(controller:cs[15],keyboardType:TextInputType.number,decoration:_decoration('Due at KM (optional)',Icons.speed),validator:(v){if((v??'').trim().isEmpty)return null;final n=double.tryParse(v!);return n==null||n<=0?'Invalid KM':null;}))]),
        gap(),TextFormField(controller:cs[16],maxLines:2,decoration:_decoration('Notes',Icons.notes)),
      ]));
    }
    Future<void> saveTab(StateSetter upd)async{
      if(tab=='Fuel'&&(_vehicles.isEmpty||_wallets.isEmpty)){_message(_vehicles.isEmpty?'Please add a vehicle first.':'Please add a wallet first.');return;}
      if(tab=='Expense'&&(_vehicles.isEmpty||_wallets.isEmpty)){_message(_vehicles.isEmpty?'Please add a vehicle first.':'Please add a wallet first.');return;}
      if(tab=='Reminder'&&_vehicles.isEmpty){_message('Please add a vehicle first.');return;}
      if(!keys[tab]!.currentState!.validate())return;
      upd(()=>_saving=true);
      try{
        if(tab=='Vehicle'){await VehicleService.saveVehicle({'name':cs[0].text.trim(),'type':vehicleType,'fuel_type':vehicleFuel,'model':cs[1].text.trim(),'registration':cs[2].text.trim(),'purchase_price':double.tryParse(cs[3].text)??0,'purchase_date':vehicleDate.toIso8601String(),'notes':cs[4].text.trim()});for(final i in [0,1,2,3,4])cs[i].clear();vehicleType='Car';vehicleFuel='Petrol';vehicleDate=DateTime.now();_message('Vehicle added.');}
        else if(tab=='Fuel'){final v=_vehicles.firstWhere((v)=>v['id']==fuelVehicle);await VehicleService.addFuel(vehicleId:fuelVehicle,vehicleName:v['name'].toString(),date:fuelDate,odometer:double.parse(cs[5].text),quantity:double.parse(cs[6].text),unitPrice:double.parse(cs[7].text),fullTank:fullTank,walletId:fuelWallet,station:cs[8].text.trim(),notes:cs[9].text.trim(),unit:unit);for(final i in [5,6,7,8,9])cs[i].clear();fuelDate=DateTime.now();fullTank=true;_message('Fuel entry saved and linked to Finance expenses.');}
        else if(tab=='Expense'){final v=_vehicles.firstWhere((v)=>v['id']==expenseVehicle);await VehicleService.addExpense(vehicleId:expenseVehicle,vehicleName:v['name'].toString(),date:expenseDate,amount:double.parse(cs[10].text),odometer:double.parse(cs[11].text),walletId:expenseWallet,category:category,vendor:cs[12].text.trim(),notes:cs[13].text.trim());for(final i in [10,11,12,13])cs[i].clear();expenseDate=DateTime.now();category=_expenseCategories.first;_message('Expense saved and linked to Finance transactions.');}
        else{await VehicleService.saveReminder({'vehicle_id':reminderVehicle,'title':cs[14].text.trim(),'due_date':reminderDate.toIso8601String(),'due_odometer':double.tryParse(cs[15].text),'notes':cs[16].text.trim()});for(final i in [14,15,16])cs[i].clear();reminderDate=DateTime.now().add(const Duration(days:30));_message('Reminder saved.');}
        await _load();upd((){});
      }catch(e){_message('Unable to save: $e');}finally{if(mounted)setState(()=>_saving=false);upd((){});}
    }
    try{
      await showModalBottomSheet<void>(context:context,backgroundColor:Colors.transparent,isScrollControlled:true,useSafeArea:true,builder:(sheet)=>StatefulBuilder(builder:(ctx,setSheet){
        final cards=[('Vehicle',Icons.directions_car_outlined,_green),('Fuel',Icons.local_gas_station_outlined,Theme.of(ctx).colorScheme.tertiary),('Expense',Icons.build_outlined,Theme.of(ctx).colorScheme.error),('Reminder',Icons.notifications_active_outlined,Theme.of(ctx).colorScheme.secondary)];
        return Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(ctx).bottom),child:SafeArea(top:false,child:Container(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(ctx).height*.88),decoration:BoxDecoration(color:Theme.of(ctx).colorScheme.surface,borderRadius:const BorderRadius.vertical(top:Radius.circular(26))),padding:const EdgeInsets.fromLTRB(14,10,14,16),child:SingleChildScrollView(keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Center(child:Container(width:38,height:4,decoration:BoxDecoration(color:Theme.of(ctx).dividerColor,borderRadius:BorderRadius.circular(8)))),const SizedBox(height:12),
          Text(heading(),style:TextStyle(fontSize:19,fontWeight:FontWeight.w800,color:_ink)),const SizedBox(height:8),
          Row(children:cards.map((card){final active=tab==card.$1;return Expanded(child:Padding(padding:EdgeInsets.symmetric(horizontal:card.$1=='Vehicle'||card.$1=='Reminder'?0:4),child:InkWell(onTap:()=>setSheet(()=>tab=card.$1),child:Container(constraints:const BoxConstraints(minHeight:68),padding:const EdgeInsets.symmetric(horizontal:2,vertical:7),decoration:BoxDecoration(color:active?card.$3.withValues(alpha:.12):Theme.of(ctx).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(12),border:Border.all(color:active?card.$3:Theme.of(ctx).colorScheme.outlineVariant,width:active?1.4:1)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(card.$2,color:card.$3,size:20),const SizedBox(height:4),Text('Add '+card.$1,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:_ink))])))));}).toList()),
          const SizedBox(height:14),form(ctx,setSheet),const SizedBox(height:14),
          Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(sheet),child:const Text('Cancel'))),const SizedBox(width:10),Expanded(child:ElevatedButton.icon(onPressed:_saving?null:()=>saveTab(setSheet),icon:const Icon(Icons.check_rounded),label:Text(tab=='Vehicle'?'Save Vehicle':tab=='Fuel'?'Save Fuel Entry':tab=='Expense'?'Save Expense':'Save Reminder'),style:ElevatedButton.styleFrom(backgroundColor:_green,foregroundColor:Theme.of(ctx).colorScheme.onPrimary,padding:const EdgeInsets.symmetric(vertical:13))))])
        ])))));
      }));
    }finally{for(final ctrl in cs)ctrl.dispose();}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface, foregroundColor: _ink, elevation: 0,
        titleSpacing: 16, toolbarHeight: 56,
        title: Text(appText(context, "Vehicle Manager", "Vehicle Manager"), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
        actions: buildSharedAppBarActions(context),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.055),
              blurRadius: 14,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                _vehicleNavItem(0, Icons.dashboard_outlined, Icons.dashboard_rounded, 'Overview'),
                _vehicleNavItem(1, Icons.directions_car_outlined, Icons.directions_car_rounded, 'Vehicles'),
                _vehicleNavItem(2, Icons.local_gas_station_outlined, Icons.local_gas_station_rounded, 'Fuel'),
                Expanded(
                  child: InkWell(
                    onTap: _openVehiclePlusSheet,
                    borderRadius: BorderRadius.circular(18),
                    child: Center(
                      child: Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                          color: _green,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(color: _green.withValues(alpha: 0.22), blurRadius: 8, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 29),
                      ),
                    ),
                  ),
                ),
                _vehicleNavItem(3, Icons.build_outlined, Icons.build_rounded, 'Expenses'),
                _vehicleNavItem(4, Icons.notifications_none, Icons.notifications_rounded, 'Reminders'),
                _vehicleNavItem(5, Icons.analytics_outlined, Icons.analytics_rounded, 'Reports'),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _dashboard(),
                _vehiclesTab(),
                _fuelTab(),
                _expensesTab(),
                _remindersTab(),
                _reportsTab(),
              ],
            ),
    );
  }
}
