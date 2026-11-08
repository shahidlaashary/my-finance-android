import 'package:flutter/material.dart';

import 'assets_screen.dart';
import 'savings_screen.dart';
import 'budgets_screen.dart';
import 'recurring_transactions_screen.dart';
import 'reports_screen.dart';

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
        title: 'Assets',
        description: 'Manage properties, vehicles and valuables',
        icon: Icons.real_estate_agent,
        color: Colors.teal,
        screen: AssetsScreen(),
      ),
      _FeatureItem(
        title: 'Savings Goals',
        description: 'Track savings targets and contributions',
        icon: Icons.savings,
        color: Colors.green,
        screen: SavingsScreen(),
      ),
      _FeatureItem(
        title: 'Budgets',
        description: 'Manage spending limits and budgets',
        icon: Icons.account_balance_wallet,
        color: Colors.orange,
        screen: BudgetsScreen(),
      ),
      _FeatureItem(
        title: 'Recurring Transactions',
        description: 'Manage scheduled income and expenses',
        icon: Icons.repeat,
        color: Colors.blue,
        screen: RecurringTransactionsScreen(),
      ),
      _FeatureItem(
        title: 'Reports & Analytics',
        description: 'View financial summaries and reports',
        icon: Icons.analytics,
        color: Colors.purple,
        screen: ReportsScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('More Features'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF147D59),
                  Color(0xFF20A477),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.dashboard_customize,
                  color: Colors.white,
                  size: 34,
                ),
                SizedBox(height: 12),
                Text(
                  'Manage Your Finances',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Access all additional finance tools from one place.',
                  style: TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                leading: CircleAvatar(
                  radius: 25,
                  backgroundColor:
                      feature.color.withOpacity(0.12),
                  child: Icon(
                    feature.icon,
                    color: feature.color,
                    size: 26,
                  ),
                ),
                title: Text(
                  feature.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(feature.description),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
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
        ],
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
