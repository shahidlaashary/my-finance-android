class RecurringTransactionModel {
  final int? id;
  final String title;
  final String type;
  final double amount;
  final int walletId;
  final int? toWalletId;
  final int? categoryId;
  final String note;
  final String frequency;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? nextRunDate;
  final bool isActive;
  final DateTime? createdAt;

  const RecurringTransactionModel({
    this.id,
    required this.title,
    required this.type,
    required this.amount,
    required this.walletId,
    this.toWalletId,
    this.categoryId,
    this.note = '',
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.nextRunDate,
    this.isActive = true,
    this.createdAt,
  });

  bool get isTransfer => type.toLowerCase() == 'transfer';

  bool get hasEnded {
    if (endDate == null) return false;

    final now = DateTime.now();

    return DateTime(endDate!.year, endDate!.month, endDate!.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  factory RecurringTransactionModel.fromMap(
    Map<String, dynamic> map,
  ) {
    return RecurringTransactionModel(
      id: map['id'] as int?,
      title: (map['title'] ?? '').toString(),
      type: (map['type'] ?? 'Expense').toString(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      walletId: (map['wallet_id'] as num?)?.toInt() ?? 0,
      toWalletId: (map['to_wallet_id'] as num?)?.toInt(),
      categoryId: (map['category_id'] as num?)?.toInt(),
      note: (map['note'] ?? '').toString(),
      frequency: (map['frequency'] ?? 'Monthly').toString(),
      startDate: DateTime.tryParse(
            (map['start_date'] ?? '').toString(),
          ) ??
          DateTime.now(),
      endDate: map['end_date'] == null
          ? null
          : DateTime.tryParse(map['end_date'].toString()),
      nextRunDate: map['next_run_date'] == null
          ? null
          : DateTime.tryParse(map['next_run_date'].toString()),
      isActive: (map['is_active'] as num?)?.toInt() != 0,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'type': type,
      'amount': amount,
      'wallet_id': walletId,
      'to_wallet_id': toWalletId,
      'category_id': categoryId,
      'note': note,
      'frequency': frequency,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'next_run_date': nextRunDate?.toIso8601String(),
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  RecurringTransactionModel copyWith({
    int? id,
    String? title,
    String? type,
    double? amount,
    int? walletId,
    int? toWalletId,
    int? categoryId,
    String? note,
    String? frequency,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? nextRunDate,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return RecurringTransactionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      walletId: walletId ?? this.walletId,
      toWalletId: toWalletId ?? this.toWalletId,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      nextRunDate: nextRunDate ?? this.nextRunDate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
