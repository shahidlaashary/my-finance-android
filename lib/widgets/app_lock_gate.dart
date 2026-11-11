import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _enabled = false;
  bool _locked = false;
  bool _biometricEnabled = false;
  bool _showPin = false;
  bool _authenticating = false;
  String? _error;
  DateTime? _pausedAt;
  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockService.revision.addListener(_reloadSettings);
    _loadSettings(initial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppLockService.revision.removeListener(_reloadSettings);
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _reloadSettings() => _loadSettings();

  Future<void> _loadSettings({bool initial = false}) async {
    try {
      final enabled = await AppLockService.isEnabled();
      final hasPin = await AppLockService.hasPin();
      final biometric = await AppLockService.biometricEnabled();
      final biometricAvailable = await AppLockService.isBiometricAvailable();
      if (!mounted) return;

      setState(() {
        _enabled = enabled && hasPin;
        _biometricEnabled = biometric && biometricAvailable;
        if (!_enabled) {
          _locked = false;
        } else if (initial || !_loading && !_enabled) {
          _locked = true;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _locked = false;
        _loading = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _enabled) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt == null) return;
      AppLockService.autoLockSeconds().then((seconds) {
        if (!mounted || !_enabled) return;
        if (seconds == 0 ||
            DateTime.now().difference(pausedAt).inSeconds >= seconds) {
          setState(() {
            _locked = true;
            _showPin = false;
            _pinController.clear();
            _error = null;
          });
        }
      });
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final success = await AppLockService.authenticateBiometric();
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      if (success) _locked = false;
    });
  }

  Future<void> _unlockWithPin() async {
    final success = await AppLockService.verifyPin(_pinController.text);
    if (!mounted) return;
    setState(() {
      if (success) {
        _locked = false;
        _pinController.clear();
        _error = null;
      } else {
        _error = 'Incorrect PIN. Please try again.';
        _pinController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Material(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_locked && _enabled)
          Positioned.fill(
            child: Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Icon(Icons.lock_rounded, size: 42, color: primary),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'My Finance is Locked',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Authenticate to securely access your financial data.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 26),
                  if (_biometricEnabled)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _authenticating ? null : _unlockWithBiometrics,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: Text(_authenticating
                            ? 'Authenticating...'
                            : 'Unlock with Biometrics'),
                      ),
                    ),
                  if (_biometricEnabled) const SizedBox(height: 12),
                  if (!_showPin)
                    TextButton(
                      onPressed: () => setState(() => _showPin = true),
                      child: const Text('Use PIN instead'),
                    ),
                  if (_showPin || !_biometricEnabled) ...[
                    TextField(
                      controller: _pinController,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      onSubmitted: (_) => _unlockWithPin(),
                      decoration: InputDecoration(
                        labelText: 'Enter your PIN',
                        errorText: _error,
                        counterText: '',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.password_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _unlockWithPin,
                        child: const Text('Unlock'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
      ],
    );
  }
}
