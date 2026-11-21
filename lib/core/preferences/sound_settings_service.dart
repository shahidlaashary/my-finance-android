import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundSettingsService extends ChangeNotifier {
  SoundSettingsService._();
  static final SoundSettingsService instance = SoundSettingsService._();
  static const MethodChannel _channel = MethodChannel('my_finance/sound');
  static const _enabledKey = 'sound_effects_enabled';
  static const _volumeKey = 'sound_effects_volume';
  static const _choicePrefix = 'sound_action_';

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

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    soundEnabled = prefs.getBool(_enabledKey) ?? false;
    soundVolume = prefs.getDouble(_volumeKey) ?? 0.60;
    for (final key in actions.keys) {
      choices[key] = prefs.getString('$_choicePrefix$key') ?? 'modern';
    }
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    soundEnabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, value);
  }

  Future<void> setSoundVolume(double value) async {
    soundVolume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setDouble(_volumeKey, soundVolume);
  }

  Future<void> setChoice(String action, String preset) async {
    if (!actions.containsKey(action) || !presets.containsKey(preset)) return;
    choices[action] = preset;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('$_choicePrefix$action', preset);
  }

  List<List<int>> _pattern(String action, String preset) {
    const tones = <String, Map<String, List<List<int>>>>{
      'soft': {
        'app_start': [[523,90],[659,90],[784,140],[1047,220]], 'save': [[880,75]], 'update': [[740,65],[980,70]],
        'delete_warning': [[440,160]], 'delete_success': [[660,65],[880,75]],
        'income': [[784,65],[1046,90]], 'expense': [[620,90],[500,100]],
        'transfer': [[720,65],[840,65]], 'reminder': [[880,100],[880,100]], 'budget_limit': [[740,110],[520,160]],
        'error': [[360,150],[280,180]], 'achievement': [[880,70],[1100,70],[1320,130]],
      },
      'classic': {
        'app_start': [[523,100],[659,100],[784,160],[1047,260]], 'save': [[950,100]], 'update': [[780,100],[950,100]],
        'delete_warning': [[420,200]], 'delete_success': [[700,90],[1000,110]],
        'income': [[900,100],[1200,120]], 'expense': [[600,100],[420,140]],
        'transfer': [[750,90],[950,90],[750,90]], 'reminder': [[1000,120]], 'budget_limit': [[800,120],[560,180]],
        'error': [[320,200]], 'achievement': [[800,90],[1000,90],[1200,90],[1500,160]],
      },
      'premium': {
        'app_start': [[587,100],[740,100],[880,160],[1175,280]], 'save': [[1040,70],[1310,80]], 'update': [[880,60],[1100,60],[1320,85]],
        'delete_warning': [[500,100],[400,150]], 'delete_success': [[880,60],[1175,70],[1560,110]],
        'income': [[1040,70],[1310,70],[1560,100]], 'expense': [[720,90],[520,110]],
        'transfer': [[880,65],[1040,65],[880,65]], 'reminder': [[1040,90],[880,90]], 'budget_limit': [[880,100],[620,170]],
        'error': [[400,100],[300,170]], 'achievement': [[880,60],[1100,60],[1320,60],[1760,140]],
      },
    };
    if (preset == 'modern') {
      const modern = <String, List<List<int>>>{
        'app_start': [[554,90],[698,90],[831,150],[1109,250]], 'save': [[980,80],[1180,70]], 'update': [[760,75],[980,80]],
        'delete_warning': [[520,140]], 'delete_success': [[760,70],[1040,90]],
        'income': [[880,70],[1175,90]], 'expense': [[650,90],[460,100]],
        'transfer': [[800,65],[1000,65]], 'reminder': [[920,90],[920,90]], 'budget_limit': [[820,100],[600,160]],
        'error': [[350,140],[270,160]], 'achievement': [[880,70],[1100,70],[1400,110]],
      };
      return modern[action] ?? [[880,80]];
    }
    return tones[preset]?[action] ?? [[880,80]];
  }

  Future<void> play(String action, {String? presetOverride}) async {
    if (!soundEnabled || soundVolume <= 0 || !actions.containsKey(action)) return;
    final pattern = _pattern(action, presetOverride ?? choices[action] ?? 'modern');
    try {
      await _channel.invokeMethod<bool>('playPattern', {
        'pattern': pattern.map((s) => {'frequency': s[0], 'durationMs': s[1]}).toList(),
        'volume': soundVolume,
      });
    } catch (_) {}
  }

  Future<void> preview(String action) => play(action);
  Future<void> testSound() => play('save');

  Future<void> reset() async {
    soundEnabled = false;
    soundVolume = 0.60;
    for (final key in actions.keys) { choices[key] = 'modern'; }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.setDouble(_volumeKey, 0.60);
    for (final key in actions.keys) { await prefs.setString('$_choicePrefix$key', 'modern'); }
  }
}
