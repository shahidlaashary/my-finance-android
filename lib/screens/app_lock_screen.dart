import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _loading = true;
  bool _enabled = false;
  bool _biometric = false;
  bool _biometricAvailable = false;
  int _timeout = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      AppLockService.isEnabled(),
      AppLockService.biometricEnabled(),
      AppLockService.isBiometricAvailable(),
      AppLockService.autoLockSeconds(),
    ]);
    if (!mounted) return;
    setState(() {
      _enabled = values[0] as bool;
      _biometric = values[1] as bool;
      _biometricAvailable = values[2] as bool;
      final savedTimeout = values[3] as int;
      _timeout = [0, 30, 60, 300].contains(savedTimeout) ? savedTimeout : 0;
      _loading = false;
    });
  }

  Future<String?> _askForPin({bool confirm = false}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(confirm ? 'Create App PIN' : 'Change App PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'New PIN (4–8 digits)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: second,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  counterText: '',
                ),
                onSubmitted: (_) {
                  if (!RegExp(r'^\d{4,8}$').hasMatch(first.text)) {
                    setDialogState(() => error = 'Enter 4 to 8 digits.');
                  } else if (first.text != second.text) {
                    setDialogState(() => error = 'PINs do not match.');
                  } else {
                    Navigator.pop(dialogContext, first.text);
                  }
                },
              ),
              if (error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!RegExp(r'^\d{4,8}$').hasMatch(first.text)) {
                  setDialogState(() => error = 'Enter 4 to 8 digits.');
                } else if (first.text != second.text) {
                  setDialogState(() => error = 'PINs do not match.');
                } else {
                  Navigator.pop(dialogContext, first.text);
                }
              },
              child: const Text('Save PIN'),
            ),
          ],
        ),
      ),
    );

    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _enableLock() async {
    final hasPin = await AppLockService.hasPin();
    if (!hasPin) {
      final pin = await _askForPin(confirm: true);
      if (pin == null) return;
      await AppLockService.setPin(pin);
    }
    await AppLockService.setEnabled(true);
    if (!mounted) return;
    setState(() => _enabled = true);
    _message('App Lock enabled.');
  }

  Future<void> _changePin() async {
    final pin = await _askForPin();
    if (pin == null) return;
    await AppLockService.setPin(pin);
    _message('App PIN updated successfully.');
  }

  Future<void> _setBiometric(bool value) async {
    if (value && !_biometricAvailable) {
      _message('No supported biometric authentication is available on this device.');
      return;
    }
    if (value) {
      final authenticated = await AppLockService.authenticateBiometric();
      if (!authenticated) {
        _message('Biometric verification was not completed.');
        return;
      }
    }
    await AppLockService.setBiometricEnabled(value);
    if (!mounted) return;
    setState(() => _biometric = value);
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('App Lock & Security')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Lock & Security',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_moon_rounded, size: 34),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Protect Your Finance Data',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      SizedBox(height: 5),
                      Text('Use a private PIN or your device biometrics to lock the app.',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.lock_outline_rounded),
              title: const Text('App Lock'),
              subtitle: const Text('Require authentication when opening My Finance'),
              value: _enabled,
              onChanged: _saving ? null : (value) async {
                setState(() => _saving = true);
                try {
                  if (value) {
                    await _enableLock();
                  } else {
                    await AppLockService.setEnabled(false);
                    if (mounted) setState(() => _enabled = false);
                  }
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('Change PIN'),
              subtitle: const Text('Update your secure app PIN'),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: awaitPinEnabled,
              onTap: _changePin,
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Biometric Unlock'),
              subtitle: Text(_biometricAvailable
                  ? 'Use fingerprint or face authentication when supported'
                  : 'No supported biometric sensor found on this device'),
              value: _biometric,
              onChanged: _enabled && _biometricAvailable
                  ? _setBiometric
                  : null,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Auto-lock timeout'),
              subtitle: const Text('Lock again after leaving the app'),
              trailing: DropdownButton<int>(
                value: _timeout,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Immediately')),
                  DropdownMenuItem(value: 30, child: Text('30 seconds')),
                  DropdownMenuItem(value: 60, child: Text('1 minute')),
                  DropdownMenuItem(value: 300, child: Text('5 minutes')),
                ],
                onChanged: _enabled ? (value) async {
                  if (value == null) return;
                  await AppLockService.setAutoLockSeconds(value);
                  if (mounted) setState(() => _timeout = value);
                } : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your PIN is stored as a salted hash in secure device storage. '
            'Biometric availability depends on your phone and its security settings.',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }

  bool get awaitPinEnabled => _enabled;
}
