import 'package:flutter/material.dart';

import 'package:my_finance/core/security/app_lock_service.dart';

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
  bool _checkingPin = false;
  bool _showPin = false;
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
      if (!mounted) return;

      setState(() {
        final wasEnabled = _enabled;
        _enabled = enabled;
        if (!enabled) {
          _locked = false;
          _pinController.clear();
          _error = null;
        } else if (initial || !wasEnabled) {
          _locked = true;
          _showPin = false;
          _pinController.clear();
          _error = null;
        }
        _loading = false;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app lock startup',
          context: ErrorDescription('while loading App Lock settings'),
        ),
      );
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
      if (pausedAt != null) _checkAutoLock(pausedAt);
    }
  }

  Future<void> _checkAutoLock(DateTime pausedAt) async {
    try {
      final seconds = await AppLockService.autoLockSeconds();
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
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app lock lifecycle',
          context: ErrorDescription('while checking auto-lock timeout'),
        ),
      );
    }
  }

  Future<void> _unlockWithPin() async {
    if (_checkingPin || _pinController.text.isEmpty) return;

    setState(() {
      _checkingPin = true;
      _error = null;
    });

    try {
      final success = await AppLockService.verifyPin(_pinController.text);
      if (!mounted) return;
      setState(() {
        _checkingPin = false;
        if (success) {
          _locked = false;
          _pinController.clear();
          _error = null;
        } else {
          _error = 'Incorrect PIN. Please try again.';
          _pinController.clear();
        }
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app lock authentication',
          context: ErrorDescription('while verifying the App Lock PIN'),
        ),
      );
      if (!mounted) return;
      setState(() {
        _checkingPin = false;
        _error = 'Unable to verify PIN. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Material(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_locked || !_enabled) return widget.child;

    final primary = Theme.of(context).colorScheme.primary;
    return Material(
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
                    'Enter your private PIN to access your financial data.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 26),
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
                      onPressed: _checkingPin ? null : _unlockWithPin,
                      child: _checkingPin
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
