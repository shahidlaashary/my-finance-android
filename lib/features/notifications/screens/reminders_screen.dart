import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/features/notifications/services/reminder_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _service = ReminderService.instance;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _service.initialize();
      final items = await _service.getReminders();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Reminders load nahi ho sake: $error');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _addReminder() async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final note = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(hours: 1));
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);
    String category = 'Personal';
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18, 18, 18, MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New Reminder',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Reminder title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Title is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(
                      labelText: 'Reminder type',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['Personal', 'Bill payment', 'Loan payment',
                      'Budget review', 'Savings goal']
                        .map((value) => DropdownMenuItem(
                          value: value, child: Text(value),
                        )).toList(),
                    onChanged: (value) {
                      if (value != null) setSheetState(() => category = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Date'),
                    subtitle: Text(DateFormat('EEE, dd MMM yyyy').format(selectedDate)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setSheetState(() => selectedDate = DateTime(
                        picked.year, picked.month, picked.day,
                        selectedTime.hour, selectedTime.minute,
                      ));
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: const Text('Time'),
                    subtitle: Text(selectedTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context, initialTime: selectedTime,
                      );
                      if (picked != null) setSheetState(() {
                        selectedTime = picked;
                        selectedDate = DateTime(selectedDate.year, selectedDate.month,
                          selectedDate.day, picked.hour, picked.minute);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Schedule Reminder'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (result != true) {
      title.dispose();
      note.dispose();
      return;
    }
    final when = DateTime(selectedDate.year, selectedDate.month, selectedDate.day,
      selectedTime.hour, selectedTime.minute);
    setState(() => _saving = true);
    try {
      await _service.addReminder(
        title: title.text,
        note: note.text,
        when: when,
        category: category,
      );
      await _load();
      _message('Reminder scheduled successfully.');
    } catch (error) {
      _message('Reminder schedule nahi ho saka: $error');
    } finally {
      title.dispose();
      note.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    await _service.deleteReminder((item['id'] as num).toInt());
    await _load();
    _message('Reminder removed.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications & Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addReminder,
        icon: _saving
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_alert),
        label: const Text('Add Reminder'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 100),
                      Icon(Icons.notifications_none, size: 58, color: Colors.grey),
                      SizedBox(height: 12),
                      Center(child: Text('No reminders scheduled yet.')),
                      SizedBox(height: 8),
                      Center(child: Text('Add a reminder for bills, loans or savings goals.')),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final when = DateTime.parse(item['when'] as String).toLocal();
                        final past = !when.isAfter(DateTime.now());
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(past ? Icons.history : Icons.notifications_active_outlined),
                            ),
                            title: Text(item['title'] as String,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${item['category']} • ${DateFormat('dd MMM yyyy, hh:mm a').format(when)}'
                              '${(item['note'] as String).isEmpty ? '' : '\n${item['note']}'}',
                            ),
                            isThreeLine: (item['note'] as String).isNotEmpty,
                            trailing: IconButton(
                              tooltip: 'Delete reminder',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(item),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
