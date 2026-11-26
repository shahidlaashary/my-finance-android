import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App ke sound effects ki settings load, save aur playback control karta hai.
class SoundSettingsService extends ChangeNotifier {
  SoundSettingsService._();
  static final SoundSettingsService instance = SoundSettingsService._();
  static const MethodChannel _channel = MethodChannel('my_finance/sound');
  static const _enabledKey = 'sound_effects_enabled';
  static const _volumeKey = 'sound_effects_volume';
  static const _choicePrefix = 'sound_action_';
  static const _actionEnabledPrefix = 'sound_action_enabled_';

  static const actions = <String, String>{
    'app_start': 'App Startup', 'save': 'Save / Create', 'update': 'Update / Edit',
    'delete_warning': 'Delete Warning', 'delete_success': 'Deleted Successfully',
    'income': 'Income', 'expense': 'Expense', 'transfer': 'Transfer',
    'reminder': 'Reminder / Schedule', 'budget_limit': 'Budget Limit Warning',
    'error': 'Error / Failed Action', 'achievement': 'Goal Achieved',
  };
  static const presets = <String, String>{
    'soft': 'Soft & Minimal', 'modern': 'Modern UI',
    'classic': 'Classic', 'premium': 'Premium',
  };

  bool soundEnabled = false;
  double soundVolume = 0.60;
  final Map<String, String> choices = {for (final key in actions.keys) key: 'modern'};
  final Map<String, bool> actionEnabled = {for (final key in actions.keys) key: true};

  /// Saved preferences ko memory mein load karke listeners ko update karta hai.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    soundEnabled = prefs.getBool(_enabledKey) ?? false;
    soundVolume = prefs.getDouble(_volumeKey) ?? 0.60;
    for (final key in actions.keys) {
      choices[key] = prefs.getString('$_choicePrefix$key') ?? 'modern';
      actionEnabled[key] = prefs.getBool('$_actionEnabledPrefix$key') ?? true;
    }
    notifyListeners();
  }

  /// Tamam sound effects ka global ON/OFF status save karta hai.
  Future<void> setSoundEnabled(bool value) async {
    soundEnabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, value);
  }

  /// Sound volume ko 0.0 se 1.0 ke darmiyan rakh kar save karta hai.
  Future<void> setSoundVolume(double value) async {
    soundVolume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setDouble(_volumeKey, soundVolume);
  }

  Future<void> setActionEnabled(String action, bool value) async {
    if (!actions.containsKey(action)) return;
    actionEnabled[action] = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool('$_actionEnabledPrefix$action', value);
  }

  Future<void> setChoice(String action, String preset) async {
    if (!actions.containsKey(action) || !presets.containsKey(preset)) return;
    choices[action] = preset;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('$_choicePrefix$action', preset);
  }

  /// Action aur preset ke mutabiq frequency aur duration ka sound pattern banata hai.
  List<List<int>> _pattern(String action, String preset) {
    const patterns = <String, List<List<int>>>{
      'app_start': [[523, 110], [659, 110], [784, 160], [1047, 260]],
      'save': [[988, 65], [1319, 95]],
      'update': [[740, 70], [880, 70], [1175, 105]],
      'delete_warning': [[392, 150], [330, 210]],
      'delete_success': [[784, 65], [988, 75], [1319, 120]],
      'income': [[659, 75], [880, 90], [1175, 130]],
      'expense': [[587, 100], [440, 120], [349, 160]],
      'transfer': [[698, 65], [880, 65], [698, 65], [1047, 100]],
      'reminder': [[880, 80], [880, 80], [1175, 140]],
      'budget_limit': [[784, 100], [622, 120], [523, 180]],
      'error': [[330, 130], [247, 180]],
      'achievement': [[523, 70], [659, 70], [784, 70], [988, 90], [1319, 180]],
    };
    final source = patterns[action] ?? [[880, 90]];
    final pitch = switch (preset) {
      'soft' => 0.96,
      'classic' => 0.90,
      'premium' => 1.06,
      _ => 1.0,
    };
    final duration = switch (preset) {
      'soft' => 1.18,
      'classic' => 1.08,
      'premium' => 1.14,
      _ => 1.0,
    };
    return source.map((step) => [
      (step[0] * pitch).round(),
      (step[1] * duration).round(),
    ]).toList();
  }

  String _waveformForAction(String action) {
    const waveforms = <String, String>{
      'app_start': 'bell',
      'save': 'pluck',
      'update': 'bright',
      'delete_warning': 'warm',
      'delete_success': 'bell',
      'income': 'bright',
      'expense': 'soft',
      'transfer': 'pluck',
      'reminder': 'warm',
      'budget_limit': 'bright',
      'error': 'warm',
      'achievement': 'bell',
    };
    return waveforms[action] ?? 'soft';
  }

  /// Enabled sound action ka pattern native channel ko bhejta hai.
  Future<void> play(String action, {String? presetOverride}) async {
    if (!soundEnabled || soundVolume <= 0 || !actions.containsKey(action) || actionEnabled[action] == false) return;
    final pattern = _pattern(action, presetOverride ?? choices[action] ?? 'modern');
    try {
      await _channel.invokeMethod<bool>('playPattern', {
        'pattern': pattern.map((s) => {'frequency': s[0], 'durationMs': s[1], 'waveform': _waveformForAction(action)}).toList(),
        'volume': soundVolume,
      });
    } catch (_) {}
  }

  Future<void> preview(String action) => play(action);
  Future<void> testSound() => play('save');

  /// Sound settings ko default values par reset karke preferences save karta hai.
  Future<void> reset() async {
    soundEnabled = false;
    soundVolume = 0.60;
    for (final key in actions.keys) { choices[key] = 'modern'; actionEnabled[key] = true; }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.setDouble(_volumeKey, 0.60);
    for (final key in actions.keys) {
      await prefs.setString('$_choicePrefix$key', 'modern');
      await prefs.setBool('$_actionEnabledPrefix$key', true);
    }
  }
}
