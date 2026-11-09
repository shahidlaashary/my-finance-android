
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
    final features = [
      _FeatureItem(
        title: 'Categories',
        description: 'Manage income and expense categories',
        icon: Icons.category_rounded,
        color: Colors.deepPurple,
        screen: const CategoriesScreen(),
      ),
      _FeatureItem(
        title: 'Assets',
        description: 'Manage properties, vehicles and valuables',
        icon: Icons.real_estate_agent_rounded,
        color: Colors.teal,
        screen: AssetsScreen(),
      ),
      _FeatureItem(
        title: 'Savings Goals',
        description: 'Track savings targets and contributions',
        icon: Icons.savings_rounded,
        color: Colors.green,
        screen: SavingsScreen(),
      ),
      _FeatureItem(
        title: 'Budgets',
        description: 'Manage spending limits and budgets',
        icon: Icons.account_balance_wallet_rounded,
        color: Colors.orange,
        screen: BudgetsScreen(),
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
        title: 'Backup & Restore',
        description: 'Create backups and restore your finance data',
        icon: Icons.backup_rounded,
        color: Colors.indigo,
        screen: BackupRestoreScreen(),
      ),
      _FeatureItem(
        title: 'Settings',
        description: 'App preferences, currency and language settings',
        icon: Icons.settings_rounded,
        color: Colors.blueGrey,
        screen: const AppSettingsScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'More Features',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
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
                  _openScreen(
                    context,
                    feature.screen,
                  );
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

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
          _SettingsInfoTile(
            icon: Icons.currency_exchange_rounded,
            title: 'Base Currency',
            subtitle: 'Default currency: PKR',
          ),
          _SettingsInfoTile(
            icon: Icons.price_change_rounded,
            title: 'Manual Exchange Rates',
            subtitle: 'Buy and sell exchange rates',
          ),
          _SettingsInfoTile(
            icon: Icons.language_rounded,
            title: 'Language',
            subtitle: 'English, Urdu and other languages',
          ),
          _SettingsInfoTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'App theme and display preferences',
          ),
          _SettingsInfoTile(
            icon: Icons.backup_rounded,
            title: 'Backup Preferences',
            subtitle: 'Automatic and manual backup options',
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
                    'Settings options are being prepared. Currency management, exchange rates, language and other preferences will be implemented in the next updates.',
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

class _SettingsInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SettingsInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
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
      ),
    );
  }
}

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
