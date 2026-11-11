class SavingsGoalModel {
  final int? id;
  final String name;
  final double targetAmount;
  final double savedAmount;
  final DateTime? targetDate;
  final int? walletId;
  final String notes;
  final bool isCompleted;
  final DateTime? createdAt;

  const SavingsGoalModel({
    this.id,
    required this.name,
    required this.targetAmount,
    this.savedAmount = 0,
    this.targetDate,
    this.walletId,
    this.notes = '',
    this.isCompleted = false,
    this.createdAt,
  });

  double get remainingAmount {
    final remaining = targetAmount - savedAmount;
    return remaining > 0 ? remaining : 0;
  }

  double get progress {
    if (targetAmount <= 0) return 0;
    final value = savedAmount / targetAmount;
    return value.clamp(0.0, 1.0).toDouble();
  }

  bool get isOverdue {
    if (targetDate == null || isCompleted) return false;
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);
    final targetOnly = DateTime(
      targetDate!.year,
      targetDate!.month,
      targetDate!.day,
    );
    return targetOnly.isBefore(dateOnly);
  }

  factory SavingsGoalModel.fromMap(Map<String, dynamic> map) {
    return SavingsGoalModel(
      id: map['id'] as int?,
      name: (map['name'] ?? '').toString(),
      targetAmount: (map['target_amount'] as num?)?.toDouble() ?? 0,
      savedAmount: (map['saved_amount'] as num?)?.toDouble() ?? 0,
      targetDate: map['target_date'] == null
          ? null
          : DateTime.tryParse(map['target_date'].toString()),
      walletId: (map['wallet_id'] as num?)?.toInt(),
      notes: (map['notes'] ?? '').toString(),
      isCompleted: (map['is_completed'] as num?)?.toInt() == 1,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'target_amount': targetAmount,
      'saved_amount': savedAmount,
      'target_date': targetDate?.toIso8601String(),
      'wallet_id': walletId,
      'notes': notes,
      'is_completed': isCompleted ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  SavingsGoalModel copyWith({
    int? id,
    String? name,
    double? targetAmount,
    double? savedAmount,
    DateTime? targetDate,
    int? walletId,
    String? notes,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return SavingsGoalModel(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      savedAmount: savedAmount ?? this.savedAmount,
      targetDate: targetDate ?? this.targetDate,
      walletId: walletId ?? this.walletId,
      notes: notes ?? this.notes,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
