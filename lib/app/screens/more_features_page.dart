import 'package:flutter/material.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/app/screens/more_features_screen.dart' show AppSettingsScreen;
import 'package:my_finance/features/finance/screens/categories_management_screen.dart' show CategoriesPage;
import 'package:my_finance/features/backup_restore/screens/backup_restore_screen.dart';
import 'package:my_finance/features/documents/screens/my_documents_screen.dart';
import 'package:my_finance/features/vehicles/screens/vehicles_screen.dart';
import 'package:my_finance/features/finance/screens/recurring_transactions_screen.dart';
import 'package:my_finance/features/finance/screens/exchange_rates_screen.dart';

class MoreFeaturesPage extends StatelessWidget {
  const MoreFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Budgets, Goals aur Stats ab bottom navigation mein mojood hain.
    // Is liye yahan unki dobara entries nahi rakhi gayin.
    final features = [
      {
        'title': 'Vehicle Manager',
        'icon': Icons.directions_car_filled_rounded,
      },
      {
        'title': 'Categories',
        'icon': Icons.category_outlined,
      },
      {
        'title': 'Recurring Transactions',
        'icon': Icons.repeat_rounded,
      },
      {
        'title': 'Exchange Rates',
        'icon': Icons.currency_exchange_rounded,
      },
      {
        'title': 'Settings',
        'icon': Icons.settings_outlined,
      },
      {
        'title': 'Backup & Restore',
        'icon': Icons.backup_outlined,
      },
      {
        'title': 'My Documents',
        'icon': Icons.folder_copy_outlined,
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'More Features',
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
                feature['title'] as String,
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
                      if (feature['title'] == 'Categories') {
                        return const CategoriesPage();
                      }
                      if (feature['title'] == 'Settings') {
                        return const AppSettingsScreen();
                      }
                      if (feature['title'] == 'Vehicle Manager') {
                        return const VehiclesScreen();
                      }
                      if (feature['title'] == 'Backup & Restore') {
                        return const BackupRestoreScreen();
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
