import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/features/staff/services/staff_service.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<Map<String, dynamic>> _staff = [], _salaries = [], _attendance = [], _wallets = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  String tr(String value) => appText(context, value, value);
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await StaffService.ensureTables();
      final values = await Future.wait([
        StaffService.getStaff(), StaffService.getSalaries(),
        StaffService.getAttendance(), FinanceDB.instance.getWallets(),
      ]);
      if (!mounted) return;
      setState(() { _staff = values[0]; _salaries = values[1]; _attendance = values[2]; _wallets = values[3]; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _message(e.toString());
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _form({Map<String, dynamic>? member}) async {
    final key = GlobalKey<FormState>();
    final name = TextEditingController(text: member?['name']?.toString() ?? '');
    final phone = TextEditingController(text: member?['phone']?.toString() ?? '');
    final role = TextEditingController(text: member?['role']?.toString() ?? '');
    final salary = TextEditingController(text: member?['salary']?.toString() ?? '');
    final notes = TextEditingController(text: member?['notes']?.toString() ?? '');
    DateTime joined = DateTime.tryParse(member?['joined_at']?.toString() ?? '') ?? DateTime.now();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent, builder: (sheet) => StatefulBuilder(builder: (context, refresh) {
        return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(height: MediaQuery.of(context).size.height * .88,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(children: [
              const SizedBox(height: 12), Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.muted.withOpacity(.4), borderRadius: BorderRadius.circular(8))),
              Padding(padding: const EdgeInsets.all(18), child: Row(children: [Expanded(child: Text(member == null ? tr('Add Staff') : tr('Edit Staff'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))), IconButton(onPressed: () => Navigator.pop(sheet), icon: const Icon(Icons.close))])),
              Expanded(child: Form(key: key, child: ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 22), children: [
                _field(name, 'Staff Name', Icons.person_outline, requiredField: true),
                const SizedBox(height: 12), _field(phone, 'Phone', Icons.phone_outlined, keyboard: TextInputType.phone),
                const SizedBox(height: 12), _field(role, 'Job Title', Icons.work_outline),
                const SizedBox(height: 12), _field(salary, 'Monthly Salary', Icons.payments_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 12), ListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Joining Date')), subtitle: Text(DateFormat.yMMMd().format(joined)), trailing: const Icon(Icons.calendar_month), onTap: () async { final d = await showDatePicker(context: context, initialDate: joined, firstDate: DateTime(1990), lastDate: DateTime(2100)); if (d != null) refresh(() => joined = d); }),
                const SizedBox(height: 12), _field(notes, 'Notes', Icons.notes_outlined, maxLines: 3),
                const SizedBox(height: 20), FilledButton(onPressed: () async {
                  if (!key.currentState!.validate()) return;
                  try { await StaffService.saveStaff(id: member?['id'] as int?, name: name.text, phone: phone.text, role: role.text, salary: double.tryParse(salary.text) ?? 0, joinedAt: joined, notes: notes.text); if (sheet.mounted) Navigator.pop(sheet); await _load(); }
                  catch (e) { _message(e.toString()); }
                }, child: Text(tr('Save Staff'))),
              ]))),
            ]),
          ),
        );
      }));
    name.dispose(); phone.dispose(); role.dispose(); salary.dispose(); notes.dispose();
  }

  Widget _field(TextEditingController c, String label, IconData icon, {bool requiredField = false, TextInputType? keyboard, int maxLines = 1}) =>
    TextFormField(controller: c, keyboardType: keyboard, maxLines: maxLines,
      validator: requiredField ? (v) => (v == null || v.trim().isEmpty) ? tr('Required') : null : null,
      decoration: InputDecoration(labelText: tr(label), prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(13))));

  Future<void> _salaryForm() async {
    if (_staff.isEmpty || _wallets.isEmpty) { _message(_staff.isEmpty ? tr('Add staff first.') : tr('Add a wallet first.')); return; }
    int staffId = _staff.first['id'] as int, walletId = _wallets.first['id'] as int;
    final amount = TextEditingController(text: (_staff.first['salary'] ?? '').toString());
    final note = TextEditingController();
    DateTime date = DateTime.now();
    final key = GlobalKey<FormState>();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (sheet) => StatefulBuilder(builder: (context, refresh) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(height: MediaQuery.of(context).size.height * .82, padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: Form(key: key, child: ListView(children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.muted.withOpacity(.4), borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 18), Text(tr('Pay Salary'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18), DropdownButtonFormField<int>(value: staffId, decoration: InputDecoration(labelText: tr('Staff Member'), border: const OutlineInputBorder()), items: _staff.map((s) => DropdownMenuItem(value: s['id'] as int, child: Text(s['name'].toString()))).toList(), onChanged: (v) { if (v != null) refresh(() { staffId = v; amount.text = _staff.firstWhere((s) => s['id'] == v)['salary'].toString(); }); }),
            const SizedBox(height: 12), TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? tr('Enter a valid amount') : null, decoration: InputDecoration(labelText: tr('Amount'), prefixIcon: const Icon(Icons.payments_outlined), border: const OutlineInputBorder())),
            const SizedBox(height: 12), DropdownButtonFormField<int>(value: walletId, decoration: InputDecoration(labelText: tr('Wallet'), border: const OutlineInputBorder()), items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text(w['name'].toString()))).toList(), onChanged: (v) { if (v != null) refresh(() => walletId = v); }),
            const SizedBox(height: 8), ListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Payment Date')), subtitle: Text(DateFormat.yMMMd().format(date)), trailing: const Icon(Icons.calendar_month), onTap: () async { final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) refresh(() => date = d); }),
            const SizedBox(height: 8), TextFormField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: tr('Notes (optional)'), border: const OutlineInputBorder())),
            const SizedBox(height: 20), FilledButton(onPressed: () async { if (!key.currentState!.validate()) return; try { await StaffService.paySalary(staffId: staffId, amount: double.parse(amount.text), walletId: walletId, date: date, note: note.text); if (sheet.mounted) Navigator.pop(sheet); await _load(); } catch (e) { _message(e.toString()); } }, child: Text(tr('Save Salary Payment'))),
          ])),
        ),
      )));
    amount.dispose(); note.dispose();
  }

  Future<void> _attendanceForm() async {
    if (_staff.isEmpty) { _message(tr('Add staff first.')); return; }
    int staffId = _staff.first['id'] as int; String status = 'Present'; DateTime date = DateTime.now();
    final note = TextEditingController();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (sheet) => StatefulBuilder(builder: (context, refresh) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(height: MediaQuery.of(context).size.height * .72, padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: ListView(children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.muted.withOpacity(.4), borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 18), Text(tr('Mark Attendance'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18), DropdownButtonFormField<int>(value: staffId, decoration: InputDecoration(labelText: tr('Staff Member'), border: const OutlineInputBorder()), items: _staff.map((s) => DropdownMenuItem(value: s['id'] as int, child: Text(s['name'].toString()))).toList(), onChanged: (v) { if (v != null) refresh(() => staffId = v); }),
            const SizedBox(height: 12), DropdownButtonFormField<String>(value: status, decoration: InputDecoration(labelText: tr('Status'), border: const OutlineInputBorder()), items: ['Present','Absent','Late','Leave','Half Day'].map((s) => DropdownMenuItem(value: s, child: Text(tr(s)))).toList(), onChanged: (v) { if (v != null) refresh(() => status = v); }),
            const SizedBox(height: 8), ListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Date')), subtitle: Text(DateFormat.yMMMd().format(date)), trailing: const Icon(Icons.calendar_month), onTap: () async { final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) refresh(() => date = d); }),
            TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: tr('Notes (optional)'), border: const OutlineInputBorder())),
            const SizedBox(height: 20), FilledButton(onPressed: () async { try { await StaffService.saveAttendance(staffId: staffId, date: date, status: status, note: note.text); if (sheet.mounted) Navigator.pop(sheet); await _load(); } catch (e) { _message(e.toString()); } }, child: Text(tr('Save Attendance'))),
          ]),
        ),
      )));
    note.dispose();
  }

  String _staffName(int id) { final rows = _staff.where((s) => s['id'] == id).toList(); return rows.isEmpty ? tr('Staff member') : rows.first['name'].toString(); }
  Widget _empty(String label) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(tr(label), textAlign: TextAlign.center)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Staff Management')), bottom: TabBar(controller: _tabs, tabs: [Tab(text: tr('Staff')), Tab(text: tr('Salary')), Tab(text: tr('Attendance'))])),
    floatingActionButton: FloatingActionButton.extended(onPressed: () { if (_tabs.index == 0) { _form(); } else if (_tabs.index == 1) { _salaryForm(); } else { _attendanceForm(); } }, icon: const Icon(Icons.add), label: Text(_tabs.index == 0 ? tr('Add Staff') : _tabs.index == 1 ? tr('Pay Salary') : tr('Mark Attendance'))),
    body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabs, children: [
      _staff.isEmpty ? _empty('No staff added yet') : ListView.builder(padding: const EdgeInsets.only(bottom: 90), itemCount: _staff.length, itemBuilder: (context, i) { final s = _staff[i]; return Card(margin: const EdgeInsets.fromLTRB(12, 6, 12, 4), child: ListTile(leading: CircleAvatar(child: Text(s['name'].toString().isEmpty ? '?' : s['name'].toString()[0].toUpperCase())), title: Text(s['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text([s['role'], s['phone']].where((v) => v != null && v.toString().isNotEmpty).join(' • ')), trailing: PopupMenuButton<String>(onSelected: (v) async { if (v == 'edit') await _form(member: s); if (v == 'delete') { await StaffService.deleteStaff(s['id'] as int); await _load(); } }, itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(tr('Edit'))), PopupMenuItem(value: 'delete', child: Text(tr('Delete')))]))); }),
      _salaries.isEmpty ? _empty('No salary payments yet') : ListView.builder(padding: const EdgeInsets.only(bottom: 90), itemCount: _salaries.length, itemBuilder: (context, i) { final s = _salaries[i]; return ListTile(leading: const CircleAvatar(child: Icon(Icons.payments_outlined)), title: Text(_staffName(s['staff_id'] as int)), subtitle: Text(DateFormat.yMMMd().format(DateTime.parse(s['paid_at'].toString()))), trailing: Text(s['amount'].toString())); }),
      _attendance.isEmpty ? _empty('No attendance records yet') : ListView.builder(padding: const EdgeInsets.only(bottom: 90), itemCount: _attendance.length, itemBuilder: (context, i) { final a = _attendance[i]; return ListTile(leading: const CircleAvatar(child: Icon(Icons.event_available_outlined)), title: Text(_staffName(a['staff_id'] as int)), subtitle: Text(DateFormat.yMMMd().format(DateTime.parse(a['attendance_date'].toString()))), trailing: Chip(label: Text(tr(a['status'].toString())))); }),
    ]),
  );
}
