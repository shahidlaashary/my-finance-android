
import 'package:flutter/material.dart';

import '../services/appearance_settings_service.dart';
import 'categories_screen.dart';
import 'assets_screen.dart';
import 'goals_screen.dart';
import 'budgets_screen.dart';
import 'recurring_transactions_screen.dart';
import 'reports_screen.dart';

class MoreFeaturesScreen extends StatelessWidget {
  const MoreFeaturesScreen({super.key});

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final features = [
      _FeatureItem(
        title: 'Assets',
        description: 'Manage properties, vehicles and valuables',
        icon: Icons.real_estate_agent_rounded,
        color: Colors.teal,
        screen: AssetsScreen(),
      ),
      _FeatureItem(
        title: 'Budgets',
        description: 'Manage spending limits and budgets',
        icon: Icons.account_balance_wallet_rounded,
        color: Colors.orange,
        screen: BudgetsScreen(),
      ),
      _FeatureItem(
        title: 'Categories',
        description: 'Manage income and expense categories',
        icon: Icons.category_rounded,
        color: Colors.deepPurple,
        screen: const CategoriesScreen(),
      ),
      _FeatureItem(
        title: 'Recurring Transactions',
        description: 'Manage scheduled income and expenses',
        icon: Icons.repeat_rounded,
        color: Colors.blue,
        screen: RecurringTransactionsScreen(),
      ),
      _FeatureItem(
        title: 'Reports & Analytics',
        description: 'View financial summaries and reports',
        icon: Icons.analytics_rounded,
        color: Colors.purple,
        screen: ReportsScreen(),
      ),
      _FeatureItem(
        title: 'Savings Goals',
        description: 'Track savings targets and contributions',
        icon: Icons.savings_rounded,
        color: Colors.green,
        screen: GoalsScreen(),
      ),
      _FeatureItem(
        title: 'Settings',
        description: 'Manage app preferences and configurations',
        icon: Icons.settings_rounded,
        color: Colors.blueGrey,
        screen: const AppSettingsScreen(),
      ),
    ];

    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'More',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primary,
                  Color.lerp(primary, Colors.white, 0.25)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.dashboard_customize_rounded,
                  color: Colors.white,
                  size: 36,
                ),
                SizedBox(height: 14),
                Text(
                  'Manage Your Finances',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Access your financial tools, categories, reports and app settings from one place.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Financial Tools',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...features.map(
            (feature) => Card(
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 9,
                ),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: feature.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    feature.icon,
                    color: feature.color,
                    size: 25,
                  ),
                ),
                title: Text(
                  feature.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    feature.description,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openScreen(context, feature.screen),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'My Finance',
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Center(
            child: Text(
              'Personal Finance Manager',
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// =====================================================
// SETTINGS SCREEN
// =====================================================

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
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.settings_rounded,
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
          const _SettingsInfoTile(
            icon: Icons.tune_rounded,
            title: 'App Settings',
            subtitle: 'General application preferences',
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
// APPEARANCE SCREEN
// =====================================================

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final AppearanceSettingsService _settings =
      AppearanceSettingsService.instance;

  Future<void> _changeThemeMode(ThemeMode mode) async {
    try {
      await _settings.setThemeMode(mode);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Theme mode updated successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save theme mode: $e')),
      );
    }
  }

  Future<void> _changeColorTheme(String color) async {
    try {
      await _settings.setColorTheme(color);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$color theme applied successfully.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save color theme: $e')),
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

  Widget _buildThemeModeOptions() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _settings.themeMode,
      builder: (context, selectedMode, _) {
        final options = [
          (ThemeMode.light, 'Light', Icons.light_mode_outlined),
          (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
          (ThemeMode.system, 'System Default', Icons.settings_brightness),
        ];

        return Column(
          children: options.map((option) {
            return RadioListTile<ThemeMode>(
              value: option.$1,
              groupValue: selectedMode,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(option.$2),
              secondary: Icon(option.$3),
              onChanged: (value) {
                if (value != null) {
                  _changeThemeMode(value);
                }
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildColorOptions() {
    const colors = {
      'Green': Color(0xFF147D59),
      'Blue': Color(0xFF2563EB),
      'Purple': Color(0xFF7C3AED),
      'Teal': Color(0xFF0F766E),
      'Orange': Color(0xFFEA580C),
      'Red': Color(0xFFDC2626),
    };

    return ValueListenableBuilder<String>(
      valueListenable: _settings.colorTheme,
      builder: (context, selectedColor, _) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.entries.map((entry) {
            final selected = selectedColor == entry.key;

            return InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _changeColorTheme(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: selected
                        ? entry.value
                        : Theme.of(context).dividerColor,
                    width: selected ? 2 : 1,
                  ),
                  color: entry.value.withOpacity(0.08),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 9,
                      backgroundColor: entry.value,
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12,
                            )
                          : null,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      entry.key,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildPlannedSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required List<String> options,
  }) {
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
                Icon(icon, color: Theme.of(context).hintColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Text(
                  'Coming soon',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((option) {
                return Chip(
                  label: Text(
                    option,
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ),
      ),
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
            title: 'Theme Mode',
            description: 'Choose how the app should look',
            children: [_buildThemeModeOptions()],
          ),
          _buildActiveSection(
            context: context,
            icon: Icons.color_lens_rounded,
            title: 'Color Theme',
            description: 'Choose your preferred app color',
            children: [_buildColorOptions()],
          ),
          _buildPlannedSection(
            context: context,
            icon: Icons.dashboard_rounded,
            title: 'Dashboard Layout',
            description: 'Choose how dashboard information is arranged',
            options: [
              'Classic Layout',
              'Compact Layout',
              'Card Layout',
              'Detailed Layout',
            ],
          ),
          _buildPlannedSection(
            context: context,
            icon: Icons.display_settings_rounded,
            title: 'Display Preferences',
            description: 'Customize the way information is displayed',
            options: [
              'Compact View',
              'Comfortable View',
              'Animations On',
              'Animations Off',
            ],
          ),
          _buildPlannedSection(
            context: context,
            icon: Icons.phone_android_rounded,
            title: 'App Icon',
            description: 'Choose an icon for My Finance',
            options: [
              'Default Icon',
              'Green Icon',
              'Blue Icon',
              'Dark Icon',
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// =====================================================
// COMING SOON NOTICE
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
// SETTINGS TILE
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

// =====================================================
// FEATURE ITEM MODEL
// =====================================================

class _FeatureItem {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final Widget screen;

  const _FeatureItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.screen,
  });
}
