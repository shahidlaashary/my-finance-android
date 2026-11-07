
class FinanceCategory {
  final int? id;
  final String name;
  final String type;
  final String icon;
  final int? parentId;
  final bool isDeleted;

  const FinanceCategory({
    this.id,
    required this.name,
    required this.type,
    this.icon = 'category',
    this.parentId,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'icon': icon,
      'parent_id': parentId,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory FinanceCategory.fromMap(Map<String, dynamic> map) {
    return FinanceCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: map['type'] as String,
      icon: map['icon'] as String? ?? 'category',
      parentId: map['parent_id'] as int?,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
  }
}
