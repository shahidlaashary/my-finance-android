import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/app/screens/more_features_screen.dart' show AppSettingsScreen;
import 'package:my_finance/features/documents/screens/my_documents_screen.dart';
import 'package:my_finance/features/vehicles/screens/vehicles_screen.dart';
import 'package:my_finance/features/finance/screens/recurring_transactions_screen.dart';
import 'package:my_finance/features/finance/screens/exchange_rates_screen.dart';
import 'package:my_finance/features/finance/screens/debt_payoff_screen.dart';
import 'package:my_finance/features/stock/screens/stock_manager_screen.dart';
import 'package:my_finance/features/staff/screens/staff_screen.dart';
import 'package:my_finance/features/recycle_bin/screens/recycle_bin_screen.dart';
import 'package:my_finance/app/screens/about_hub_screen.dart';

class MoreFeaturesPage extends StatelessWidget {
  const MoreFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Budgets, Goals aur Stats ab bottom navigation mein mojood hain.
    // Is liye yahan unki dobara entries nahi rakhi gayin.
    final features = [
      {
        'title': 'About',
        'icon': Icons.info_outline_rounded,
      },
      {
        'title': 'Debt Payoff Planner',
        'icon': Icons.trending_down_rounded,
      },
      {
        'title': 'Exchange Rates',
        'icon': Icons.currency_exchange_rounded,
      },
      {
        'title': 'My Documents',
        'icon': Icons.folder_copy_outlined,
      },
      {
        'title': 'Recurring Transactions',
        'icon': Icons.repeat_rounded,
      },
      {
        'title': 'Settings',
        'icon': Icons.settings_outlined,
      },
      {
        'title': 'Staff Management',
        'icon': Icons.badge_outlined,
      },
      {
        'title': 'Recycle Bin',
        'icon': Icons.delete_outline_rounded,
      },
      {
        'title': 'Stock Manager',
        'icon': Icons.inventory_2_outlined,
      },
      {
        'title': 'Vehicle Manager',
        'icon': Icons.directions_car_filled_rounded,
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          appText(context, 'More Features', 'مزید خصوصیات'),
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: features.length,
        itemBuilder: (context, index) {
          final feature = features[index];

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(
                feature['icon'] as IconData,
                color: AppColors.primary,
              ),
              title: Text(
                appText(context, feature['title'] as String, feature['title'] as String),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) {
                      if (feature['title'] == 'Settings') {
                        return const AppSettingsScreen();
                      }
                      if (feature['title'] == 'Vehicle Manager') {
                        return const VehiclesScreen();
                      }
                      if (feature['title'] == 'My Documents') {
                        return const MyDocumentsScreen();
                      }
                      if (feature['title'] == 'Recurring Transactions') {
                        return const RecurringTransactionsScreen();
                      }
                      if (feature['title'] == 'Exchange Rates') {
                        return const ExchangeRatesScreen();
                      }
                      if (feature['title'] == 'Debt Payoff Planner') {
                        return const DebtPayoffScreen();
                      }
                      if (feature['title'] == 'Staff Management') {
                        return const StaffScreen();
                      }
                      if (feature['title'] == 'Recycle Bin') {
                        return const RecycleBinScreen();
                      }
                      if (feature['title'] == 'Stock Manager') {
                        return const StockManagerScreen();
                      }
                      if (feature['title'] == 'About') {
                        return const AboutHubScreen();
                      }
                      return const MyDocumentsScreen();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
