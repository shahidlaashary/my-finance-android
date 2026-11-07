
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
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Income'),
            Tab(text: 'Expenses'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CategoryList(type: 'income'),
          _CategoryList(type: 'expense'),
        ],
      ),
    );
  }
}

class _CategoryList extends StatefulWidget {
  final String type;

  const _CategoryList({required this.type});

  @override
  State<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<_CategoryList> {
  List<FinanceCategory> categories = [];
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

    final result =
        await CategoryService.getCategories(widget.type);

    if (!mounted) return;

    setState(() {
      categories = result;
      loading = false;
    });
  }

  Future<void> openEditor({
    FinanceCategory? category,
    int? parentId,
  }) async {
    final nameController =
        TextEditingController(text: category?.name ?? '');

    String selectedIcon = category?.icon ?? icons.first;

    final result = await showDialog<bool>(
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
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Category Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Choose Icon'),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: icons.map((icon) {
                        final selected = selectedIcon == icon;

                        return InkWell(
                          onTap: () => updateDialog(
                            () => selectedIcon = icon,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Colors.grey.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 23),
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

    if (result == true) {
      await loadCategories();
    }
  }

  Future<void> deleteCategory(FinanceCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category?'),
        content: const Text(
          'This category will be hidden. Existing financial records '
          'will not be physically deleted.',
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

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: categories.isEmpty
              ? const Center(
                  child: Text('No categories added yet'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            category.icon,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        title: Text(
                          category.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          widget.type == 'income'
                              ? 'Income category'
                              : 'Expense category',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              openEditor(category: category);
                            } else if (value == 'delete') {
                              deleteCategory(category);
                            } else if (value == 'sub') {
                              openEditor(parentId: category.id);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'sub',
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
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => openEditor(),
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
