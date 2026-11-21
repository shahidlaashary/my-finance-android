import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/features/dashboard/home_screen.dart' show HomePage;
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
  // Build only the Home tab at startup. Other tabs are created on first visit.
  int selectedIndex = 0;
  final Set<int> _visitedPages = {0};
  late final List<Widget> _pages;
  final GlobalKey<LoansScreenState> _loansScreenKey = GlobalKey<LoansScreenState>();

  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(featurePageBuilder: (title) => SimpleFeaturePage(title: title)),
      const AssetsScreen(),
      const BudgetsScreen(),
      const GoalsScreen(),
      LoansScreen(key: _loansScreenKey),
      const StatsScreen(),
      const TransactionsScreen(),
      const WalletsPage(),
    ];
  }

  void selectPage(int index) {
    if (index < 0 || index >= _pages.length) return;

    setState(() {
      selectedIndex = index;
      _visitedPages.add(index);
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
    final isUrdu = Localizations.localeOf(context).languageCode == 'ur';
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: List<Widget>.generate(
          _pages.length,
          (index) => _visitedPages.contains(index)
              ? _pages[index]
              : const SizedBox.shrink(),
        ),
      ),

      // Nau jagah: aath navigation tabs aur darmiyan mein Plus.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
                  label: appText(context, 'Home', 'ہوم'),
                ),
                _navItem(
                  index: 1,
                  icon: Icons.real_estate_agent_outlined,
                  activeIcon: Icons.real_estate_agent_rounded,
                  label: appText(context, 'Assets', 'اثاثے'),
                ),
                _navItem(
                  index: 2,
                  icon: Icons.account_balance_wallet_outlined,
                  activeIcon: Icons.account_balance_wallet_rounded,
                  label: appText(context, 'Budgets', 'بجٹ'),
                ),
                _navItem(
                  index: 3,
                  icon: Icons.flag_outlined,
                  activeIcon: Icons.flag_rounded,
                  label: appText(context, 'Goals', 'اہداف'),
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
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: Theme.of(context).colorScheme.onPrimary,
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
                  label: appText(context, 'Loans', 'قرضے'),
                ),
                _navItem(
                  index: 5,
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart_rounded,
                  label: appText(context, 'Stats', 'اعدادوشمار'),
                ),
                _navItem(
                  index: 6,
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: appText(context, 'Txns', 'لین دین'),
                ),
                _navItem(
                  index: 7,
                  icon: Icons.account_balance_outlined,
                  activeIcon: Icons.account_balance_rounded,
                  label: appText(context, 'Wallets', 'والٹس'),
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
                offset: Offset(0, index == 0 ? -1.25 : 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                        child: Icon(
                          isSelected ? activeIcon : icon,
                          size: 22,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).hintColor,
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
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).hintColor,
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
  void _selectType(String type) {
    setState(() => selectedType = type);
  }

  Widget _buildQuickEntryForm() {
    return TransactionEntryForm(
      key: ValueKey(selectedType),
      transactionType: selectedType,
    );
  }

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
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
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
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          appText(context, 'Quick Add', 'فوری اندراج'),
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: Theme.of(context).hintColor,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      _transactionTab(
                        title: appText(context, 'Income', 'آمدنی'),
                        subtitle: appText(context, 'Received', 'وصولی'),
                        value: 'Income',
                        icon: Icons.south_west_rounded,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                      _transactionTab(
                        title: appText(context, 'Expense', 'اخراجات'),
                        subtitle: appText(context, 'Spent', 'خرچ'),
                        value: 'Expense',
                        icon: Icons.north_east_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      _transactionTab(
                        title: appText(context, 'Transfer', 'منتقلی'),
                        subtitle: appText(context, 'Wallets', 'والٹس'),
                        value: 'Transfer',
                        icon: Icons.swap_horiz_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      _transactionTab(
                        title: appText(context, 'Loan', 'قرض'),
                        subtitle: appText(context, 'New loan', 'نیا قرض'),
                        value: 'Loan',
                        icon: Icons.handshake_outlined,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 4),
                      _transactionTab(
                        title: appText(context, 'Asset', 'اثاثہ'),
                        subtitle: appText(context, 'New asset', 'نیا اثاثہ'),
                        value: 'Asset',
                        icon: Icons.real_estate_agent_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildQuickEntryForm()),
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
    required String value,
  }) {
    final selected = selectedType == value;
    return Expanded(
      child: InkWell(
        onTap: () => _selectType(value),
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 58,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.11) : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? color : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: selected ? color : Theme.of(context).hintColor),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: selected ? color : Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 1),
              SizedBox(
                height: 18,
                child: Text(
                  subtitle,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 7.8,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).hintColor,
                  ),
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
