import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance/core/preferences/language_settings_service.dart';

/// App-wide sound and voice preferences plus the native Android audio bridge.
class SoundSettingsService extends ChangeNotifier {
  SoundSettingsService._();
  static final SoundSettingsService instance = SoundSettingsService._();

  static const MethodChannel _channel = MethodChannel('my_finance/sound');
  static const _soundKey = 'sound_effects_enabled';
  static const _voiceKey = 'voice_announcements_enabled';
  static const _soundVolumeKey = 'sound_effects_volume';
  static const _voiceVolumeKey = 'voice_announcements_volume';
  static const _voiceLanguageKey = 'voice_announcements_language';

  static const supportedLanguages = LanguageSettingsService.languageNames;

  bool soundEnabled = true;
  bool voiceEnabled = false;
  double soundVolume = 0.55;
  double voiceVolume = 0.85;
  String voiceLanguage = 'en';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    soundEnabled = prefs.getBool(_soundKey) ?? true;
    voiceEnabled = prefs.getBool(_voiceKey) ?? false;
    soundVolume = prefs.getDouble(_soundVolumeKey) ?? 0.55;
    voiceVolume = prefs.getDouble(_voiceVolumeKey) ?? 0.85;
    final language = prefs.getString(_voiceLanguageKey) ??
        LanguageSettingsService.instance.locale.value.languageCode;
    voiceLanguage = supportedLanguages.containsKey(language) ? language : 'en';
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    soundEnabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_soundKey, value);
  }

  Future<void> setVoiceEnabled(bool value) async {
    voiceEnabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_voiceKey, value);
  }

  Future<void> setSoundVolume(double value) async {
    soundVolume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setDouble(_soundVolumeKey, soundVolume);
  }

  Future<void> setVoiceVolume(double value) async {
    voiceVolume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setDouble(_voiceVolumeKey, voiceVolume);
  }

  Future<void> setVoiceLanguage(String value) async {
    if (!supportedLanguages.containsKey(value)) return;
    voiceLanguage = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_voiceLanguageKey, value);
  }

  /// Short universal feedback tone. Called by the app-level tap listener.
  Future<void> playActionSound() async {
    if (!soundEnabled || soundVolume <= 0) return;
    try {
      await _channel.invokeMethod<bool>('playTone', {
        'frequency': 880,
        'durationMs': 75,
        'volume': soundVolume,
      });
    } catch (_) {
      // Audio feedback must never interrupt a finance action.
    }
  }

  /// Can be used by completed finance actions and reminder flows.
  Future<void> announce(String text, {String? language}) async {
    if (!voiceEnabled || text.trim().isEmpty || voiceVolume <= 0) return;
    try {
      await _channel.invokeMethod<bool>('speak', {
        'text': text,
        'language': language ?? voiceLanguage,
        'volume': voiceVolume,
      });
    } on PlatformException {
      // Let the caller show a clear message when the selected voice is missing.
      rethrow;
    }
  }

  Future<void> testSound() async {
    if (!soundEnabled) return;
    try {
      await _channel.invokeMethod<bool>('playTone', {
        'frequency': 1046,
        'durationMs': 180,
        'volume': soundVolume,
      });
    } catch (_) {}
  }

  Future<void> testVoice() async {
    if (!voiceEnabled) return;
    final samples = <String, String>{
      'en': 'Welcome to My Finance.',
      'ur': 'مائی فنانس میں خوش آمدید۔',
      'ar': 'مرحباً بك في ماي فاينانس.',
      'hi': 'माई फाइनेंस में आपका स्वागत है।',
      'pa': 'مائی فنانس میں خوش آمدید۔',
      'skr': 'مائی فنانس میں خوش آمدید۔',
      'sd': 'مائی فنانس میں خوش آمدید۔',
      'bal': 'مائی فنانس میں خوش آمدید۔',
      'ps': 'مائی فنانس میں خوش آمدید۔',
    };
    await announce(samples[voiceLanguage] ?? samples['en']!);
  }
}

/// Detects short taps across the app and plays one global action sound.
/// Dragging, scrolling and long presses are ignored.
class AppSoundTapListener extends StatefulWidget {
  const AppSoundTapListener({super.key, required this.child});
  final Widget child;

  @override
  State<AppSoundTapListener> createState() => _AppSoundTapListenerState();
}

class _AppSoundTapListenerState extends State<AppSoundTapListener> {
  final Map<int, Offset> _starts = {};
  final Map<int, DateTime> _times = {};

  void _down(PointerEvent event) {
    _starts[event.pointer] = event.position;
    _times[event.pointer] = DateTime.now();
  }

  void _up(PointerEvent event) {
    final start = _starts.remove(event.pointer);
    final time = _times.remove(event.pointer);
    if (start == null || time == null) return;
    final moved = (event.position - start).distance;
    final elapsed = DateTime.now().difference(time);
    if (moved <= 12 && elapsed.inMilliseconds <= 450) {
      SoundSettingsService.instance.playActionSound();
    }
  }

  void _cancel(PointerEvent event) {
    _starts.remove(event.pointer);
    _times.remove(event.pointer);
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: widget.child,
      );
}
