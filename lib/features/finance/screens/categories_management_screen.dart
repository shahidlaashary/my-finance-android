import 'package:flutter/material.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/core/database/finance_database.dart';

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
