import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/app_strings.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

class SimpleFeaturePage extends StatelessWidget {
  final String title;

  const SimpleFeaturePage({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: buildMainSectionAppBarActions(context),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getIcon(),
                size: 55,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(AppStrings.translate(context, 'This section is ready for its feature implementation.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (title) {
      case 'Assets':
        return Icons.real_estate_agent_outlined;
      case 'Loans':
        return Icons.handshake_outlined;
      case 'Budgets':
        return Icons.account_balance_wallet_outlined;
      case 'Goals':
        return Icons.flag_outlined;
      case 'Stats':
        return Icons.bar_chart_outlined;
      case 'Categories':
        return Icons.category_outlined;
      case 'Recurring Transactions':
        return Icons.repeat_rounded;
      case 'Exchange Rates':
        return Icons.currency_exchange_rounded;
      case 'Backup & Restore':
        return Icons.backup_outlined;
      default:
        return Icons.settings_outlined;
    }
  }
}

// ============================================================
