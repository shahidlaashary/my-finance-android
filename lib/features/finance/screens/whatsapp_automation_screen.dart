import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  bool _loading = true;
  bool _enabled = false;
  bool _beforeDue = true;
  bool _onDue = true;
  bool _afterDue = true;
  bool _paymentConfirmation = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _beforeDue = prefs.getBool(_beforeKey) ?? true;
      _onDue = prefs.getBool(_dueKey) ?? true;
      _afterDue = prefs.getBool(_overdueKey) ?? true;
      _paymentConfirmation = prefs.getBool(_paymentKey) ?? false;
      _loading = false;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
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
        onChanged: _enabled
            ? (next) {
                setState(() => onChanged(next));
              }
            : null,
        secondary: Icon(icon, color: AppColors.primary),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Automation',
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
                        const Row(
                          children: [
                            Icon(Icons.link_off_rounded,
                                color: Color(0xFFB7791F)),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text('Not connected',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ),
                            Chip(
                              label: Text('Setup required',
                                  style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your existing WhatsApp Business number will be connected through Meta Cloud API Coexistence. A secure backend, Meta onboarding and approved message templates are required before automatic sending can start.',
                          style: TextStyle(fontSize: 12, height: 1.45),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'No number migration or messages will be initiated from this screen.',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                _sectionTitle('Automation'),
                Card(
                  child: SwitchListTile(
                    value: _enabled,
                    onChanged: (value) async {
                      setState(() => _enabled = value);
                      await _save(_enabledKey, value);
                    },
                    secondary: const Icon(Icons.auto_awesome,
                        color: AppColors.primary),
                    title: const Text('Enable Auto Reminders',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text(
                        'Will activate after WhatsApp connection is completed.',
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
                        const Text('Payment due reminder',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        const Text(
                          'Assalam-o-Alaikum {Party Name}, aapki {Currency} {Outstanding Amount} payment {Due Date} ko due hai. Meharbani farma kar payment clear kar dein. Shukriya!',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Placeholders actual party aur loan details se automatically replace honge.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.muted),
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
