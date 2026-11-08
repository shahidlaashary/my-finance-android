class AccountModel {
  final int? id;
  final String name;
  final String type;
  final String currency;
  final double balance;
  final bool excludeTotal;

  const AccountModel({
    this.id,
    required this.name,
    required this.type,
    this.currency = 'PKR',
    this.balance = 0,
    this.excludeTotal = false,
  });

  factory AccountModel.fromMap(Map<String, dynamic> map) {
    return AccountModel(
      id: map['id'] as int?,
      name: (map['name'] ?? '').toString(),
      type: (map['type'] ?? 'Other').toString(),
      currency: (map['currency'] ?? 'PKR').toString(),
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      excludeTotal: (map['exclude_total'] as num?)?.toInt() == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type,
      'currency': currency,
      'balance': balance,
      'exclude_total': excludeTotal ? 1 : 0,
    };
  }

  AccountModel copyWith({
    int? id,
    String? name,
    String? type,
    String? currency,
    double? balance,
    bool? excludeTotal,
  }) {
    return AccountModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      balance: balance ?? this.balance,
      excludeTotal: excludeTotal ?? this.excludeTotal,
    );
  }
}
