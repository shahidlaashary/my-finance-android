
/// Loan repayment aur wallet currency conversion ki details represent karta hai.
class RepaymentModel {
  final int? id;
  final int loanId;
  final double amount;
  final int walletId;
  final String repaymentDate;
  final String paymentMethod;
  final String notes;
  final String createdAt;
  final String walletCurrency;
  final double walletAmount;
  final double exchangeRate;
  final bool isManualRate;
  final String rateSource;
  final String baseCurrencyAtTime;
  final double? baseExchangeRate;
  final double? baseConvertedAmount;
  final String baseRateSource;

  const RepaymentModel({
    this.id,
    required this.loanId,
    required this.amount,
    required this.walletId,
    required this.repaymentDate,
    this.paymentMethod = 'cash',
    this.notes = '',
    required this.createdAt,
    this.walletCurrency = 'PKR',
    double? walletAmount,
    this.exchangeRate = 1.0,
    this.isManualRate = false,
    this.rateSource = 'Automatic',
    this.baseCurrencyAtTime = 'PKR',
    this.baseExchangeRate,
    this.baseConvertedAmount,
    this.baseRateSource = 'Unknown',
  }) : walletAmount = walletAmount ?? amount;

  /// Repayment model ko database columns ke mutabiq map mein convert karta hai.
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
      'wallet_currency': walletCurrency,
      'wallet_amount': walletAmount,
      'exchange_rate': exchangeRate,
      'is_manual_rate': isManualRate ? 1 : 0,
      'rate_source': rateSource,
      'base_currency_at_time': baseCurrencyAtTime,
      'base_exchange_rate': baseExchangeRate,
      'base_converted_amount': baseConvertedAmount,
      'base_rate_source': baseRateSource,
    };
  }

  /// Database row se repayment model tayyar karta hai.
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
      walletCurrency: (map['wallet_currency']?.toString() ?? 'PKR').toUpperCase(),
      walletAmount: (map['wallet_amount'] as num?)?.toDouble() ?? (map['amount'] as num).toDouble(),
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      isManualRate: (map['is_manual_rate'] as num?)?.toInt() == 1,
      rateSource: map['rate_source']?.toString() ?? 'Unknown',
      baseCurrencyAtTime: (map['base_currency_at_time']?.toString() ?? 'PKR').toUpperCase(),
      baseExchangeRate: (map['base_exchange_rate'] as num?)?.toDouble(),
      baseConvertedAmount: (map['base_converted_amount'] as num?)?.toDouble(),
      baseRateSource: map['base_rate_source']?.toString() ?? 'Unknown',
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
    String? walletCurrency,
    double? walletAmount,
    double? exchangeRate,
    bool? isManualRate,
    String? rateSource,
    String? baseCurrencyAtTime,
    double? baseExchangeRate,
    double? baseConvertedAmount,
    String? baseRateSource,
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
      walletCurrency: walletCurrency ?? this.walletCurrency,
      walletAmount: walletAmount ?? this.walletAmount,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      isManualRate: isManualRate ?? this.isManualRate,
      rateSource: rateSource ?? this.rateSource,
      baseCurrencyAtTime: baseCurrencyAtTime ?? this.baseCurrencyAtTime,
      baseExchangeRate: baseExchangeRate ?? this.baseExchangeRate,
      baseConvertedAmount: baseConvertedAmount ?? this.baseConvertedAmount,
      baseRateSource: baseRateSource ?? this.baseRateSource,
    );
  }
}
