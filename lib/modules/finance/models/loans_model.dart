/// Loan ki amount, outstanding balance, party aur linked asset details represent karta hai.
class LoansModel {
  final int? id;
  final int? partyId;
  final String loanType;
  final double amount;
  final double remainingAmount;
  final int walletId;
  final String currency;
  final String? sourceType;
  final int? sourceId;
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
    this.currency = 'PKR',
    this.sourceType,
    this.sourceId,
    required this.lendingDate,
    this.dueDate,
    this.notes = '',
    this.status = 'active',
    required this.createdAt,
  });

  bool get isPaid => remainingAmount <= 0;
  bool get isAssetLinked => sourceType == 'asset_purchase' || sourceType == 'asset_sale';

  /// Unpaid loan ki due date guzarne par true deta hai.
  bool get isOverdue {
    if (isPaid || dueDate == null || dueDate!.isEmpty) return false;
    final due = DateTime.tryParse(dueDate!);
    if (due == null) return false;
    final today = DateTime.now();
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Total amount mein se outstanding minus karke repaid amount deta hai.
  double get repaidAmount => (amount - remainingAmount).clamp(0, amount).toDouble();

  /// Loan model ko database record mein convert karta hai.
  Map<String, dynamic> toMap() => {
    'id': id, 'party_id': partyId, 'loan_type': loanType,
    'amount': amount, 'remaining_amount': remainingAmount,
    'wallet_id': walletId, 'currency': currency.toUpperCase(),
    'source_type': sourceType, 'source_id': sourceId,
    'lending_date': lendingDate, 'due_date': dueDate,
    'notes': notes, 'status': status, 'created_at': createdAt,
  };

  factory LoansModel.fromMap(Map<String, dynamic> map) => LoansModel(
    id: (map['id'] as num?)?.toInt(),
    partyId: (map['party_id'] as num?)?.toInt(),
    loanType: map['loan_type'] as String? ?? 'given',
    amount: (map['amount'] as num).toDouble(),
    remainingAmount: (map['remaining_amount'] as num).toDouble(),
    walletId: (map['wallet_id'] as num).toInt(),
    currency: (map['currency']?.toString() ?? 'PKR').toUpperCase(),
    sourceType: map['source_type']?.toString(),
    sourceId: (map['source_id'] as num?)?.toInt(),
    lendingDate: map['lending_date'] as String,
    dueDate: map['due_date'] as String?,
    notes: map['notes'] as String? ?? '',
    status: map['status'] as String? ?? 'active',
    createdAt: map['created_at'] as String,
  );

  LoansModel copyWith({
    int? id, int? partyId, String? loanType, double? amount,
    double? remainingAmount, int? walletId, String? currency,
    String? sourceType, int? sourceId, String? lendingDate,
    String? dueDate, String? notes, String? status, String? createdAt,
  }) => LoansModel(
    id: id ?? this.id, partyId: partyId ?? this.partyId,
    loanType: loanType ?? this.loanType, amount: amount ?? this.amount,
    remainingAmount: remainingAmount ?? this.remainingAmount,
    walletId: walletId ?? this.walletId,
    currency: currency ?? this.currency,
    sourceType: sourceType ?? this.sourceType, sourceId: sourceId ?? this.sourceId,
    lendingDate: lendingDate ?? this.lendingDate,
    dueDate: dueDate ?? this.dueDate, notes: notes ?? this.notes,
    status: status ?? this.status, createdAt: createdAt ?? this.createdAt,
  );
}
