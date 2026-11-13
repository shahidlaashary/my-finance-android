import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'package:my_finance/core/security/app_lock_service.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _loading = true;
  bool _enabled = false;
  bool _hasPin = false;
  int _timeout = 0;
  bool _biometricEnabled = false;
  List<BiometricType> _availableBiometrics = [];
  bool _saving = false;

  String get _biometricMethods {
    final methods = <String>[];
    if (_availableBiometrics.contains(BiometricType.face)) methods.add('Face');
    if (_availableBiometrics.contains(BiometricType.fingerprint)) methods.add('Fingerprint');
    if (methods.isEmpty && _availableBiometrics.isNotEmpty) return 'Device biometrics';
    return methods.isEmpty ? 'No enrolled biometrics detected' : methods.join(' & ');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        AppLockService.isEnabled(),
        AppLockService.hasPin(),
        AppLockService.autoLockSeconds(),
        AppLockService.isBiometricEnabled(),
        AppLockService.availableBiometrics(),
      ]);
      if (!mounted) return;
      setState(() {
        _enabled = values[0] as bool;
        _hasPin = values[1] as bool;
        _timeout = values[2] as int;
        _biometricEnabled = values[3] as bool;
        _availableBiometrics = values[4] as List<BiometricType>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Unable to load App Lock settings: $error');
    }
  }

  Future<String?> _askForPin({bool confirm = false}) async {
    final current = TextEditingController();
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(confirm ? 'Create App PIN' : 'Change App PIN'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!confirm) ...[
                    TextField(
                      controller: current,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      decoration: const InputDecoration(
                        labelText: 'Current PIN',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: first,
                    autofocus: confirm,
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
                  ),
                  if (error != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!confirm &&
                      !await AppLockService.verifyPin(current.text)) {
                    setDialogState(() => error = 'Current PIN is incorrect.');
                    return;
                  }
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
    } finally {
      current.dispose();
      first.dispose();
      second.dispose();
    }
  }

  Future<void> _enableLock() async {
    if (!_hasPin) {
      final pin = await _askForPin(confirm: true);
      if (pin == null) return;
      await AppLockService.setPin(pin);
      if (mounted) setState(() => _hasPin = true);
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
    if (!mounted) return;
    _message('App PIN updated successfully.');
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Future<void> _setEnabled(bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (value) {
        await _enableLock();
      } else {
        await AppLockService.setBiometricEnabled(false);
        await AppLockService.setEnabled(false);
        if (mounted) {
          setState(() {
            _enabled = false;
            _biometricEnabled = false;
          });
          _message('App Lock disabled.');
        }
      }
    } catch (error) {
      _message('Unable to update App Lock: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setBiometricEnabled(bool value) async {
    if (_saving) return;
    if (value && (!_enabled || !_hasPin)) {
      _message('Enable App Lock and create a PIN first.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (value) {
        // Refresh the enrolled methods in case the user changed device
        // biometrics since this settings page was opened.
        final available = await AppLockService.availableBiometrics();
        if (!mounted) return;
        setState(() => _availableBiometrics = available);

        if (available.isEmpty) {
          _message('Set up Face Unlock or Fingerprint in your device settings first.');
          return;
        }

        // Verify that the system prompt can actually authenticate before
        // saving the combined biometric-unlock preference.
        final authenticated = await AppLockService.authenticateBiometric();
        if (!mounted) return;
        if (!authenticated) {
          _message('Biometric verification was not completed. The setting was not enabled.');
          return;
        }
      }

      await AppLockService.setBiometricEnabled(value);
      if (!mounted) return;
      setState(() => _biometricEnabled = value);
      _message(
        value
            ? 'Face / Fingerprint Unlock enabled. Your PIN remains as backup.'
            : 'Biometric unlock disabled.',
      );
    } catch (error) {
      _message('Unable to update biometric setting: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setTimeout(int? value) async {
    if (value == null || !_enabled) return;
    try {
      await AppLockService.setAutoLockSeconds(value);
      if (mounted) setState(() => _timeout = value);
    } catch (error) {
      _message('Unable to update timeout: $error');
    }
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
        title: const Text(
          'App Lock & Security',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
                      Text(
                        'Protect Your Finance Data',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Use your PIN or your phone’s secure Face / Fingerprint authentication to protect the app.',
                        style: TextStyle(fontSize: 12),
                      ),
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
              subtitle: const Text(
                'Require your PIN or enabled biometrics when opening My Finance',
              ),
              value: _enabled,
              onChanged: _saving ? null : _setEnabled,
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Face / Fingerprint Unlock'),
              subtitle: Text(
                _biometricMethods == 'No enrolled biometrics detected'
                    ? 'Set up Face Unlock or Fingerprint on this device first.'
                    : 'Android will use an enrolled secure biometric ($_biometricMethods). PIN remains available as backup.',
              ),
              value: _biometricEnabled,
              onChanged: _enabled && !_saving ? _setBiometricEnabled : null,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('Change PIN'),
              subtitle: const Text('Update your secure app PIN'),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: _hasPin && !_saving,
              onTap: _changePin,
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
                onChanged: _enabled && !_saving ? _setTimeout : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your PIN is stored as a salted hash in secure device storage. '
            'Biometric unlock uses the security system built into your device; '
            'your PIN remains available as a backup.',
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
