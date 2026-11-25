import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/sound_settings_service.dart';

class SoundSettingsScreen extends StatelessWidget {
  const SoundSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final settings = SoundSettingsService.instance;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sound Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: AnimatedBuilder(
        animation: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.volume_up_rounded, color: colors.primary, size: 25), const SizedBox(width: 10),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Action Sound Effects', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text('Control app launch music, action sound effects and audio preferences', style: TextStyle(fontSize: 12)),
                  ]))]),
                const SizedBox(height: 6),
                SwitchListTile(dense: true, visualDensity: VisualDensity.compact, minVerticalPadding: 0, contentPadding: EdgeInsets.zero, title: const Text('Sound Effects'),
                  subtitle: Text(settings.soundEnabled ? 'Enabled' : 'Off by default'),
                  value: settings.soundEnabled, onChanged: settings.setSoundEnabled),
                Opacity(opacity: settings.soundEnabled ? 1 : 0.45, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [const Expanded(child: Text('Master Volume', style: TextStyle(fontWeight: FontWeight.w600))),
                    Text('${(settings.soundVolume * 100).round()}%')]),
                  Slider(value: settings.soundVolume, min: 0, max: 1, divisions: 20, onChanged: settings.soundEnabled ? settings.setSoundVolume : null),
                  Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: settings.soundEnabled ? settings.testSound : null,
                    icon: const Icon(Icons.play_arrow_rounded), label: const Text('Preview'))),
                ])),
              ]),
            )),
            Card(elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Action Sounds', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Choose a distinct tone style for each action.', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 4),
                SwitchListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  minVerticalPadding: 0,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('App Launch Sound', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: const Text('Play a premium welcome tone when the app opens', style: TextStyle(fontSize: 11)),
                  value: settings.actionEnabled['app_start'] ?? true,
                  onChanged: settings.soundEnabled ? (value) => settings.setActionEnabled('app_start', value) : null,
                ),
                ...SoundSettingsService.actions.entries.where((entry) => entry.key != 'app_start').map((entry) => Padding(padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    SizedBox(width: 142, child: DropdownButtonFormField<String>(
                      value: settings.choices[entry.key] ?? 'modern', isDense: true,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 7)),
                      items: SoundSettingsService.presets.entries.map((p) => DropdownMenuItem(value: p.key,
                        child: Text(p.value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: settings.soundEnabled ? (v) { if (v != null) settings.setChoice(entry.key, v); } : null,
                    )),
                    IconButton(tooltip: 'Preview ${entry.value}', onPressed: settings.soundEnabled ? () => settings.preview(entry.key) : null,
                      icon: const Icon(Icons.play_circle_outline_rounded)),
                  ]))),
              ]),
            )),
            Padding(padding: const EdgeInsets.only(top: 4, bottom: 10), child: Text(
              'No sound on ordinary taps, typing, scrolling or navigation. Delete actions use warning and completion tones.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () async {
              final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                title: const Text('Reset Sound Settings?'),
                content: const Text('Turn sounds off and restore all sound styles to defaults?'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset'))],
              ));
              if (confirm == true) await settings.reset();
            }, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Reset Sound Settings'))),
          ],
        ),
      ),
    );
  }
}
