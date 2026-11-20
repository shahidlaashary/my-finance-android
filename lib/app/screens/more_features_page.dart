import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/app/screens/more_features_screen.dart' show AppSettingsScreen;
import 'package:my_finance/features/documents/screens/my_documents_screen.dart';
import 'package:my_finance/features/vehicles/screens/vehicles_screen.dart';
import 'package:my_finance/features/finance/screens/exchange_rates_screen.dart';
import 'package:my_finance/features/stock/screens/stock_manager_screen.dart';
import 'package:my_finance/features/staff/screens/staff_screen.dart';
import 'package:my_finance/features/recycle_bin/screens/recycle_bin_screen.dart';
import 'package:my_finance/features/installments/screens/installments_screen.dart';
import 'package:my_finance/features/committee/screens/committee_screen.dart';
import 'package:my_finance/features/partners/screens/my_partner_screen.dart';
import 'package:my_finance/features/finance/screens/whatsapp_automation_screen.dart';

class MoreFeaturesPage extends StatelessWidget {
  const MoreFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Budgets, Goals aur Stats ab bottom navigation mein mojood hain.
    // Is liye yahan unki dobara entries nahi rakhi gayin.
    final features = [
      {
        'title': 'WhatsApp Automation',
        'icon': Icons.chat_rounded,
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
        'title': 'Staff Management',
        'icon': Icons.badge_outlined,
      },
      {
        'title': 'Stock Manager',
        'icon': Icons.inventory_2_outlined,
      },
      {
        'title': 'Vehicle Manager',
        'icon': Icons.directions_car_filled_rounded,
      },
      {
        'title': 'Installment Manager',
        'icon': Icons.payments_rounded,
      },
      {
        'title': 'Committee',
        'icon': Icons.groups_2_outlined,
      },
      {
        'title': 'My Partner',
        'icon': Icons.handshake_outlined,
      },
      {
        'title': 'Recycle Bin',
        'icon': Icons.delete_outline_rounded,
      },
      {
        'title': 'Settings',
        'icon': Icons.settings_outlined,
      },

    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                      if (feature['title'] == 'WhatsApp Automation') {
                        return const WhatsAppAutomationScreen();
                      }
                      if (feature['title'] == 'Settings') {
                        return const AppSettingsScreen();
                      }
                      if (feature['title'] == 'Vehicle Manager') {
                        return const VehiclesScreen();
                      }
                      if (feature['title'] == 'My Documents') {
                        return const MyDocumentsScreen();
                      }
                      if (feature['title'] == 'Exchange Rates') {
                        return const ExchangeRatesScreen();
                      }
                      if (feature['title'] == 'Staff Management') {
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
                      if (feature['title'] == 'My Partner') {
                        return const MyPartnerScreen();
                      }
                      return const MyDocumentsScreen();
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
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
