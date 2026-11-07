
import 'package:flutter/material.dart';

import '../models/finance_category.dart';
import '../services/category_service.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Income'),
            Tab(text: 'Expenses'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          CategoryList(type: 'income'),
          CategoryList(type: 'expense'),
        ],
      ),
    );
  }
}

class CategoryList extends StatefulWidget {
  final String type;

  const CategoryList({super.key, required this.type});

  @override
  State<CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<CategoryList> {
  List<FinanceCategory> categories = [];
  final Map<int, List<FinanceCategory>> subcategories = {};
  bool loading = true;

  static const icons = [
    '💰', '🍔', '🏠', '🚗', '🛍️',
    '💊', '🎓', '💼', '🎁', '📱',
    '✈️', '🏦', '📦', '🎯', '💡',
  ];

  @override
  void initState() {
    super.initState();
    loadCategories();
  }

  Future<void> loadCategories() async {
    setState(() => loading = true);

    try {
      final result =
          await CategoryService.getCategories(widget.type);

      final Map<int, List<FinanceCategory>> children = {};

      for (final category in result) {
        if (category.id == null) continue;

        children[category.id!] =
            await CategoryService.getCategories(
          widget.type,
          parentId: category.id,
        );
      }

      if (!mounted) return;

      setState(() {
        categories = result;
        subcategories
          ..clear()
          ..addAll(children);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading categories: $e')),
      );
    }
  }

  Future<void> editCategory({
    FinanceCategory? category,
    int? parentId,
  }) async {
    final nameController =
        TextEditingController(text: category?.name ?? '');

    String selectedIcon = category?.icon ?? icons.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            return AlertDialog(
              title: Text(
                category == null
                    ? parentId == null
                        ? 'Add Category'
                        : 'Add Subcategory'
                    : 'Edit Category',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: icons.map((icon) {
                        return InkWell(
                          onTap: () =>
                              updateDialog(() => selectedIcon = icon),
                          child: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: selectedIcon == icon
                                  ? Theme.of(context)
                                      .colorScheme.primaryContainer
                                  : Colors.grey.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 22),
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
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;

                    final item = FinanceCategory(
                      id: category?.id,
                      name: name,
                      type: widget.type,
                      icon: selectedIcon,
                      parentId: category?.parentId ?? parentId,
                    );

                    if (category == null) {
                      await CategoryService.addCategory(item);
                    } else {
                      await CategoryService.updateCategory(item);
                    }

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();

    if (saved == true) await loadCategories();
  }

  Future<void> deleteCategory(FinanceCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category?'),
        content: const Text(
          'The category will be hidden. Existing transaction records '
          'will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && category.id != null) {
      await CategoryService.deleteCategory(category.id!);
      await loadCategories();
    }
  }

  Widget categoryTile(FinanceCategory category) {
    final children = subcategories[category.id] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              child: Text(
                category.icon,
                style: const TextStyle(fontSize: 21),
              ),
            ),
            title: Text(
              category.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  editCategory(category: category);
                } else if (value == 'delete') {
                  deleteCategory(category);
                } else if (value == 'add') {
                  editCategory(parentId: category.id);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'add',
                  child: Text('Add Subcategory'),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
            ),
          ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 8),
              child: Column(
                children: children.map((child) {
                  return ListTile(
                    dense: true,
                    leading: Text(
                      child.icon,
                      style: const TextStyle(fontSize: 19),
                    ),
                    title: Text(child.name),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          editCategory(category: child);
                        } else if (value == 'delete') {
                          deleteCategory(child);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : categories.isEmpty
                  ? const Center(child: Text('No categories yet'))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: categories.map(categoryTile).toList(),
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => editCategory(),
                icon: const Icon(Icons.add),
                label: const Text('Add Category'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
