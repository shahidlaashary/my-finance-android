import 'package:flutter/material.dart';

import 'package:my_finance/core/theme/appearance_settings_service.dart';
import 'package:my_finance/features/backup_restore/screens/backup_restore_screen.dart';
import 'package:my_finance/features/security/app_lock_screen.dart';
import 'package:my_finance/features/settings/general_app_preferences_screen.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openScreen(context, const GeneralAppPreferencesScreen()),
            child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Settings',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Manage your My Finance preferences.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
          const SizedBox(height: 20),
          _SettingsInfoTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Customize theme mode and app colors',
            onTap: () => _openScreen(
              context,
              const AppearanceScreen(),
            ),
          ),
          _SettingsInfoTile(
            icon: Icons.backup_rounded,
            title: 'Backup & Restore',
            subtitle: 'Create a manual backup or restore your finance data',
            onTap: () => _openScreen(
              context,
              const BackupRestoreScreen(),
            ),
          ),
          _SettingsInfoTile(
            icon: Icons.security_rounded,
            title: 'App Lock & Security',
            subtitle: 'Protect with PIN, Face Unlock or Fingerprint',
            onTap: () => _openScreen(
              context,
              const AppLockScreen(),
            ),
          ),
          const _SettingsInfoTile(
            icon: Icons.currency_exchange_rounded,
            title: 'Base Currency',
            subtitle: 'Default currency: PKR',
          ),
          const _SettingsInfoTile(
            icon: Icons.language_rounded,
            title: 'Language',
            subtitle: 'English, Urdu and other languages',
          ),
          const _SettingsInfoTile(
            icon: Icons.price_change_rounded,
            title: 'Manual Exchange Rates',
            subtitle: 'Manage buy and sell exchange rates',
          ),
          const SizedBox(height: 16),
          _ComingSoonNotice(
            message:
                'Other settings will be made functional in upcoming updates.',
          ),
        ],
      ),
    );
  }
}

// =====================================================
// App ki zahiri soorat ka safha
// =====================================================

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final AppearanceSettingsService _settings =
      AppearanceSettingsService.instance;

  Future<void> _changeThemePreset(AppThemePreset preset) async {
    try {
      await _settings.setThemePreset(preset);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save theme: $e')),
      );
    }
  }

  Widget _buildHeader(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, Colors.white, 0.25)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.palette_rounded,
            color: Colors.white,
            size: 34,
          ),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personalize Your App',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Customize the look and feel of My Finance.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: primary, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle, color: Colors.green, size: 19),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOptions() {
    return ValueListenableBuilder<AppThemePreset>(
      valueListenable: _settings.themePreset,
      builder: (context, selectedPreset, _) {
        final options = [
          (AppThemePreset.emeraldGreen, 'Emerald Green', Icons.eco_outlined),
          (AppThemePreset.lightMode, 'Light Mode', Icons.light_mode_outlined),
          (AppThemePreset.darkMode, 'Dark Mode', Icons.dark_mode_outlined),
          (AppThemePreset.midnightGold, 'Midnight Gold', Icons.nights_stay_outlined),
          (AppThemePreset.oceanBlue, 'Ocean Blue', Icons.water_outlined),
          (AppThemePreset.carbonBlack, 'Carbon Black', Icons.contrast_rounded),
        ];

        return Column(
          children: options.map((option) {
            return RadioListTile<AppThemePreset>(
              value: option.$1,
              groupValue: selectedPreset,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(option.$2),
              secondary: Icon(option.$3),
              onChanged: (value) {
                if (value != null) _changeThemePreset(value);
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Appearance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context),
          const SizedBox(height: 20),
          _buildActiveSection(
            context: context,
            icon: Icons.dark_mode_rounded,
            title: 'App Theme',
            description: 'Choose a color theme for the entire app',
            children: [_buildThemeOptions()],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// =====================================================
// Jald anay wali sahulat ka paigham
// =====================================================

class _ComingSoonNotice extends StatelessWidget {
  final String message;

  const _ComingSoonNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// Settings ka option
// =====================================================

class _SettingsInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 5,
        ),
        leading: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 25,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: onTap != null
            ? const Icon(Icons.chevron_right_rounded)
            : null,
        onTap: onTap,
      ),
    );
  }
}
