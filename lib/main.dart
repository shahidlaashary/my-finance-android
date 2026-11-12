
import 'package:flutter/material.dart';
import 'package:my_finance/app/my_finance_app.dart';
import 'package:my_finance/features/dashboard/screens/home_screen.dart' show HomePage;
import 'package:my_finance/app/screens/more_features_screen.dart' show AppSettingsScreen;
import 'package:my_finance/core/theme/app_colors.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

import 'package:my_finance/core/startup/app_bootstrap_service.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/finance/services/budgets_service.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/features/finance/models/budgets_model.dart';
import 'package:my_finance/core/models/attachment_model.dart';
import 'package:my_finance/features/finance/screens/assets_screen.dart';
import 'package:my_finance/features/finance/screens/budgets_screen.dart';
import 'package:my_finance/features/finance/screens/goals_screen.dart';
import 'package:my_finance/features/finance/screens/loans_screen.dart';
import 'package:my_finance/features/finance/screens/stats_screen.dart';
import 'package:my_finance/features/finance/screens/transactions_screen.dart';
import 'package:my_finance/features/documents/screens/my_documents_screen.dart';
import 'package:my_finance/features/vehicles/screens/vehicles_screen.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:my_finance/features/finance/screens/wallets_screen.dart' show WalletsPage;

// ============================================================
// Naya database aur wallet ka intizam
// ============================================================

Future<void> main() async {
  await AppBootstrapService.initialize();

  runApp(MyFinanceApp(
    home: const MainScreen(),
    routes: {'/settings': (_) => const MoreFeaturesPage()},
  ));
}

// ============================================================
// Database ka nizam
// ============================================================

// App composition is maintained in lib/app/my_finance_app.dart.


// ============================================================
// Main screen aur 9 jagah wali bottom navigation
// ============================================================

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
    KeyedSubtree(key: ValueKey('assets-$_refreshVersion'), child: const AssetsPage()),
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

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AssetsScreen();
  }
}

// ============================================================
// Loans ka safha
// ============================================================

class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleFeaturePage(title: 'Loans');
  }
}

// ============================================================
// Mazeed sahuliyat
// ============================================================

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
                      if (feature['title'] == 'My Documents') {
                        return const MyDocumentsScreen();
                      }
                      return SimpleFeaturePage(
                        title: feature['title'] as String,
                      );
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

// ============================================================
// Categories ka intizam
// ============================================================

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  String selectedType = 'Income';
  List<Map<String, dynamic>> categories = [];
  bool loading = true;

  final List<IconData> availableIcons = [
    Icons.account_balance_wallet_outlined,
    Icons.business_center_outlined,
    Icons.trending_up_outlined,
    Icons.card_giftcard_outlined,
    Icons.home_work_outlined,
    Icons.laptop_mac_outlined,
    Icons.savings_outlined,
    Icons.restaurant_outlined,
    Icons.directions_car_outlined,
    Icons.shopping_bag_outlined,
    Icons.receipt_long_outlined,
    Icons.health_and_safety_outlined,
    Icons.school_outlined,
    Icons.checkroom_outlined,
    Icons.phone_android_outlined,
    Icons.people_outline,
    Icons.flight_outlined,
    Icons.movie_outlined,
    Icons.volunteer_activism_outlined,
    Icons.more_horiz_rounded,
  ];

  Color get categoryColor =>
      selectedType == 'Income' ? AppColors.income : const Color(0xFFD58B36);

  @override
  void initState() {
    super.initState();
    loadCategories();
  }

  Future<void> loadCategories() async {
    setState(() => loading = true);
    final result = await FinanceDB.instance.getCategories(selectedType);
    if (!mounted) return;
    setState(() {
      categories = result;
      loading = false;
    });
  }

  Future<void> changeType(String type) async {
    if (type == selectedType) return;
    setState(() {
      selectedType = type;
      loading = true;
    });
    final result = await FinanceDB.instance.getCategories(type);
    if (!mounted) return;
    setState(() {
      categories = result;
      loading = false;
    });
  }

  Future<void> persistCategories() async {
    await FinanceDB.instance.saveCategories(selectedType, categories);
  }

  Future<void> showCategoryDialog({int? index}) async {
    final editing = index != null;
    final existing = editing ? categories[index] : null;
    final nameController = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    int selectedIcon =
        existing?['icon'] as int? ?? availableIcons.first.codePoint;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(editing ? 'Edit Category' : 'Add Category'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Category Name',
                      prefixIcon: const Icon(Icons.category_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Choose Icon',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableIcons.map((icon) {
                      final selected = icon.codePoint == selectedIcon;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => dialogSetState(
                          () => selectedIcon = icon.codePoint,
                        ),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: selected
                                ? categoryColor.withValues(alpha: 0.16)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? categoryColor
                                  : const Color(0xFFE5EBE7),
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: 21,
                            color: selected ? categoryColor : AppColors.muted,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(dialogContext, {
                    'name': name,
                    'icon': selectedIcon,
                  });
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: Text(editing ? 'Save' : 'Add'),
              ),
            ],
          ),
        );
      },
    );

    nameController.dispose();
    if (result == null) return;

    final duplicate = categories.asMap().entries.any((entry) =>
        entry.key != index &&
        (entry.value['name'] as String).toLowerCase() ==
            (result['name'] as String).toLowerCase());
    if (duplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This category already exists.')),
      );
      return;
    }

    setState(() {
      if (editing) {
        categories[index] = result;
      } else {
        categories.add(result);
      }
    });
    await persistCategories();
  }

  Future<void> deleteCategory(int index) async {
    final name = categories[index]['name'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Kya aap "$name" category delete karna chahte hain?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => categories.removeAt(index));
    await persistCategories();
  }

  Future<void> reorderCategories(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = categories.removeAt(oldIndex);
      categories.insert(newIndex, item);
    });
    await persistCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Categories',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Category',
            onPressed: () => showCategoryDialog(),
            icon: const Icon(Icons.add_rounded, size: 29),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(child: _categoryTab('Income', Icons.trending_up_rounded)),
                  Expanded(child: _categoryTab('Expense', Icons.account_balance_wallet_outlined)),
                ],
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : categories.isEmpty
                    ? const Center(
                        child: Text(
                          'No categories yet. Tap + to add one.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: categories.length,
                        onReorder: reorderCategories,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final iconCode = category['icon'] as int;
                          return Container(
                            key: ValueKey(
                              '${selectedType}_${category['name']}_$index',
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFE9EEEB)),
                              ),
                            ),
                            child: SizedBox(
                              height: 82,
                              child: Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const SizedBox(
                                      width: 28,
                                      child: Icon(
                                        Icons.drag_indicator_rounded,
                                        color: Color(0xFF9AA49F),
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: categoryColor.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      IconData(iconCode, fontFamily: 'MaterialIcons'),
                                      color: categoryColor,
                                      size: 25,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      category['name'] as String,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit',
                                    onPressed: () => showCategoryDialog(index: index),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: AppColors.muted,
                                      size: 23,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: () => deleteCategory(index),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppColors.muted,
                                      size: 23,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTab(String type, IconData icon) {
    final selected = selectedType == type;
    final color = type == 'Income'
        ? AppColors.income
        : const Color(0xFFD58B36);
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () => changeType(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: selected ? Colors.white : AppColors.text),
            const SizedBox(width: 8),
            Text(
              type,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Feature ka sada safha
// ============================================================

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
              const Text(
                'This section is ready for its feature implementation.',
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
// Transactions database ke operations
// ============================================================

extension FinanceTransactionOperations on FinanceDB {
  // Transaction save karna aur linked wallet ka balance update karna.
  Future<int> addTransaction({
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    double? toAmount,
    double? exchangeRate,
    String category = '',
    String note = '',
    DateTime? date,
    double transferFee = 0,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount zero se zyada hona chahiye.');
    }
    if (!transferFee.isFinite || transferFee < 0 ||
        (type != 'Transfer' && transferFee > 0)) {
      throw Exception('Transfer fee durust nahi hai.');
    }

    final transactionDate = date ?? DateTime.now();
    final now = DateTime.now().toIso8601String();

    final transactionId = await db.transaction((txn) async {
      final sourceRows = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      if (sourceRows.isEmpty) {
        throw Exception('Selected wallet nahi mila.');
      }

      final source = sourceRows.first;
      final sourceBalance = (source['balance'] as num).toDouble();

      final totalSourceDeduction = amount + (type == 'Transfer' ? transferFee : 0);
      if (type == 'Expense' || type == 'Transfer') {
        if (sourceBalance < totalSourceDeduction) {
          throw Exception('Wallet mein itna balance available nahi hai.');
        }
      }

      double? finalToAmount;
      double? finalRate;

      if (type == 'Transfer') {
        if (toWalletId == null || toWalletId == walletId) {
          throw Exception('Do different wallets select karein.');
        }

        final destinationRows = await txn.query(
          'wallets',
          where: 'id = ?',
          whereArgs: [toWalletId],
          limit: 1,
        );

        if (destinationRows.isEmpty) {
          throw Exception('Destination wallet nahi mila.');
        }

        final destination = destinationRows.first;
        final sourceCurrency = source['currency'] as String;
        final destinationCurrency = destination['currency'] as String;

        if (sourceCurrency == destinationCurrency) {
          finalToAmount = amount;
          finalRate = 1;
        } else {
          if (toAmount == null || toAmount <= 0) {
            throw Exception(
              'Different currencies ke transfer ke liye '
              'destination amount enter karein.',
            );
          }

          finalToAmount = toAmount;
          finalRate = finalToAmount / amount;
        }

        final destinationBalance =
            (destination['balance'] as num).toDouble();

        // Dono wallets ke balances aik hi database transaction mein update hote hain.
        await txn.update(
          'wallets',
          {'balance': sourceBalance - totalSourceDeduction},
          where: 'id = ?',
          whereArgs: [walletId],
        );

        await txn.update(
          'wallets',
          {'balance': destinationBalance + finalToAmount},
          where: 'id = ?',
          whereArgs: [toWalletId],
        );
      } else if (type == 'Income') {
        await txn.update(
          'wallets',
          {'balance': sourceBalance + amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      } else if (type == 'Expense') {
        await txn.update(
          'wallets',
          {'balance': sourceBalance - amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      } else {
        throw Exception('Transaction type valid nahi hai.');
      }

      final transactionId = await txn.insert('transactions', {
        'type': type,
        'amount': amount,
        'wallet_id': walletId,
        'to_wallet_id': toWalletId,
        'to_amount': finalToAmount,
        'exchange_rate': finalRate,
        'balance_delta': null,
        'category': category,
        'note': note,
        'date': transactionDate.toIso8601String(),
        'created_at': now,
      });

      if (type == 'Transfer' && transferFee > 0) {
        await txn.insert(
          'app_settings',
          {
            'setting_key': 'transaction_transfer_fee_$transactionId',
            'setting_value': transferFee.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      return transactionId;
    });
    AppRefreshController.notifyChanged();
    return transactionId;
  }

  // Transactions ki history hasil karna.
  Future<List<Map<String, dynamic>>> getTransactions() async {
    return db.rawQuery('''
      SELECT
        transactions.*,
        source.name AS wallet_name,
        source.currency AS wallet_currency,
        destination.name AS to_wallet_name,
        destination.currency AS to_wallet_currency,
        COALESCE((
          SELECT CAST(settings.setting_value AS REAL)
          FROM app_settings AS settings
          WHERE settings.setting_key = 'transaction_transfer_fee_' || transactions.id
          LIMIT 1
        ), 0) AS transfer_fee
      FROM transactions
      LEFT JOIN wallets AS source
              ON transactions.wallet_id = source.id
      LEFT JOIN wallets AS destination
        ON transactions.to_wallet_id = destination.id
      ORDER BY transactions.date DESC, transactions.id DESC
    ''');
  }

  // Transaction delete hone par wallet balances ko pehli halat mein lana.
  Future<void> deleteTransaction(int id) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) return;

      final item = rows.first;
      final type = item['type'] as String;
      final feeRows = await txn.query(
        'app_settings',
        columns: ['setting_value'],
        where: 'setting_key = ?',
        whereArgs: ['transaction_transfer_fee_$id'],
        limit: 1,
      );
      final transferFee = feeRows.isEmpty
          ? 0.0
          : (double.tryParse(feeRows.first['setting_value']?.toString() ?? '') ?? 0.0);
      final amount = (item['amount'] as num).toDouble();
      final walletId = item['wallet_id'] as int;

      final sourceRows = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      if (sourceRows.isNotEmpty) {
        final sourceBalance =
            (sourceRows.first['balance'] as num).toDouble();

        if (type == 'Income') {
          await txn.update(
            'wallets',
            {'balance': sourceBalance - amount},
            where: 'id = ?',
            whereArgs: [walletId],
          );
        } else if (type == 'Expense') {
          await txn.update(
            'wallets',
            {'balance': sourceBalance + amount},
            where: 'id = ?',
            whereArgs: [walletId],
          );
        } else if (type == 'Transfer') {
          await txn.update(
            'wallets',
            {'balance': sourceBalance + amount + transferFee},
            where: 'id = ?',
            whereArgs: [walletId],
          );

          final destinationId = item['to_wallet_id'] as int?;
          final destinationAmount =
              (item['to_amount'] as num?)?.toDouble() ?? amount;

          if (destinationId != null) {
            final destinationRows = await txn.query(
              'wallets',
              where: 'id = ?',
              whereArgs: [destinationId],
              limit: 1,
            );

            if (destinationRows.isNotEmpty) {
              final destinationBalance =
                  (destinationRows.first['balance'] as num).toDouble();

              await txn.update(
                'wallets',
                {'balance': destinationBalance - destinationAmount},
                where: 'id = ?',
                whereArgs: [destinationId],
              );
            }
          }
        } else if (type == 'Adjustment') {
          final delta =
              (item['balance_delta'] as num?)?.toDouble() ?? 0;

          await txn.update(
            'wallets',
            {'balance': sourceBalance - delta},
            where: 'id = ?',
            whereArgs: [walletId],
          );
        }
      }

      await txn.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'app_settings',
        where: 'setting_key = ?',
        whereArgs: ['transaction_transfer_fee_$id'],
      );
    });
    AppRefreshController.notifyChanged();
  }
}

// ============================================================
// Transaction add karne ka form
// ============================================================

class TransactionEntryForm extends StatefulWidget {
  final String transactionType;

  const TransactionEntryForm({
    super.key,
    required this.transactionType,
  });

  @override
  State<TransactionEntryForm> createState() =>
      _TransactionEntryFormState();
}

class _TransactionEntryFormState extends State<TransactionEntryForm> {
  final formKey = GlobalKey<FormState>();

  final amountController = TextEditingController();
  final destinationAmountController = TextEditingController();
  final transferFeeController = TextEditingController();
  final noteController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  List<Map<String, dynamic>> wallets = [];
  List<Map<String, dynamic>> transactionCategories = [];

  int? selectedWalletId;
  int? selectedDestinationWalletId;

  DateTime selectedDate = DateTime.now();
  String selectedRecurring = 'None';
  XFile? selectedNoteImage;

  bool saving = false;
  bool loading = true;
  bool transferFeeEnabled = false;

  String selectedCategory = '';

  bool get isTransfer => widget.transactionType == 'Transfer';

  @override
  void initState() {
    super.initState();
    loadWallets();
  }

  @override
  void dispose() {
    amountController.dispose();
    destinationAmountController.dispose();
    transferFeeController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> loadWallets() async {
    final result = await FinanceDB.instance.getWallets();
    final categories = isTransfer
        ? <Map<String, dynamic>>[]
        : await FinanceDB.instance.getCategories(widget.transactionType);

    if (!mounted) return;

    setState(() {
      wallets = result;
      transactionCategories = categories;
      loading = false;

      if (wallets.isNotEmpty) {
        selectedWalletId = wallets.first['id'] as int;
        if (isTransfer && wallets.length > 1) {
          selectedDestinationWalletId = wallets[1]['id'] as int;
        }
      }

      if (transactionCategories.isNotEmpty &&
          !transactionCategories.any(
            (category) => category['name'] == selectedCategory,
          )) {
        selectedCategory = transactionCategories.first['name'] as String;
      }
    });
  }

  Map<String, dynamic>? get selectedWallet {
    for (final wallet in wallets) {
      if (wallet['id'] == selectedWalletId) return wallet;
    }
    return null;
  }

  Map<String, dynamic>? get selectedDestinationWallet {
    for (final wallet in wallets) {
      if (wallet['id'] == selectedDestinationWalletId) return wallet;
    }
    return null;
  }

  InputDecoration decoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null || !mounted) return;

    setState(() {
      selectedDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        selectedDate.hour,
        selectedDate.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDate),
    );

    if (picked == null || !mounted) return;

    setState(() {
      selectedDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _showRecurringOptions() async {
    const options = ['None', 'Daily', 'Weekly', 'Monthly', 'Yearly'];

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 15),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recurring',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              ...options.map(
                (option) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option),
                  trailing: selectedRecurring == option
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : const Icon(Icons.circle_outlined, color: AppColors.muted),
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => selectedRecurring = selected);
    }
  }

  Widget _buildDateTimeRecurringBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Date', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 15),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            DateFormat('dd MMM yyyy').format(selectedDate),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 34, color: Theme.of(context).dividerColor),
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('Time', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.access_time_rounded, size: 15),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            DateFormat('h:mm a').format(selectedDate),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 34, color: Theme.of(context).dividerColor),
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _showRecurringOptions,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Recurring', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(Icons.repeat_rounded, size: 15),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            selectedRecurring,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountField() {
    return TextFormField(
      controller: amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: decoration('Amount', icon: Icons.payments_outlined),
      validator: (value) {
        final amount = double.tryParse(value?.trim() ?? '');
        if (amount == null || amount <= 0) {
          return 'Valid amount enter karein.';
        }
        return null;
      },
    );
  }

  Widget _walletField() {
    return DropdownButtonFormField<int>(
      value: selectedWalletId,
      isExpanded: true,
      decoration: decoration(
        isTransfer ? 'From Wallet' : 'Wallet',
        icon: Icons.account_balance_wallet_outlined,
      ),
      items: wallets.map((wallet) => DropdownMenuItem<int>(
        value: wallet['id'] as int,
        child: Text(
          '${wallet['name']} (${wallet['currency']})',
          overflow: TextOverflow.ellipsis,
        ),
      )).toList(),
      onChanged: (value) => setState(() => selectedWalletId = value),
    );
  }

  Widget _destinationWalletField() {
    return DropdownButtonFormField<int>(
      value: selectedDestinationWalletId,
      isExpanded: true,
      decoration: decoration(
        'To Wallet',
        icon: Icons.account_balance_outlined,
      ),
      items: wallets.where((wallet) => wallet['id'] != selectedWalletId)
          .map((wallet) => DropdownMenuItem<int>(
            value: wallet['id'] as int,
            child: Text(
              '${wallet['name']} (${wallet['currency']})',
              overflow: TextOverflow.ellipsis,
            ),
          )).toList(),
      onChanged: (value) => setState(() => selectedDestinationWalletId = value),
    );
  }

  Widget _categoryField() {
    return DropdownButtonFormField<String>(
      value: transactionCategories.any(
        (category) => category['name'] == selectedCategory,
      ) ? selectedCategory : null,
      isExpanded: true,
      decoration: decoration('Category', icon: Icons.category_outlined),
      hint: const Text('Select Category'),
      items: transactionCategories.map((category) {
        final iconCode = category['icon'] as int;
        return DropdownMenuItem<String>(
          value: category['name'] as String,
          child: Row(
            children: [
              Icon(
                IconData(iconCode, fontFamily: 'MaterialIcons'),
                size: 19,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) setState(() => selectedCategory = value);
      },
    );
  }

  Widget _notesField() {
    return TextFormField(
      controller: noteController,
      maxLines: 2,
      decoration: decoration('Notes (Optional)', icon: Icons.notes_rounded).copyWith(
        suffixIcon: IconButton(
          tooltip: selectedNoteImage == null ? 'Attach image' : 'Change image',
          icon: Icon(
            selectedNoteImage == null
                ? Icons.add_photo_alternate_outlined
                : Icons.image_rounded,
            color: AppColors.primary,
          ),
          onPressed: _pickNoteImage,
        ),
      ),
    );
  }

  Future<void> _pickNoteImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => selectedNoteImage = picked);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image select nahi ho saki: $e')),
      );
    }
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) return;

    if (selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallet select karein.')),
      );
      return;
    }

    double? destinationAmount;
    double transferFee = 0;

    if (isTransfer) {
      if (transferFeeEnabled) {
        transferFee = double.tryParse(transferFeeController.text.trim()) ?? 0;
        if (!transferFee.isFinite || transferFee <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Valid transfer fee enter karein.')),
          );
          return;
        }
      }
      if (selectedDestinationWalletId == null ||
          selectedDestinationWalletId == selectedWalletId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Different destination wallet select karein.')),
        );
        return;
      }

      final sourceCurrency = selectedWallet?['currency'];
      final destinationCurrency = selectedDestinationWallet?['currency'];

      if (sourceCurrency != destinationCurrency) {
        destinationAmount = double.tryParse(destinationAmountController.text.trim());
        if (destinationAmount == null || destinationAmount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Destination amount enter karein.')),
          );
          return;
        }
      }
    }

    setState(() => saving = true);

    try {
      final transactionId = await FinanceDB.instance.addTransaction(
        type: widget.transactionType,
        amount: amount,
        walletId: selectedWalletId!,
        toWalletId: isTransfer ? selectedDestinationWalletId : null,
        toAmount: destinationAmount,
        transferFee: transferFee,
        category: isTransfer ? '' : selectedCategory,
        note: noteController.text.trim(),
        date: selectedDate,
      );

      await FinanceDB.instance.db.insert(
        'app_settings',
        {
          'setting_key': 'transaction_recurrence_$transactionId',
          'setting_value': selectedRecurring,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      String? attachmentWarning;
      if (selectedNoteImage != null) {
        try {
          await AttachmentService.addAttachment(
            ownerType: AttachmentOwnerTypes.transaction,
            ownerId: transactionId,
            sourcePath: selectedNoteImage!.path,
            originalFileName: selectedNoteImage!.name,
          );
        } catch (e) {
          attachmentWarning = e.toString().replaceFirst('Exception: ', '');
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            attachmentWarning == null
                ? 'Transaction successfully saved.'
                : 'Transaction saved, but image could not be attached: $attachmentWarning',
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );

      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.transactionType == 'Income';
    final accentColor = isIncome
        ? AppColors.income
        : isTransfer
            ? AppColors.primary
            : AppColors.expense;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (wallets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Pehle ek wallet add karein.'),
        ),
      );
    }

    return Form(
      key: formKey,
      child: SingleChildScrollView(
        primary: false,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDateTimeRecurringBox(),
            const SizedBox(height: 14),
            if (isTransfer) ...[
              _amountField(),
              const SizedBox(height: 12),
              _walletField(),
              const SizedBox(height: 12),
              _destinationWalletField(),
              if (selectedWallet != null &&
                  selectedDestinationWallet != null &&
                  selectedWallet!['currency'] != selectedDestinationWallet!['currency']) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: destinationAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: decoration(
                    'Destination Amount (${selectedDestinationWallet!['currency']})',
                    icon: Icons.currency_exchange_rounded,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (isTransfer) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFE2E9E5)),
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Transfer Fee',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Add an optional fee to this transfer',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: transferFeeEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (value) => setState(() {
                      transferFeeEnabled = value;
                      if (!value) transferFeeController.clear();
                    }),
                  ),
                ),
                if (transferFeeEnabled) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: transferFeeController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: decoration(
                      'Fee Amount (${selectedWallet?['currency'] ?? ''})',
                      icon: Icons.payments_outlined,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              _notesField(),
            ] else ...[
              _amountField(),
              const SizedBox(height: 12),
              _walletField(),
              const SizedBox(height: 12),
              _categoryField(),
              const SizedBox(height: 12),
              _notesField(),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : save,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      height: 21,
                      width: 21,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save Transaction',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Transactions ki history
// ============================================================

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<Map<String, dynamic>> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTransactions();
  }

  Future<void> loadTransactions() async {
    setState(() => loading = true);

    try {
      final result =
          await FinanceDB.instance.getTransactions();

      if (!mounted) return;

      setState(() {
        transactions = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> deleteTransaction(
    Map<String, dynamic> transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text(
          'Kya aap is transaction ko delete karna chahte hain? '
          'Wallet balance bhi reverse ho jayega.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FinanceDB.instance.deleteTransaction(
        transaction['id'] as int,
      );

      await loadTransactions();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: const Text(
          'Transactions',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        actions: buildMainSectionAppBarActions(context),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : transactions.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 55,
                        color: AppColors.primary,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No transactions yet',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadTransactions,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final item = transactions[index];

                      final type = item['type'] as String;
                      final amount =
                          (item['amount'] as num).toDouble();

                      final currency =
                          item['wallet_currency'] as String? ?? 'PKR';

                      final date = DateTime.tryParse(
                            item['date'] as String? ?? '',
                          ) ??
                          DateTime.now();

                      final isIncome = type == 'Income';
                      final isExpense = type == 'Expense';
                      final isTransfer = type == 'Transfer';

                      final color = isIncome
                          ? AppColors.income
                          : isExpense
                              ? AppColors.expense
                              : AppColors.primary;

                      final icon = isIncome
                          ? Icons.south_west_rounded
                          : isExpense
                              ? Icons.north_east_rounded
                              : Icons.swap_horiz_rounded;

                      final destinationName =
                          item['to_wallet_name'] as String?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.10),
                            child: Icon(icon, color: AppColors.primary),
                          ),
                          title: Text(
                            isTransfer
                                ? '${
                                    item['wallet_name'] ?? 'Wallet'
                                  } → ${destinationName ?? 'Wallet'}'
                                : (item['wallet_name'] ?? 'Wallet')
                                    .toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '$type • ${DateFormat('dd MMM yyyy').format(date)}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              if ((item['category'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text(
                                  item['category'] as String,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              if (isTransfer &&
                                  (item['transfer_fee'] as num? ?? 0).toDouble() > 0)
                                Text(
                                  'Transfer Fee: $currency ${NumberFormat('#,##0.##').format((item['transfer_fee'] as num).toDouble())}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              if ((item['note'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text(
                                  item['note'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isTransfer
                                    ? '$currency ${NumberFormat('#,##0.##').format(amount + ((item['transfer_fee'] as num?)?.toDouble() ?? 0))}'
                                    : '${isIncome ? '+' : isExpense ? '-' : ''}$currency ${NumberFormat('#,##0.##').format(amount)}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    deleteTransaction(item);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ============================================================
// Wallet ke options
// ============================================================

const List<String> walletTypes = [
  'Cash',
  'Bank',
  'Savings',
  'Current',
  'Credit Card',
  'Debit Card',
  'Digital Wallet',
  'Investment',
  'Other',
  'Custom',
];

const List<String> walletCurrencies = [
  'PKR',
  'USD',
  'GBP',
  'EUR',
  'AED',
  'SAR',
  'INR',
];

const List<IconData> walletIcons = [
  Icons.account_balance_wallet_outlined,
  Icons.account_balance_outlined,
  Icons.savings_outlined,
  Icons.credit_card_outlined,
  Icons.money_outlined,
  Icons.phone_android_outlined,
  Icons.trending_up_outlined,
  Icons.attach_money,
  Icons.payments_outlined,
  Icons.wallet_outlined,
  Icons.business_center_outlined,
  Icons.shopping_bag_outline