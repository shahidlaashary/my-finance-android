/// Asset ki purchase, valuation, sale aur linked payment details represent karta hai.
class AssetsModel {
  final int? id;
  final String name;
  final String category;
  final double purchasePrice;
  final double currentValue;
  final DateTime purchaseDate;
  final int walletId;
  final String paymentType;
  final int? partyId;
  final String currency;
  final int? linkedLoanId;
  final String notes;
  final bool isSold;
  final bool includeInConsolidatedBalance;
  final DateTime? saleDate;
  final double? salePrice;
  final int? saleWalletId;
  final double? saleWalletAmount;
  final String saleWalletCurrency;
  final double saleExchangeRate;
  final bool saleIsManualRate;
  final String salePaymentType;
  final int? salePartyId;
  final int? saleLinkedLoanId;
  final DateTime? createdAt;

  const AssetsModel({
    this.id, required this.name, this.category = 'Other',
    required this.purchasePrice, required this.currentValue,
    required this.purchaseDate, required this.walletId,
    this.paymentType = 'Wallet', this.partyId, this.currency = 'PKR',
    this.linkedLoanId, this.notes = '', this.isSold = false,
    this.saleDate, this.salePrice, this.saleWalletId,
    this.saleWalletAmount, this.saleWalletCurrency = 'PKR', this.saleExchangeRate = 1.0, this.saleIsManualRate = false,
    this.salePaymentType = 'Wallet', this.salePartyId,
    this.saleLinkedLoanId, this.createdAt,
    this.includeInConsolidatedBalance = false,
  });

  /// Sold asset ka purchase price ke muqablay mein profit ya loss deta hai.
  double get profitOrLoss => !isSold || salePrice == null ? 0 : salePrice! - purchasePrice;

  /// Database row ko typed asset model mein convert karta hai.
  factory AssetsModel.fromMap(Map<String, dynamic> map) => AssetsModel(
    id: (map['id'] as num?)?.toInt(),
    name: (map['name'] ?? '').toString(),
    category: (map['category'] ?? 'Other').toString(),
    purchasePrice: (map['purchase_price'] as num?)?.toDouble() ?? 0,
    currentValue: (map['current_value'] as num?)?.toDouble() ?? 0,
    purchaseDate: DateTime.tryParse((map['purchase_date'] ?? '').toString()) ?? DateTime.now(),
    walletId: (map['wallet_id'] as num?)?.toInt() ?? 0,
    paymentType: (map['payment_type'] ?? 'Wallet').toString(),
    partyId: (map['party_id'] as num?)?.toInt(),
    currency: (map['currency'] ?? 'PKR').toString().toUpperCase(),
    linkedLoanId: (map['linked_loan_id'] as num?)?.toInt(),
    notes: (map['notes'] ?? '').toString(),
    isSold: (map['is_sold'] as num?)?.toInt() == 1,
    includeInConsolidatedBalance: (map['include_in_consolidated_balance'] as num?)?.toInt() == 1,
    saleDate: map['sale_date'] == null ? null : DateTime.tryParse(map['sale_date'].toString()),
    salePrice: (map['sale_price'] as num?)?.toDouble(),
    saleWalletId: (map['sale_wallet_id'] as num?)?.toInt(),
    saleWalletAmount: (map['sale_wallet_amount'] as num?)?.toDouble(),
    saleWalletCurrency: (map['sale_wallet_currency'] ?? map['currency'] ?? 'PKR').toString().toUpperCase(),
    saleExchangeRate: (map['sale_exchange_rate'] as num?)?.toDouble() ?? 1.0,
    saleIsManualRate: (map['sale_is_manual_rate'] as num?)?.toInt() == 1,
    salePaymentType: (map['sale_payment_type'] ?? 'Wallet').toString(),
    salePartyId: (map['sale_party_id'] as num?)?.toInt(),
    saleLinkedLoanId: (map['sale_linked_loan_id'] as num?)?.toInt(),
    createdAt: map['created_at'] == null ? null : DateTime.tryParse(map['created_at'].toString()),
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id, 'name': name, 'category': category,
    'purchase_price': purchasePrice, 'current_value': currentValue,
    'purchase_date': purchaseDate.toIso8601String(), 'wallet_id': walletId,
    'payment_type': paymentType, 'party_id': partyId, 'currency': currency.toUpperCase(),
    'linked_loan_id': linkedLoanId, 'notes': notes,
    'is_sold': isSold ? 1 : 0, 'include_in_consolidated_balance': includeInConsolidatedBalance ? 1 : 0, 'sale_date': saleDate?.toIso8601String(),
    'sale_price': salePrice, 'sale_wallet_id': saleWalletId,
    'sale_wallet_amount': saleWalletAmount, 'sale_wallet_currency': saleWalletCurrency.toUpperCase(),
    'sale_exchange_rate': saleExchangeRate, 'sale_is_manual_rate': saleIsManualRate ? 1 : 0,
    'sale_payment_type': salePaymentType, 'sale_party_id': salePartyId,
    'sale_linked_loan_id': saleLinkedLoanId, 'created_at': createdAt?.toIso8601String(),
  };

  AssetsModel copyWith({
    int? id, String? name, String? category, double? purchasePrice,
    double? currentValue, DateTime? purchaseDate, int? walletId,
    String? paymentType, int? partyId, String? currency, int? linkedLoanId,
    String? notes, bool? isSold, bool? includeInConsolidatedBalance, Object? saleDate = _unset,
    Object? salePrice = _unset, Object? saleWalletId = _unset,
    Object? saleWalletAmount = _unset, String? saleWalletCurrency, double? saleExchangeRate, bool? saleIsManualRate,
    String? salePaymentType, Object? salePartyId = _unset,
    Object? saleLinkedLoanId = _unset, Object? createdAt = _unset,
  }) => AssetsModel(
    id: id ?? this.id, name: name ?? this.name, category: category ?? this.category,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    currentValue: currentValue ?? this.currentValue,
    purchaseDate: purchaseDate ?? this.purchaseDate, walletId: walletId ?? this.walletId,
    paymentType: paymentType ?? this.paymentType,
    partyId: partyId ?? this.partyId, currency: currency ?? this.currency,
    linkedLoanId: linkedLoanId ?? this.linkedLoanId, notes: notes ?? this.notes,
    isSold: isSold ?? this.isSold,
    includeInConsolidatedBalance: includeInConsolidatedBalance ?? this.includeInConsolidatedBalance,
    saleDate: identical(saleDate, _unset) ? this.saleDate : saleDate as DateTime?,
    salePrice: identical(salePrice, _unset) ? this.salePrice : salePrice as double?,
    saleWalletId: identical(saleWalletId, _unset) ? this.saleWalletId : saleWalletId as int?,
    saleWalletAmount: identical(saleWalletAmount, _unset) ? this.saleWalletAmount : saleWalletAmount as double?,
    saleWalletCurrency: saleWalletCurrency ?? this.saleWalletCurrency,
    saleExchangeRate: saleExchangeRate ?? this.saleExchangeRate,
    saleIsManualRate: saleIsManualRate ?? this.saleIsManualRate,
    salePaymentType: salePaymentType ?? this.salePaymentType,
    salePartyId: identical(salePartyId, _unset) ? this.salePartyId : salePartyId as int?,
    saleLinkedLoanId: identical(saleLinkedLoanId, _unset) ? this.saleLinkedLoanId : saleLinkedLoanId as int?,
    createdAt: identical(createdAt, _unset) ? this.createdAt : createdAt as DateTime?,
  );
}
const Object _unset = Object();
