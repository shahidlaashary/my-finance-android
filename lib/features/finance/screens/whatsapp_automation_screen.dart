import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:my_finance/core/theme/app_colors.dart';

class WhatsAppAutomationScreen extends StatefulWidget {
  const WhatsAppAutomationScreen({super.key});

  @override
  State<WhatsAppAutomationScreen> createState() =>
      _WhatsAppAutomationScreenState();
}

class _WhatsAppAutomationScreenState extends State<WhatsAppAutomationScreen> {
  static const _enabledKey = 'wa_auto_reminders_enabled';
  static const _beforeKey = 'wa_reminder_before_due';
  static const _dueKey = 'wa_reminder_on_due';
  static const _overdueKey = 'wa_reminder_after_due';
  static const _paymentKey = 'wa_payment_confirmation';
  static const _phoneKey = 'wa_pending_phone_number';

  bool _loading = true;
  bool _enabled = false;
  bool _beforeDue = true;
  bool _onDue = true;
  bool _afterDue = true;
  bool _paymentConfirmation = false;
  String _phoneNumber = '';
  bool _connected = false; // Set true only after successful Meta backend verification.

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enabled = _connected && (prefs.getBool(_enabledKey) ?? false);
      _beforeDue = prefs.getBool(_beforeKey) ?? true;
      _onDue = prefs.getBool(_dueKey) ?? true;
      _afterDue = prefs.getBool(_overdueKey) ?? true;
      _paymentConfirmation = prefs.getBool(_paymentKey) ?? false;
      _phoneNumber = prefs.getString(_phoneKey) ?? '';
      _loading = false;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _showConnectNumberDialog() async {
    final controller = TextEditingController(text: _phoneNumber);
    final number = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Connect WhatsApp'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'WhatsApp number',
            hintText: '+92 300 1234567',
            prefixIcon: Icon(Icons.phone_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
              if (digits.length < 10 || digits.length > 15) return;
              Navigator.pop(dialogContext, value);
            },
            child: Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (number == null || number.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, number.trim());
    if (!mounted) return;
    setState(() => _phoneNumber = number.trim());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Verification setup required'),
        content: Text(
          'Your number has been saved as pending. The official Meta verification service is not connected yet, so an OTP or WhatsApp connection cannot be started from this app build. Your number will not be marked Connected until Meta confirms it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualSendDialog() async {
    final phoneController = TextEditingController();
    final messageController = TextEditingController(
      text: 'Assalam-o-Alaikum, aapki payment reminder hai. Meharbani farma kar apni outstanding payment clear kar dein. Shukriya!',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Send WhatsApp Reminder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Party WhatsApp number',
                  hintText: '923001234567',
                  helperText: 'Country code ke sath number likhein',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(Icons.open_in_new_rounded),
            label: Text('Open WhatsApp'),
          ),
        ],
      ),
    );
    if (result == true) {
      final digits = phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final message = messageController.text.trim();
      if (digits.length < 10 || digits.length > 15 || message.isEmpty) {
        _showMessage('Valid party number aur message enter karein.');
      } else {
        final uri = Uri.https('wa.me', '/$digits', {'text': message});
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) _showMessage('WhatsApp open nahi ho saka. WhatsApp install/check karein.');
      }
    }
    phoneController.dispose();
    messageController.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      );

  Widget _toggle({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        value: value,
        onChanged: _enabled && _connected
            ? (next) {
                setState(() => onChanged(next));
              }
            : null,
        secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WhatsApp Automation',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF128C55), Color(0xFF075E42)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.chat_rounded, color: Colors.white, size: 27),
                          SizedBox(width: 9),
                          Expanded(
                            child: Text('Automatic Party Reminders',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                      SizedBox(height: 9),
                      Text(
                        'Due payments, overdue reminders aur payment confirmations WhatsApp par bhejne ka control.',
                        style: TextStyle(
                            color: Colors.white, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
                _sectionTitle('WhatsApp Connection'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _connected ? Icons.check_circle_rounded : Icons.link_rounded,
                              color: _connected ? Colors.green : Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _connected ? 'Connected' : (_phoneNumber.isEmpty ? 'Not connected' : 'Number saved — verification pending'),
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                            ),
                            Chip(
                              label: Text(_connected ? 'Connected' : 'Not connected',
                                  style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        if (_phoneNumber.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('WhatsApp number: $_phoneNumber',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _connected
                              ? 'Your WhatsApp number is ready for automatic reminders.'
                              : 'Connect your own WhatsApp number. Number verification will be completed securely through Meta.',
                          style: TextStyle(fontSize: 12, height: 1.45),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _connected ? null : _showConnectNumberDialog,
                            icon: Icon(_phoneNumber.isEmpty ? Icons.message_rounded : Icons.verified_user_outlined),
                            label: Text(_phoneNumber.isEmpty ? 'Connect WhatsApp' : 'Verify Number'),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Real verification and sending require the secure Meta connection service. This screen will not mark a number as connected until the backend confirms it.',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
                _sectionTitle('Automation'),
                Card(
                  child: SwitchListTile(
                    value: _enabled,
                    onChanged: _connected ? (value) async {
                      setState(() => _enabled = value);
                      await _save(_enabledKey, value);
                    } : null,
                    secondary: Icon(Icons.auto_awesome,
                        color: Theme.of(context).colorScheme.primary),
                    title: Text('Enable Auto Reminders',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        _connected ? 'Automatic reminders are available.' : 'Connect and verify WhatsApp first.',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                _toggle(
                  title: 'Before Due Date',
                  subtitle: 'Send reminder 3 days before payment is due',
                  icon: Icons.notifications_active_outlined,
                  value: _beforeDue,
                  onChanged: (v) {
                    _beforeDue = v;
                    _save(_beforeKey, v);
                  },
                ),
                _toggle(
                  title: 'On Due Date',
                  subtitle: 'Send reminder on the payment due date',
                  icon: Icons.event_available_outlined,
                  value: _onDue,
                  onChanged: (v) {
                    _onDue = v;
                    _save(_dueKey, v);
                  },
                ),
                _toggle(
                  title: 'Overdue Reminder',
                  subtitle: 'Send reminder 3 days after the due date',
                  icon: Icons.warning_amber_rounded,
                  value: _afterDue,
                  onChanged: (v) {
                    _afterDue = v;
                    _save(_overdueKey, v);
                  },
                ),
                _toggle(
                  title: 'Payment Confirmation',
                  subtitle: 'Send a message when a party payment is recorded',
                  icon: Icons.task_alt_rounded,
                  value: _paymentConfirmation,
                  onChanged: (v) {
                    _paymentConfirmation = v;
                    _save(_paymentKey, v);
                  },
                ),
                _sectionTitle('Message Preview'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payment due reminder',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(
                          'Assalam-o-Alaikum {Party Name}, aapki {Currency} {Outstanding Amount} payment {Due Date} ko due hai. Meharbani farma kar payment clear kar dein. Shukriya!',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Placeholders actual party aur loan details se automatically replace honge.',
                          style: TextStyle(
                              fontSize: 11, color: Theme.of(context).hintColor),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _showManualSendDialog,
                            icon: Icon(Icons.send_rounded),
                            label: Text('Send Reminder on WhatsApp'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'WhatsApp mein message khulega. Aap review karke khud Send press karein.',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
