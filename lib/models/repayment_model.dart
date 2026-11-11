
class RepaymentModel {
  final int? id;
  final int loanId;
  final double amount;
  final int walletId;
  final String repaymentDate;
  final String paymentMethod;
  final String notes;
  final String createdAt;

  const RepaymentModel({
    this.id,
    required this.loanId,
    required this.amount,
    required this.walletId,
    required this.repaymentDate,
    this.paymentMethod = 'cash',
    this.notes = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'loan_id': loanId,
      'amount': amount,
      'wallet_id': walletId,
      'repayment_date': repaymentDate,
      'payment_method': paymentMethod,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory RepaymentModel.fromMap(Map<String, dynamic> map) {
    return RepaymentModel(
      id: map['id'] as int?,
      loanId: map['loan_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      walletId: map['wallet_id'] as int,
      repaymentDate: map['repayment_date'] as String,
      paymentMethod:
          map['payment_method'] as String? ?? 'cash',
      notes: map['notes'] as String? ?? '',
      createdAt: map['created_at'] as String,
    );
  }

  RepaymentModel copyWith({
    int? id,
    int? loanId,
    double? amount,
    int? walletId,
    String? repaymentDate,
    String? paymentMethod,
    String? notes,
    String? createdAt,
  }) {
    return RepaymentModel(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      amount: amount ?? this.amount,
      walletId: walletId ?? this.walletId,
      repaymentDate: repaymentDate ?? this.repaymentDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
