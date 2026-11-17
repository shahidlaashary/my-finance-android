class LoansModel {
  final int? id;
  final int? partyId;
  final String loanType;
  final double amount;
  final double remainingAmount;
  final int walletId;
  final String lendingDate;
  final String? dueDate;
  final String notes;
  final String status;
  final String createdAt;

  const LoansModel({
    this.id,
    required this.partyId,
    this.loanType = 'given',
    required this.amount,
    required this.remainingAmount,
    required this.walletId,
    required this.lendingDate,
    this.dueDate,
    this.notes = '',
    this.status = 'active',
    required this.createdAt,
  });

  bool get isPaid => remainingAmount <= 0;

  bool get isOverdue {
    if (isPaid || dueDate == null || dueDate!.isEmpty) return false;
    final due = DateTime.tryParse(dueDate!);
    if (due == null) return false;
    final today = DateTime.now();
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  double get repaidAmount =>
      (amount - remainingAmount).clamp(0, amount).toDouble();

  Map<String, dynamic> toMap() => {
        'id': id,
        'party_id': partyId,
        'loan_type': loanType,
        'amount': amount,
        'remaining_amount': remainingAmount,
        'wallet_id': walletId,
        'lending_date': lendingDate,
        'due_date': dueDate,
        'notes': notes,
        'status': status,
        'created_at': createdAt,
      };

  factory LoansModel.fromMap(Map<String, dynamic> map) => LoansModel(
        id: map['id'] as int?,
        partyId: map['party_id'] as int?,
        loanType: map['loan_type'] as String? ?? 'given',
        amount: (map['amount'] as num).toDouble(),
        remainingAmount: (map['remaining_amount'] as num).toDouble(),
        walletId: map['wallet_id'] as int,
        lendingDate: map['lending_date'] as String,
        dueDate: map['due_date'] as String?,
        notes: map['notes'] as String? ?? '',
        status: map['status'] as String? ?? 'active',
        createdAt: map['created_at'] as String,
      );

  LoansModel copyWith({
    int? id,
    int? partyId,
    String? loanType,
    double? amount,
    double? remainingAmount,
    int? walletId,
    String? lendingDate,
    String? dueDate,
    String? notes,
    String? status,
    String? createdAt,
  }) =>
      LoansModel(
        id: id ?? this.id,
        partyId: partyId ?? this.partyId,
        loanType: loanType ?? this.loanType,
        amount: amount ?? this.amount,
        remainingAmount: remainingAmount ?? this.remainingAmount,
        walletId: walletId ?? this.walletId,
        lendingDate: lendingDate ?? this.lendingDate,
        dueDate: dueDate ?? this.dueDate,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
}
