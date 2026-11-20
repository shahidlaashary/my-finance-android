import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_finance/core/preferences/sound_settings_service.dart';

class SoundVoiceSettingsScreen extends StatelessWidget {
  const SoundVoiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SoundSettingsService.instance;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound & Voice Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: AnimatedBuilder(
        animation: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionCard(
              context,
              icon: Icons.music_note_rounded,
              title: 'App Sound Effects',
              subtitle: 'Play a soft sound when you tap or use app controls',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sound Effects'),
                    subtitle: Text(settings.soundEnabled ? 'Enabled across the app' : 'All app sounds are muted'),
                    value: settings.soundEnabled,
                    onChanged: settings.setSoundEnabled,
                  ),
                  _volumeRow(
                    context,
                    title: 'Sound Volume',
                    value: settings.soundVolume,
                    enabled: settings.soundEnabled,
                    onChanged: settings.setSoundVolume,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: settings.soundEnabled ? settings.testSound : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Test Sound'),
                    ),
                  ),
                ],
              ),
            ),
            _sectionCard(
              context,
              icon: Icons.record_voice_over_rounded,
              title: 'Voice Announcements',
              subtitle: 'Allow My Finance to speak supported announcements',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Voice Announcements'),
                    subtitle: Text(settings.voiceEnabled ? 'Enabled' : 'Disabled'),
                    value: settings.voiceEnabled,
                    onChanged: settings.setVoiceEnabled,
                  ),
                  _volumeRow(
                    context,
                    title: 'Voice Volume',
                    value: settings.voiceVolume,
                    enabled: settings.voiceEnabled,
                    onChanged: settings.setVoiceVolume,
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Voice Language',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: settings.voiceLanguage,
                        items: SoundSettingsService.supportedLanguages.entries
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
                            .toList(),
                        onChanged: settings.voiceEnabled
                            ? (value) {
                                if (value != null) settings.setVoiceLanguage(value);
                              }
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: settings.voiceEnabled
                          ? () => _testVoice(context, settings)
                          : null,
                      icon: const Icon(Icons.record_voice_over_rounded),
                      label: const Text('Test Voice'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
              child: Text(
                'Only the selected language voice is used. If it is not installed or supported on your Android device, the announcement will not play.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testVoice(
    BuildContext context,
    SoundSettingsService settings,
  ) async {
    try {
      await settings.testVoice();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice test started.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      final message = error.code == 'VOICE_UNAVAILABLE'
          ? 'Selected language ki TTS voice is not available on this device. Install that voice in Android Text-to-Speech settings.'
          : error.code == 'TTS_NOT_READY'
              ? 'Text-to-speech is still starting. Please try again.'
              : 'Unable to start the selected TTS voice.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _volumeRow(
    BuildContext context, {
    required String title,
    required double value,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${(value * 100).round()}%'),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
