class WalletModel {
  final int? id;
  final String name;
  final String type;
  final String? customType;
  final String currency;
  final double balance;
  final double openingBalance;
  final String? walletNumber;
  final int iconCode;
  final bool excludeTotal;
  final String createdAt;

  const WalletModel({
    this.id,
    required this.name,
    required this.type,
    this.customType,
    this.currency = 'PKR',
    this.balance = 0,
    this.openingBalance = 0,
    this.walletNumber,
    required this.iconCode,
    this.excludeTotal = false,
    required this.createdAt,
  });

  factory WalletModel.fromMap(Map<String, dynamic> map) => WalletModel(
    id: (map['id'] as num?)?.toInt(),
    name: (map['name'] ?? '').toString(),
    type: (map['type'] ?? 'Other').toString(),
    customType: map['custom_type']?.toString(),
    currency: (map['currency'] ?? 'PKR').toString(),
    balance: (map['balance'] as num?)?.toDouble() ?? 0,
    openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
    walletNumber: map['wallet_number']?.toString(),
    iconCode: (map['icon_code'] as num?)?.toInt() ?? 0,
    excludeTotal: (map['exclude_total'] as num?)?.toInt() == 1,
    createdAt: (map['created_at'] ?? '').toString(),
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'type': type,
    'custom_type': customType,
    'currency': currency,
    'balance': balance,
    'opening_balance': openingBalance,
    'wallet_number': walletNumber,
    'icon_code': iconCode,
    'exclude_total': excludeTotal ? 1 : 0,
    'created_at': createdAt,
  };
}
