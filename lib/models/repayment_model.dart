
class RepaymentModel {
  final int? id;
  final int loanId;
  final double amount;
  final int accountId;
  final String repaymentDate;
  final String paymentMethod;
  final String notes;
  final String createdAt;

  const RepaymentModel({
    this.id,
    required this.loanId,
    required this.amount,
    required this.accountId,
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
      'account_id': accountId,
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
      accountId: map['account_id'] as int,
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
    int? accountId,
    String? repaymentDate,
    String? paymentMethod,
    String? notes,
    String? createdAt,
  }) {
    return RepaymentModel(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      amount: amount ?? this.amount,
      accountId: accountId ?? this.accountId,
      repaymentDate: repaymentDate ?? this.repaymentDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
