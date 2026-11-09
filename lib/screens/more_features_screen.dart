
import 'package:flutter/material.dart';

import 'categories_screen.dart';
import 'assets_screen.dart';
import 'savings_screen.dart';
import 'budgets_screen.dart';
import 'recurring_transactions_screen.dart';
import 'reports_screen.dart';
import 'backup_restore_screen.dart';

class MoreFeaturesScreen extends StatelessWidget {
  const MoreFeaturesScreen({super.key});

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // More Features - Alphabetical Order
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
        screen: SavingsScreen(),
      ),
      _FeatureItem(
        title: 'Settings',
        description: 'Manage app preferences and configurations',
        icon: Icons.settings_rounded,
        color: Colors.blueGrey,
        screen: const AppSettingsScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'More Features',
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
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF147D59),
                  Color(0xFF20A477),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF147D59).withOpacity(0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
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
              color: Theme.of(context).cardColor,
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
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  size: 23,
                ),
                onTap: () {
                  _openScreen(context, feature.screen);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'My Finance',
              style: TextStyle(
                color: Colors.grey.shade500,
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
                color: Colors.grey.shade500,
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
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Settings - Alphabetical Order
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
              color: const Color(0xFF147D59).withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.settings_rounded,
                  color: Color(0xFF147D59),
                  size: 32,
                ),
                SizedBox(width: 14),
                Expanded(
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

          // 1. Appearance
          _SettingsInfoTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Theme, colors, fonts and display preferences',
            onTap: () {
              _openScreen(
                context,
                const AppearanceScreen(),
              );
            },
          ),

          // 2. App Settings
          const _SettingsInfoTile(
            icon: Icons.tune_rounded,
            title: 'App Settings',
            subtitle: 'General application preferences',
          ),

          // 3. Backup & Restore
          _SettingsInfoTile(
            icon: Icons.backup_rounded,
            title: 'Backup & Restore',
            subtitle: 'Create backups and restore your finance data',
            onTap: () {
              _openScreen(
                context,
                BackupRestoreScreen(),
              );
            },
          ),

          // 4. Base Currency
          const _SettingsInfoTile(
            icon: Icons.currency_exchange_rounded,
            title: 'Base Currency',
            subtitle: 'Default currency: PKR',
          ),

          // 5. Language
          const _SettingsInfoTile(
            icon: Icons.language_rounded,
            title: 'Language',
            subtitle: 'English, Urdu and other languages',
          ),

          // 6. Manual Exchange Rates
          const _SettingsInfoTile(
            icon: Icons.price_change_rounded,
            title: 'Manual Exchange Rates',
            subtitle: 'Manage buy and sell exchange rates',
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Some settings are currently displayed as options and will be made functional in upcoming updates.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// APPEARANCE SCREEN
// =====================================================

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  Widget _buildSection({
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
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF147D59).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFF147D59),
                    size: 23,
                  ),
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
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((option) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF147D59).withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF147D59).withOpacity(0.18),
                    ),
                  ),
                  child: Text(
                    option,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF147D59),
                  Color(0xFF20A477),
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
          ),

          const SizedBox(height: 20),

          _buildSection(
            context: context,
            icon: Icons.dark_mode_rounded,
            title: 'Theme Mode',
            description: 'Choose how the app should look',
            options: [
              'Light',
              'Dark',
              'System Default',
            ],
          ),

          _buildSection(
            context: context,
            icon: Icons.color_lens_rounded,
            title: 'Color Theme',
            description: 'Choose your preferred app color',
            options: [
              'Green',
              'Blue',
              'Purple',
              'Teal',
              'Orange',
              'Red',
            ],
          ),

          _buildSection(
            context: context,
            icon: Icons.format_size_rounded,
            title: 'Font Size',
            description: 'Adjust text size throughout the app',
            options: [
              'Small',
              'Medium',
              'Large',
            ],
          ),

          _buildSection(
            context: context,
            icon: Icons.text_fields_rounded,
            title: 'Font Style',
            description: 'Choose your preferred font appearance',
            options: [
              'Default',
              'Modern',
              'Classic',
            ],
          ),

          _buildSection(
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

          _buildSection(
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

          _buildSection(
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

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'These are the planned appearance options. Their actual selection and application will be implemented in a later update.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
          color: const Color(0xFF147D59),
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
