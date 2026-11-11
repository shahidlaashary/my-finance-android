class BudgetModel {
  final int? id;
  final String name;
  final String? category;
  final double limitAmount;
  final double spentAmount;
  final String period;
  final DateTime startDate;
  final DateTime endDate;
  final String currency;
  final bool isActive;
  final DateTime? createdAt;

  const BudgetModel({
    this.id,
    required this.name,
    this.category,
    required this.limitAmount,
    this.spentAmount = 0,
    this.period = 'Monthly',
    required this.startDate,
    required this.endDate,
    this.currency = 'PKR',
    this.isActive = true,
    this.createdAt,
  });

  double get remainingAmount {
    final remaining = limitAmount - spentAmount;
    return remaining > 0 ? remaining : 0;
  }

  double get progress {
    if (limitAmount <= 0) return 0;
    return (spentAmount / limitAmount).clamp(0.0, 1.0).toDouble();
  }

  bool get isExceeded => spentAmount > limitAmount;

  bool get isCurrentlyActive {
    if (!isActive) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  factory BudgetModel.fromMap(Map<String, dynamic> map) {
    return BudgetModel(
      id: map['id'] as int?,
      name: (map['name'] ?? '').toString(),
      category: map['category']?.toString(),
      limitAmount: (map['limit_amount'] as num?)?.toDouble() ?? 0,
      spentAmount: (map['spent_amount'] as num?)?.toDouble() ?? 0,
      period: (map['period'] ?? 'Monthly').toString(),
      startDate: DateTime.tryParse(
            (map['start_date'] ?? '').toString(),
          ) ??
          DateTime.now(),
      endDate: DateTime.tryParse(
            (map['end_date'] ?? '').toString(),
          ) ??
          DateTime.now(),
      currency: (map['currency'] ?? 'PKR').toString(),
      isActive: (map['is_active'] as num?)?.toInt() != 0,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'limit_amount': limitAmount,
      'spent_amount': spentAmount,
      'period': period,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'currency': currency,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  BudgetModel copyWith({
    int? id,
    String? name,
    String? category,
    double? limitAmount,
    double? spentAmount,
    String? period,
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return BudgetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.category,
      limitAmount: limitAmount ?? this.limitAmount,
      spentAmount: spentAmount ?? this.spentAmount,
      period: period ?? this.period,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      currency: currency ?? this.currency,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
