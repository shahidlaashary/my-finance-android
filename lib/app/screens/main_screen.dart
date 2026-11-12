import 'package:flutter/material.dart';

import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/features/dashboard/screens/home_screen.dart' show HomePage;
import 'package:my_finance/features/finance/screens/assets_screen.dart';
import 'package:my_finance/features/finance/screens/budgets_screen.dart';
import 'package:my_finance/features/finance/screens/goals_screen.dart';
import 'package:my_finance/features/finance/screens/loans_screen.dart';
import 'package:my_finance/features/finance/screens/stats_screen.dart';
import 'package:my_finance/features/finance/screens/transaction_entry_form.dart' show TransactionEntryForm;
import 'package:my_finance/features/finance/screens/transactions_screen.dart';
import 'package:my_finance/features/finance/screens/wallets_screen.dart' show WalletsPage;
import 'package:my_finance/app/screens/simple_feature_page.dart' show SimpleFeaturePage;

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Plus button alag page nahi, is liye pages mein sirf 8 screens hain.
  int selectedIndex = 0;
  int _refreshVersion = 0;

  List<Widget> get pages => [
    KeyedSubtree(
      key: ValueKey('home-$_refreshVersion'),
      child: HomePage(
        featurePageBuilder: (title) => SimpleFeaturePage(title: title),
      ),
    ),
    KeyedSubtree(key: ValueKey('assets-$_refreshVersion'), child: const AssetsScreen()),
    KeyedSubtree(key: ValueKey('budgets-$_refreshVersion'), child: const BudgetsScreen()),
    KeyedSubtree(key: ValueKey('goals-$_refreshVersion'), child: const GoalsScreen()),
    KeyedSubtree(key: ValueKey('loans-$_refreshVersion'), child: const LoansScreen()),
    KeyedSubtree(key: ValueKey('stats-$_refreshVersion'), child: const StatsScreen()),
    KeyedSubtree(key: ValueKey('transactions-$_refreshVersion'), child: const TransactionsScreen()),
    KeyedSubtree(key: ValueKey('wallets-$_refreshVersion'), child: const WalletsPage()),
  ];

  @override
  void initState() {
    super.initState();
    AppRefreshController.revision.addListener(_handleDataChanged);
  }

  @override
  void dispose() {
    AppRefreshController.revision.removeListener(_handleDataChanged);
    super.dispose();
  }

  void _handleDataChanged() {
    if (!mounted) return;
    setState(() => _refreshVersion++);
  }

  void selectPage(int index) {
    if (index < 0 || index >= pages.length) return;

    setState(() {
      selectedIndex = index;
    });
  }

  void openPlusSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const PlusActionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),

      // Nau jagah: aath navigation tabs aur darmiyan mein Plus.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.055),
              blurRadius: 14,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                _navItem(
                  index: 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                ),
                _navItem(
                  index: 1,
                  icon: Icons.real_estate_agent_outlined,
                  activeIcon: Icons.real_estate_agent_rounded,
                  label: 'Assets',
                ),
                _navItem(
                  index: 2,
                  icon: Icons.account_balance_wallet_outlined,
                  activeIcon: Icons.account_balance_wallet_rounded,
                  label: 'Budgets',
                ),
                _navItem(
                  index: 3,
                  icon: Icons.flag_outlined,
                  activeIcon: Icons.flag_rounded,
                  label: 'Goals',
                ),

                // Darmiyan ka Plus: sirf icon, koi text label nahi.
                Expanded(
                  flex: 1,
                  child: InkWell(
                    onTap: openPlusSheet,
                    borderRadius: BorderRadius.circular(18),
                    child: Center(
                      child: Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.22),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 29,
                        ),
                      ),
                    ),
                  ),
                ),

                _navItem(
                  index: 4,
                  icon: Icons.handshake_outlined,
                  activeIcon: Icons.handshake_rounded,
                  label: 'Loans',
                ),
                _navItem(
                  index: 5,
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart_rounded,
                  label: 'Stats',
                ),
                _navItem(
                  index: 6,
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: 'Txns',
                ),
                _navItem(
                  index: 7,
                  icon: Icons.account_balance_outlined,
                  activeIcon: Icons.account_balance_rounded,
                  label: 'Wallets',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Har navigation item ko aik jaisi width milti hai.
  // FittedBox labels ko aik hi line mein rakhne mein madad karta hai.
  Widget _navItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = selectedIndex == index;

    return Expanded(
      flex: 1,
      child: InkWell(
        onTap: () => selectPage(index),
        child: SizedBox(
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, index == 0 ? -0.75 : 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                        child: Icon(
                          isSelected ? activeIcon : icon,
                          size: 21,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 14,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Plus button ke options ka panel
// ============================================================

class PlusActionSheet extends StatefulWidget {
  const PlusActionSheet({super.key});

  @override
  State<PlusActionSheet> createState() => _PlusActionSheetState();
}

class _PlusActionSheetState extends State<PlusActionSheet> {
  String selectedType = 'Income';

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final maxSheetHeight = keyboardHeight > 0
        ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * 0.95
        : screenHeight * 0.70;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9E0DC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Add New Transaction',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _transactionTab(
                        title: 'Income',
                        subtitle: 'Money received',
                        icon: Icons.south_west_rounded,
                        color: AppColors.income,
                      ),
                      const SizedBox(width: 8),
                      _transactionTab(
                        title: 'Expense',
                        subtitle: 'Money spent',
                        icon: Icons.north_east_rounded,
                        color: AppColors.expense,
                      ),
                      const SizedBox(width: 8),
                      _transactionTab(
                        title: 'Transfer',
                        subtitle: 'Between wallets',
                        icon: Icons.swap_horiz_rounded,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TransactionEntryForm(
                    key: ValueKey(selectedType),
                    transactionType: selectedType,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _transactionTab({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final selected = selectedType == title;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (selectedType != title) {
            setState(() => selectedType = title);
          }
        },
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.11) : const Color(0xFFF5F7F6),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? color : const Color(0xFFE8EEEA),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: selected ? color : AppColors.muted),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? color : AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Home ka khulasa
// ============================================================

// ============================================================
// Assets ka safha
// ============================================================
