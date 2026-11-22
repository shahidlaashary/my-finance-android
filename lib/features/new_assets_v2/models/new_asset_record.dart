/// Domain model for the isolated New Assets System (v2).
/// This model intentionally does not depend on the legacy AssetsModel.
class NewAssetRecord {
  const NewAssetRecord({
    this.id,
    required this.name,
    required this.category,
    required this.currency,
    required this.purchaseAmount,
    required this.currentValue,
    required this.purchaseDate,
    required this.paymentType,
    this.walletId,
    this.partyId,
    this.linkedLoanId,
    this.includeInConsolidatedBalance = false,
    this.isSold = false,
    this.saleAmount,
    this.saleDate,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String category;
  final String currency;
  final double purchaseAmount;
  final double currentValue;
  final DateTime purchaseDate;
  /// 'Wallet' or 'Loan'. Loan assets do not require a wallet at purchase time.
  final String paymentType;
  final int? walletId;
  final int? partyId;
  final int? linkedLoanId;
  final bool includeInConsolidatedBalance;
  final bool isSold;
  final double? saleAmount;
  final DateTime? saleDate;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory NewAssetRecord.fromMap(Map<String, Object?> map) {
    return NewAssetRecord(
      id: (map['id'] as num?)?.toInt(),
      name: map['name'] as String,
      category: map['category'] as String,
      currency: map['currency'] as String,
      purchaseAmount: (map['purchase_amount'] as num).toDouble(),
      currentValue: (map['current_value'] as num).toDouble(),
      purchaseDate: DateTime.parse(map['purchase_date'] as String),
      paymentType: map['payment_type'] as String,
      walletId: (map['wallet_id'] as num?)?.toInt(),
      partyId: (map['party_id'] as num?)?.toInt(),
      linkedLoanId: (map['linked_loan_id'] as num?)?.toInt(),
      includeInConsolidatedBalance: (map['include_in_consolidated_balance'] as num? ?? 0) == 1,
      isSold: (map['is_sold'] as num? ?? 0) == 1,
      saleAmount: (map['sale_amount'] as num?)?.toDouble(),
      saleDate: map['sale_date'] == null ? null : DateTime.parse(map['sale_date'] as String),
      notes: map['notes'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
    'name': name,
    'category': category,
    'currency': currency,
    'purchase_amount': purchaseAmount,
    'current_value': currentValue,
    'purchase_date': purchaseDate.toIso8601String(),
    'payment_type': paymentType,
    'wallet_id': walletId,
    'party_id': partyId,
    'linked_loan_id': linkedLoanId,
    'include_in_consolidated_balance': includeInConsolidatedBalance ? 1 : 0,
    'is_sold': isSold ? 1 : 0,
    'sale_amount': saleAmount,
    'sale_date': saleDate?.toIso8601String(),
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
