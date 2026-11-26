import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';

import 'package:my_finance/app/screens/app_settings_screen.dart' show AppSettingsScreen;
import 'package:my_finance/modules/space/screens/my_space_screen.dart';
import 'package:my_finance/modules/vehicles/screens/vehicles_screen.dart';
import 'package:my_finance/modules/finance/screens/exchange_rates_screen.dart';
import 'package:my_finance/modules/stock/screens/stock_manager_screen.dart';
import 'package:my_finance/modules/staff/screens/staff_screen.dart';
import 'package:my_finance/features/recycle_bin/screens/recycle_bin_screen.dart';
import 'package:my_finance/modules/installments/screens/installments_screen.dart';
import 'package:my_finance/modules/committee/screens/committee_screen.dart';
import 'package:my_finance/modules/partners/screens/my_partners_screen.dart';
import 'package:my_finance/modules/parties/screens/manage_parties_screen.dart';
import 'package:my_finance/modules/properties/screens/properties_screen.dart';

/// App ke tamam additional modules aur tools tak rasai dene wala hub.
class ModulesToolsPage extends StatelessWidget {
  const ModulesToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Budgets, Goals aur Stats ab bottom navigation mein mojood hain.
    // Is liye yahan unki dobara entries nahi rakhi gayin.
    final features = [
      {
        'title': 'Exchange Rates',
        'subtitle': 'View and manage currency exchange rates',
        'icon': Icons.currency_exchange_rounded,
      },
      {
        'title': 'My Space',
        'subtitle': 'Organize books, agreements, docs, music, photos and videos in one place',
        'icon': Icons.folder_special_outlined,
      },
      {
        'title': 'Properties Manager',
        'subtitle': 'Manage properties, tenants, contracts and documents',
        'icon': Icons.home_work_outlined,
      },
      {
        'title': 'Staff Manager',
        'subtitle': 'Manage staff details and related records',
        'icon': Icons.badge_outlined,
      },
      {
        'title': 'Stock Manager',
        'subtitle': 'Track inventory, purchases and stock levels',
        'icon': Icons.inventory_2_outlined,
      },
      {
        'title': 'Vehicle Manager',
        'subtitle': 'Manage your vehicles and related expenses',
        'icon': Icons.directions_car_filled_rounded,
      },
      {
        'title': 'Installment Manager',
        'subtitle': 'Track installment plans and payment schedules',
        'icon': Icons.payments_rounded,
      },
      {
        'title': 'Committee',
        'subtitle': 'Manage committee members and contribution records',
        'icon': Icons.groups_2_outlined,
      },
      {
        'title': 'My Partners',
        'subtitle': 'Manage partners details and shared records',
        'icon': Icons.handshake_outlined,
      },
      {
        'title': 'Manage Parties',
        'subtitle': 'Manage your parties and contact records',
        'icon': Icons.people_alt_outlined,
      },
      {
        'title': 'Recycle Bin',
        'subtitle': 'Restore deleted records or permanently remove them',
        'icon': Icons.delete_outline_rounded,
      },
      {
        'title': 'Settings',
        'subtitle': 'Manage app preferences, appearance and security',
        'icon': Icons.settings_outlined,
      },

    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          appText(context, 'Modules & Tools', 'ماڈیولز اور ٹولز'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: features.length,
        itemBuilder: (context, index) {
          final feature = features[index];

          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
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
                      if (feature['title'] == 'My Space') {
                        return const MySpaceScreen();
                      }
                      if (feature['title'] == 'Exchange Rates') {
                        return const ExchangeRatesScreen();
                      }
                      if (feature['title'] == 'Properties Manager') {
                        return const PropertiesScreen();
                      }
                      if (feature['title'] == 'Staff Manager') {
                        return const StaffScreen();
                      }
                      if (feature['title'] == 'Installment Manager') {
                        return const InstallmentsScreen();
                      }
                      if (feature['title'] == 'Committee') {
                        return const CommitteeScreen();
                      }
                      if (feature['title'] == 'Recycle Bin') {
                        return const RecycleBinScreen();
                      }
                      if (feature['title'] == 'Stock Manager') {
                        return const StockManagerScreen();
                      }
                      if (feature['title'] == 'My Partners') {
                        return const MyPartnersScreen();
                      }
                      if (feature['title'] == 'Manage Parties') {
                        return ManageParties(hideBalances: false, onLoanTap: (_) {});
                      }
                      return const MySpaceScreen();
                    },
                  ),
                );
              },
              child: ListTile(
                minTileHeight: 72,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 1,
                ),
                leading: Icon(
                  feature['icon'] as IconData,
                  color: Theme.of(context).colorScheme.primary,
                  size: 23,
                ),
                title: Text(
                  appText(
                    context,
                    feature['title'] as String,
                    feature['title'] as String,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  appText(
                    context,
                    feature['subtitle'] as String,
                    feature['subtitle'] as String,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          );
        },
      ),
    );
  }
}
