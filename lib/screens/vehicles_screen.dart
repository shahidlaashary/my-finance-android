import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../services/vehicle_service.dart';
import '../services/attachment_service.dart';
import '../services/vehicle_export_service.dart';
import '../widgets/attachment_section.dart';
import '../widgets/shared_app_bar_actions.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  bool _saving = false;
  String _reportRange = 'All Time';
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _fuel = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _reminders = [];
  List<Map<String, dynamic>> _wallets = [];

  static const _green = Color(0xFF147D59);
  static const _ink = Color(0xFF202A26);
  static const _muted = Color(0xFF7B8781);
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
    _load();
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        VehicleService.getVehicles(), VehicleService.getFuelLogs(),
        VehicleService.getExpenses(), VehicleService.getReminders(),
        VehicleService.getWallets(),
      ]);
      if (!mounted) return;
      setState(() {
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
    return totals.entries.map((e) => '${e.key} ${_amount(e.value)}').join(' • ');
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
    return totals.entries.map((e) => '${e.key} ${_amount(e.value / distance)}/km').join(' • ');
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
    return totals.entries.map((e) => '${e.key} ${_amount(e.value)}').join(' • ');
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

  String _moneyByCurrency(List<Map<String, dynamic>> records, String amountKey) {
    final totals = <String, double>{};
    for (final r in records) {
      final wallet = _wallets.where((w) => w['id'] == r['wallet_id']).toList();
      final currency = wallet.isEmpty ? 'PKR' : (wallet.first['currency'] ?? 'PKR').toString();
      totals[currency] = (totals[currency] ?? 0) + ((r[amountKey] as num?)?.toDouble() ?? 0);
    }
    if (totals.isEmpty) return '0.00';
    return totals.entries.map((e) => '${e.key} ${_amount(e.value)}').join('  •  ');
  }

  double _distanceFor(int vehicleId) {
    final rows = _fuel.where((e) => e['vehicle_id'] == vehicleId).toList()
      ..sort((a,b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    if (rows.length < 2) return 0;
    final first = (rows.first['odometer'] as num?)?.toDouble() ?? 0;
    final last = (rows.last['odometer'] as num?)?.toDouble() ?? 0;
    return last >= first ? last - first : 0;
  }

  double? _averageMileage(int vehicleId) {
    final rows = _fuel.where((e) => e['vehicle_id'] == vehicleId && e['full_tank'] == true).toList()
      ..sort((a,b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    if (rows.length < 2) return null;
    double totalLitres = 0;
    double? result;
    for (var i = 1; i < rows.length; i++) {
      final start = (rows[i - 1]['odometer'] as num?)?.toDouble() ?? 0;
      final end = (rows[i]['odometer'] as num?)?.toDouble() ?? 0;
      for (final f in _fuel) {
        if (f['vehicle_id'] != vehicleId) continue;
        final d = DateTime.tryParse(f['date']?.toString() ?? '');
        final from = DateTime.tryParse(rows[i - 1]['date'].toString());
        final to = DateTime.tryParse(rows[i]['date'].toString());
        if (d != null && from != null && to != null && d.isAfter(from) && !d.isAfter(to)) {
          totalLitres += (f['quantity'] as num?)?.toDouble() ?? 0;
        }
      }
      if (end > start && totalLitres > 0) result = (end - start) / totalLitres;
      totalLitres = 0;
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
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E9E5))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _green, width: 1.5)),
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
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: child,
        ),
      )),
    );
  }

  Widget _sheetHeader(String title, BuildContext context) => Column(children: [
    Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD9E0DC), borderRadius: BorderRadius.circular(10)))),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink))),
      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded), color: Colors.grey),
    ]),
    const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(value: type, isExpanded: true, decoration: _decoration('Vehicle Type', Icons.category_outlined), items: _vehicleTypes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setSheet(() => type = v); })),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(value: fuelType, isExpanded: true, decoration: _decoration('Fuel Type', Icons.local_gas_station_outlined), items: _fuelTypes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setSheet(() => fuelType = v); })),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: model, decoration: _decoration('Company / Model', Icons.directions_car_filled_outlined)),
            const SizedBox(height: 12),
            TextFormField(controller: registration, textCapitalization: TextCapitalization.characters, decoration: _decoration('Registration Number', Icons.confirmation_number_outlined)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Purchase Price (optional)', Icons.payments_outlined), validator: (v) { if ((v ?? '').trim().isEmpty) return null; final n = double.tryParse(v!); return n == null || !n.isFinite || n < 0 ? 'Enter a valid price' : null; })),
              const SizedBox(width: 10),
              Expanded(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () async { final d = await showDatePicker(context: context, initialDate: purchaseDate, firstDate: DateTime(1950), lastDate: DateTime(2100)); if (d != null) setSheet(() => purchaseDate = d); }, child: InputDecorator(decoration: _decoration('Purchase Date', Icons.calendar_month_outlined), child: Text(DateFormat('dd MMM yyyy').format(purchaseDate), style: const TextStyle(fontSize: 13))))),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: notes, maxLines: 2, decoration: _decoration('Notes', Icons.notes_rounded)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: const Text('Cancel'))),
              const SizedBox(width: 10),
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
              }, icon: const Icon(Icons.check_rounded), label: Text(vehicle == null ? 'Save Vehicle' : 'Update Vehicle'), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)))),
            ]),
          ]),
        )),
      )),
    );
    name.dispose(); model.dispose(); registration.dispose(); price.dispose(); notes.dispose();
  }

  Future<void> _showFuelForm() async {
    if (_vehicles.isEmpty || _wallets.isEmpty) { _message(_vehicles.isEmpty ? 'Please add a vehicle first.' : 'Please add a wallet first.'); return; }
    final key = GlobalKey<FormState>();
    final odo = TextEditingController(); final quantity = TextEditingController(); final unitPrice = TextEditingController();
    final station = TextEditingController(); final notes = TextEditingController();
    var vehicleId = _vehicles.first['id'] as int;
    var walletId = _wallets.first['id'] as int;
    var date = DateTime.now(); var fullTank = true;
    String unit = _vehicles.first['fuel_type'] == 'Electric' ? 'kWh' : 'L';
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent, elevation: 0,
      builder: (sheet) => StatefulBuilder(builder: (context, setSheet) => _sheetFrame(context,
        Form(key: key, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHeader('Add Fuel Entry', sheet),
            DropdownButtonFormField<int>(value: vehicleId, isExpanded: true, decoration: _decoration('Vehicle', Icons.directions_car_outlined),
              items: _vehicles.map((v) => DropdownMenuItem(value: v['id'] as int, child: Text(v['name'].toString()))).toList(),
              onChanged: (v) { if (v != null) setSheet(() { vehicleId = v; final selected = _vehicles.firstWhere((e) => e['id'] == v); unit = selected['fuel_type'] == 'Electric' ? 'kWh' : 'L'; }); }),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: odo, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Odometer (KM)', Icons.speed_rounded), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 ? 'Enter KM reading' : null; })),
              const SizedBox(width: 10),
              Expanded(child: InkWell(onTap: () async { final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setSheet(() => date = d); }, child: InputDecorator(decoration: _decoration('Date', Icons.calendar_month), child: Text(DateFormat('dd MMM yyyy').format(date), style: const TextStyle(fontSize: 13))))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Quantity ($unit)', Icons.local_gas_station), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter quantity' : null; }, onChanged: (_) => setSheet(() {}))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: unitPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Price per $unit (${_walletCurrency(walletId)})', Icons.price_change_outlined), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter price' : null; }, onChanged: (_) => setSheet(() {}))),
            ]),
            const SizedBox(height: 8),
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFEAF4EF), borderRadius: BorderRadius.circular(12)),
              child: Text('Total Fuel Cost: ${_amount((double.tryParse(quantity.text) ?? 0) * (double.tryParse(unitPrice.text) ?? 0))}', style: const TextStyle(color: _green, fontWeight: FontWeight.w800))),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: fullTank, onChanged: (v) => setSheet(() => fullTank = v ?? false), title: Text(unit == 'kWh' ? 'Full charge' : 'Full tank fill-up'), controlAffinity: ListTileControlAffinity.leading, dense: true),
            TextFormField(controller: station, decoration: _decoration('Fuel Station (optional)', Icons.storefront_outlined)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(value: walletId, isExpanded: true, decoration: _decoration('Pay from Wallet', Icons.account_balance_wallet_outlined),
              items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text('${w['name']} • ${w['currency']}'))).toList(),
              onChanged: (v) { if (v != null) setSheet(() => walletId = v); }),
            const SizedBox(height: 12),
            TextFormField(controller: notes, maxLines: 2, decoration: _decoration('Notes / Memo', Icons.notes_rounded)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(onPressed: _saving ? null : () async {
                if (!key.currentState!.validate()) return;
                setSheet(() => _saving = true);
                try {
                  final v = _vehicles.firstWhere((e) => e['id'] == vehicleId);
                  await VehicleService.addFuel(vehicleId: vehicleId, vehicleName: v['name'].toString(), date: date,
                    odometer: double.parse(odo.text), quantity: double.parse(quantity.text), unitPrice: double.parse(unitPrice.text),
                    fullTank: fullTank, walletId: walletId, station: station.text.trim(), notes: notes.text.trim(), unit: unit);
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet); await _load(); _message('Fuel entry saved and linked to Finance expenses.');
                } catch (e) { _message('Unable to save fuel entry: $e'); }
                finally { if (mounted) setState(() => _saving = false); }
              }, icon: const Icon(Icons.check_rounded), label: const Text('Save Fuel Entry'), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)))),
            ]),
          ]),
        )),
      )),
    );
    odo.dispose(); quantity.dispose(); unitPrice.dispose(); station.dispose(); notes.dispose();
  }

  Future<void> _showExpenseForm() async {
    if (_vehicles.isEmpty || _wallets.isEmpty) { _message(_vehicles.isEmpty ? 'Please add a vehicle first.' : 'Please add a wallet first.'); return; }
    final key = GlobalKey<FormState>();
    final amount = TextEditingController(); final odo = TextEditingController(); final vendor = TextEditingController(); final notes = TextEditingController();
    var vehicleId = _vehicles.first['id'] as int; var walletId = _wallets.first['id'] as int;
    var category = _expenseCategories.first; var date = DateTime.now();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent, elevation: 0,
      builder: (sheet) => StatefulBuilder(builder: (context, setSheet) => _sheetFrame(context,
        Form(key: key, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHeader('Add Vehicle Expense', sheet),
            DropdownButtonFormField<int>(value: vehicleId, isExpanded: true, decoration: _decoration('Vehicle', Icons.directions_car_outlined),
              items: _vehicles.map((v) => DropdownMenuItem(value: v['id'] as int, child: Text(v['name'].toString()))).toList(), onChanged: (v) { if (v != null) setSheet(() => vehicleId = v); }),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Amount', Icons.currency_exchange), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter amount' : null; })),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(value: category, isExpanded: true, decoration: _decoration('Category', Icons.category_outlined),
                items: _expenseCategories.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) { if (v != null) setSheet(() => category = v); })),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: odo, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Odometer (KM)', Icons.speed_rounded), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 ? 'Enter KM' : null; })),
              const SizedBox(width: 10),
              Expanded(child: InkWell(onTap: () async { final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setSheet(() => date = d); }, child: InputDecorator(decoration: _decoration('Date', Icons.calendar_month), child: Text(DateFormat('dd MMM yyyy').format(date), style: const TextStyle(fontSize: 13))))),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: vendor, decoration: _decoration('Workshop / Vendor', Icons.storefront_outlined)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(value: walletId, isExpanded: true, decoration: _decoration('Pay from Wallet', Icons.account_balance_wallet_outlined),
              items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text('${w['name']} • ${w['currency']}'))).toList(), onChanged: (v) { if (v != null) setSheet(() => walletId = v); }),
            const SizedBox(height: 12),
            TextFormField(controller: notes, maxLines: 2, decoration: _decoration('Notes / Memo', Icons.notes_rounded)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(onPressed: _saving ? null : () async {
                if (!key.currentState!.validate()) return;
                setSheet(() => _saving = true);
                try {
                  final v = _vehicles.firstWhere((e) => e['id'] == vehicleId);
                  await VehicleService.addExpense(vehicleId: vehicleId, vehicleName: v['name'].toString(), date: date,
                    amount: double.parse(amount.text), odometer: double.parse(odo.text), walletId: walletId,
                    category: category, vendor: vendor.text.trim(), notes: notes.text.trim());
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet); await _load(); _message('Expense saved and linked to Finance transactions.');
                } catch (e) { _message('Unable to save expense: $e'); }
                finally { if (mounted) setState(() => _saving = false); }
              }, icon: const Icon(Icons.check_rounded), label: const Text('Save Expense'), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)))),
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
            const SizedBox(height: 12),
            TextFormField(controller: title, decoration: _decoration('Reminder Title', Icons.notifications_active_outlined), validator: (v) => v == null || v.trim().isEmpty ? 'Enter reminder title' : null),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: InkWell(onTap: () async { final d = await showDatePicker(context: context, initialDate: dueDate, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setSheet(() => dueDate = d); }, child: InputDecorator(decoration: _decoration('Due Date', Icons.calendar_month), child: Text(DateFormat('dd MMM yyyy').format(dueDate), style: const TextStyle(fontSize: 13))))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: dueOdo, keyboardType: TextInputType.number, decoration: _decoration('Due at KM (optional)', Icons.speed_rounded), validator: (v) { if ((v ?? '').trim().isEmpty) return null; final n = double.tryParse(v!); return n == null || !n.isFinite || n <= 0 ? 'Enter valid KM' : null; })),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: notes, maxLines: 2, decoration: _decoration('Notes', Icons.notes_rounded)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheet), child: const Text('Cancel'))),
              const SizedBox(width: 10),
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
              }, icon: const Icon(Icons.check_rounded), label: Text(reminder == null ? 'Save Reminder' : 'Update Reminder'), style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)))),
            ]),
          ]),
        )),
      )),
    );
    title.dispose(); dueOdo.dispose(); notes.dispose();
  }

  Future<void> _deleteRecord(Future<void> Function() action, String label) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Delete $label?'), content: const Text('This will also reverse its linked wallet transaction.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete'))]));
    if (yes != true) return;
    try { await action(); await _load(); _message('$label deleted and wallet balance updated.'); }
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
    padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE8EEEA))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 21), const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink), maxLines: 2, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 3), Text(title, style: const TextStyle(fontSize: 11, color: _muted)),
      if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 10, color: _muted)),
    ]),
  ));

  Widget _empty(String title, String detail, IconData icon) => Center(child: Padding(
    padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: _green.withOpacity(.65)), const SizedBox(height: 12),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
      const SizedBox(height: 5), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12)),
    ]),
  ));

  Widget _dashboard() {
    final due = _dueReminders();
    final distance = _vehicles.fold<double>(0, (sum, v) => sum + _distanceFor(v['id'] as int));
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(12, 14, 12, 100), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_green, Color(0xFF2B9B72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vehicle Overview', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            SizedBox(height: 5), Text('Fuel, mileage and running costs in one place', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          CircleAvatar(radius: 25, backgroundColor: Colors.white24, child: Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 27)),
        ]),
      ),
      const SizedBox(height: 13),
      Row(children: [
        _metric('Vehicles', '${_vehicles.length}', Icons.directions_car_outlined, _green),
        const SizedBox(width: 10), _metric('Distance tracked', '${_amount(distance)} km', Icons.speed_rounded, Colors.blue),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric('Fuel spending', _moneyByCurrency(_fuel, 'total'), Icons.local_gas_station_outlined, Colors.orange),
        const SizedBox(width: 10), _metric('Other expenses', _moneyByCurrency(_expenses, 'amount'), Icons.build_outlined, Colors.red),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric('This month', _monthlySpend(), Icons.calendar_month_outlined, Colors.purple),
        const SizedBox(width: 10), _metric('Due alerts', '${due.length}', Icons.notifications_active_outlined, due.isEmpty ? _green : Colors.red),
      ]),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Reminders & Alerts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
        Text('${due.length} due', style: TextStyle(color: due.isEmpty ? _muted : Colors.red, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
      const SizedBox(height: 8),
      if (due.isEmpty) const Card(child: ListTile(leading: Icon(Icons.check_circle_outline, color: _green), title: Text('No overdue reminders'), subtitle: Text('Your service schedule is up to date.')))
      else ...due.map((r) => Card(child: ListTile(
        leading: const Icon(Icons.notifications_active_outlined, color: Colors.red),
        title: Text(r['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_vehicleName(r['vehicle_id'])} • Due ${_date(r['due_date'])}'),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteRecord(() => VehicleService.deleteReminder(r['id'] as int), 'reminder')),
      ))),
      const SizedBox(height: 14),
      const Text('Your Vehicles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 8),
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
        leading: CircleAvatar(backgroundColor: const Color(0xFFE6F1EC), child: Icon(v['type'] == 'Bike' ? Icons.two_wheeler_rounded : Icons.directions_car_rounded, color: _green)),
        title: Text(v['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
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
            if ((v['notes'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(v['notes'].toString(), style: const TextStyle(color: _muted, fontSize: 12))),
            Row(children: [
              TextButton.icon(onPressed: () => _showVehicleForm(vehicle: v), icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
              TextButton.icon(onPressed: () => _deleteRecord(() async { await VehicleService.deleteVehicle(id); await AttachmentService.deleteOwnerAttachments(ownerType: 'vehicle', ownerId: id); }, 'vehicle'), icon: const Icon(Icons.delete_outline, color: Colors.red), label: const Text('Delete', style: TextStyle(color: Colors.red))),
            ]),
            AttachmentSection(ownerType: 'vehicle', ownerId: id),
          ])),
        ],
      ),
    );
  }

  Widget _smallStat(String title, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFFF4F7F5), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: _muted, fontSize: 10)),
      const SizedBox(height: 2), Text(value, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
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
        leading: const CircleAvatar(backgroundColor: Color(0xFFFFF2DE), child: Icon(Icons.local_gas_station_outlined, color: Colors.orange)),
        title: Text('${_vehicleName(f['vehicle_id'])} • ${_amount(f['total'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${_date(f['date'])} • ${_amount(f['quantity'])} ${f['unit']} • ${_amount(f['odometer'])} km'),
        trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'delete') _deleteRecord(() async { final id = f['id'] as int; await VehicleService.deleteFuel(id); await AttachmentService.deleteOwnerAttachments(ownerType: 'vehicle_fuel', ownerId: id); }, 'fuel entry'); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete Fuel Entry'))]),
        children: [
          ListTile(dense: true, title: const Text('Price per unit'), trailing: Text(_amount(f['unit_price']))),
          ListTile(dense: true, title: const Text('Fuel station'), trailing: Text((f['station'] ?? '—').toString())),
          ListTile(dense: true, title: const Text('Tank fill'), trailing: Text(f['full_tank'] == true ? 'Full tank' : 'Partial')),
          if ((f['notes'] ?? '').toString().isNotEmpty) ListTile(dense: true, title: const Text('Notes'), subtitle: Text(f['notes'].toString())),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: AttachmentSection(ownerType: 'vehicle_fuel', ownerId: f['id'] as int)),
        ],
      ),
    )).toList()));

  Widget _expensesTab() => RefreshIndicator(onRefresh: _load, child: _expenses.isEmpty
    ? _empty('No vehicle expenses', 'Record servicing, repairs, tyres, insurance and other costs.', Icons.build_outlined)
    : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: _expenses.map((e) => Card(
      margin: const EdgeInsets.only(bottom: 9), child: ExpansionTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFFCEBEA), child: Icon(Icons.build_outlined, color: Colors.red)),
        title: Text('${e['category']} • ${_amount(e['amount'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${_vehicleName(e['vehicle_id'])} • ${_date(e['date'])} • ${_amount(e['odometer'])} km'),
        trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'delete') _deleteRecord(() async { final id = e['id'] as int; await VehicleService.deleteExpense(id); await AttachmentService.deleteOwnerAttachments(ownerType: 'vehicle_expense', ownerId: id); }, 'vehicle expense'); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete Expense'))]),
        children: [
          ListTile(dense: true, title: const Text('Paid from'), trailing: Text(_walletName(e['wallet_id']))),
          ListTile(dense: true, title: const Text('Workshop / Vendor'), trailing: Text((e['vendor'] ?? '—').toString())),
          if ((e['notes'] ?? '').toString().isNotEmpty) ListTile(dense: true, title: const Text('Notes'), subtitle: Text(e['notes'].toString())),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: AttachmentSection(ownerType: 'vehicle_expense', ownerId: e['id'] as int)),
        ],
      ),
    )).toList()));

  Widget _remindersTab() => RefreshIndicator(onRefresh: _load, child: _reminders.isEmpty
    ? _empty('No service reminders', 'Create reminders for oil changes, servicing, tyres, insurance and documents.', Icons.notifications_none_rounded)
    : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: _reminders.map((r) {
      final due = DateTime.tryParse(r['due_date']?.toString() ?? '');
      final overdue = due != null && due.isBefore(DateTime.now());
      return Card(margin: const EdgeInsets.only(bottom: 9), child: ListTile(
        leading: Icon(Icons.notifications_active_outlined, color: overdue ? Colors.red : _green),
        title: Text(r['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_vehicleName(r['vehicle_id'])} • ${_date(r['due_date'])}${r['due_odometer'] == null ? '' : ' • ${_amount(r['due_odometer'])} km'}'),
        trailing: PopupMenuButton<String>(onSelected: (v) {
          if (v == 'edit') _showReminderForm(reminder: r);
          if (v == 'delete') _deleteRecord(() => VehicleService.deleteReminder(r['id'] as int), 'reminder');
        }, itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit Reminder')),
          PopupMenuItem(value: 'delete', child: Text('Delete Reminder')),
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
    final reportExpenses = _rangeRows(_expenses);
    final reportReminders = _rangeRows(_reminders);
    final sortedFuel = [...reportFuel]..sort((a,b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
      DropdownButtonFormField<String>(value: _reportRange, decoration: _decoration('Report Period', Icons.date_range_outlined),
        items: const ['Daily', 'Weekly', 'Monthly', 'Yearly', 'All Time'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _reportRange = v ?? 'All Time')),
      const SizedBox(height: 12),
      const Text('Vehicle Comparison', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 8),
      if (_vehicles.isEmpty) _empty('No comparison data', 'Add vehicles and fuel records to compare running costs.', Icons.compare_arrows_rounded)
      else ..._vehicles.map((v) {
        final id = v['id'] as int; final mileage = _averageMileage(id);
        final distance = _distanceFor(id);
        return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _smallStat('Distance', '${_amount(distance)} km'),
            _smallStat('Mileage', mileage == null ? '—' : '${_amount(mileage)} ${_mileageUnit(id)}'),
            _smallStat('Cost / KM', _costPerKm(id)),
            _smallStat('Fuel cost', _vehicleCost(id, fuelOnly: true)),
            _smallStat('Other cost', _vehicleCost(id, fuelOnly: false)),
          ]),
        ])));
      }),
      const SizedBox(height: 14),
      const Text('Fuel Price History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 8),
      if (sortedFuel.isEmpty) const Card(child: ListTile(title: Text('No fuel price history yet.')))
      else ...sortedFuel.take(30).map((f) => Card(child: ListTile(
        dense: true, leading: const Icon(Icons.price_change_outlined, color: Colors.orange),
        title: Text('${_vehicleName(f['vehicle_id'])} • ${_walletCurrency(f['wallet_id'])} ${_amount(f['unit_price'])} / ${f['unit']}'),
        subtitle: Text('${_date(f['date'])} • ${f['station'] ?? 'Station not entered'}'),
        trailing: Text('${_amount(f['quantity'])} ${f['unit']}'),
      ))),
      const SizedBox(height: 16),
      const Text('Export Reports', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 8),
      Card(child: Column(children: [
        ListTile(leading: const Icon(Icons.table_view_rounded, color: _green), title: const Text('Excel Workbook'), subtitle: const Text('Vehicles, fuel log, expenses and reminders'), trailing: const Icon(Icons.download_rounded), onTap: () => _export(true)),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red), title: const Text('PDF Report'), subtitle: const Text('Shareable summary of all vehicle records'), trailing: const Icon(Icons.download_rounded), onTap: () => _export(false)),
      ])),
      const SizedBox(height: 8),
      const Text('Reports are saved in the app documents folder and opened with a compatible app.', style: TextStyle(color: _muted, fontSize: 11)),
    ]);
  }

  String _fabLabel() => switch (_tabs.index) {
    1 => 'Add Vehicle', 2 => 'Add Fuel', 3 => 'Add Expense', 4 => 'Add Reminder', _ => 'Add Vehicle',
  };
  VoidCallback _fabAction() => switch (_tabs.index) {
    2 => _showFuelForm, 3 => _showExpenseForm, 4 => _showReminderForm, _ => _showVehicleForm,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white, foregroundColor: _ink, elevation: 0,
        titleSpacing: 16, toolbarHeight: 56,
        title: const Text('Vehicle Manager', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
        actions: buildSharedAppBarActions(context),
        bottom: TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start,
          labelColor: _green, unselectedLabelColor: _muted, indicatorColor: _green,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined, size: 18)),
            Tab(text: 'Vehicles', icon: Icon(Icons.directions_car_outlined, size: 18)),
            Tab(text: 'Fuel Log', icon: Icon(Icons.local_gas_station_outlined, size: 18)),
            Tab(text: 'Expenses', icon: Icon(Icons.build_outlined, size: 18)),
            Tab(text: 'Reminders', icon: Icon(Icons.notifications_none, size: 18)),
            Tab(text: 'Reports', icon: Icon(Icons.analytics_outlined, size: 18)),
          ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _fabAction(), backgroundColor: _green, foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded), label: Text(_fabLabel()),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabs, children: [
        _dashboard(), _vehiclesTab(), _fuelTab(), _expensesTab(), _remindersTab(), _reportsTab(),
      ]),
    );
  }
}
