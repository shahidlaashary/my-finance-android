
class LoanModel {
  final int? id;
  final String borrowerName;
  final String? borrowerPhone;
  final double amount;
  final double remainingAmount;
  final int accountId;
  final String lendingDate;
  final String? dueDate;
  final String notes;
  final String status;
  final String createdAt;

  const LoanModel({
    this.id,
    required this.borrowerName,
    this.borrowerPhone,
    required this.amount,
    required this.remainingAmount,
    required this.accountId,
    required this.lendingDate,
    this.dueDate,
    this.notes = '',
    this.status = 'active',
    required this.createdAt,
  });

  bool get isPaid => remainingAmount <= 0;

  bool get isOverdue {
    if (isPaid || dueDate == null || dueDate!.isEmpty) {
      return false;
    }

    final due = DateTime.tryParse(dueDate!);

    if (due == null) return false;

    final today = DateTime.now();

    return due.isBefore(
      DateTime(today.year, today.month, today.day),
    );
  }

  double get repaidAmount {
    return (amount - remainingAmount).clamp(0, amount);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'borrower_name': borrowerName,
      'borrower_phone': borrowerPhone,
      'amount': amount,
      'remaining_amount': remainingAmount,
      'account_id': accountId,
      'lending_date': lendingDate,
      'due_date': dueDate,
      'notes': notes,
      'status': status,
      'created_at': createdAt,
    };
  }

  factory LoanModel.fromMap(Map<String, dynamic> map) {
    return LoanModel(
      id: map['id'] as int?,
      borrowerName: map['borrower_name'] as String,
      borrowerPhone: map['borrower_phone'] as String?,
      amount: (map['amount'] as num).toDouble(),
      remainingAmount:
          (map['remaining_amount'] as num).toDouble(),
      accountId: map['account_id'] as int,
      lendingDate: map['lending_date'] as String,
      dueDate: map['due_date'] as String?,
      notes: map['notes'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      createdAt: map['created_at'] as String,
    );
  }

  LoanModel copyWith({
    int? id,
    String? borrowerName,
    String? borrowerPhone,
    double? amount,
    double? remainingAmount,
    int? accountId,
    String? lendingDate,
    String? dueDate,
    String? notes,
    String? status,
    String? createdAt,
  }) {
    return LoanModel(
      id: id ?? this.id,
      borrowerName: borrowerName ?? this.borrowerName,
      borrowerPhone: borrowerPhone ?? this.borrowerPhone,
      amount: amount ?? this.amount,
      remainingAmount:
          remainingAmount ?? this.remainingAmount,
      accountId: accountId ?? this.accountId,
      lendingDate: lendingDate ?? this.lendingDate,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
