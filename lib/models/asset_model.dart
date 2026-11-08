
class AssetModel {
  final int? id;
  final String name;
  final String category;
  final double purchasePrice;
  final double currentValue;
  final DateTime purchaseDate;
  final int accountId;
  final String notes;
  final bool isSold;
  final DateTime? saleDate;
  final double? salePrice;
  final DateTime? createdAt;

  const AssetModel({
    this.id,
    required this.name,
    this.category = 'Other',
    required this.purchasePrice,
    required this.currentValue,
    required this.purchaseDate,
    required this.accountId,
    this.notes = '',
    this.isSold = false,
    this.saleDate,
    this.salePrice,
    this.createdAt,
  });

  double get profitOrLoss {
    if (!isSold || salePrice == null) return 0;
    return salePrice! - purchasePrice;
  }

  factory AssetModel.fromMap(Map<String, dynamic> map) {
    return AssetModel(
      id: (map['id'] as num?)?.toInt(),
      name: (map['name'] ?? '').toString(),
      category: (map['category'] ?? 'Other').toString(),
      purchasePrice: (map['purchase_price'] as num?)?.toDouble() ?? 0,
      currentValue: (map['current_value'] as num?)?.toDouble() ?? 0,
      purchaseDate: DateTime.tryParse(
            (map['purchase_date'] ?? '').toString(),
          ) ??
          DateTime.now(),
      accountId: (map['account_id'] as num?)?.toInt() ?? 0,
      notes: (map['notes'] ?? '').toString(),
      isSold: (map['is_sold'] as num?)?.toInt() == 1,
      saleDate: map['sale_date'] == null
          ? null
          : DateTime.tryParse(map['sale_date'].toString()),
      salePrice: (map['sale_price'] as num?)?.toDouble(),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'purchase_price': purchasePrice,
      'current_value': currentValue,
      'purchase_date': purchaseDate.toIso8601String(),
      'account_id': accountId,
      'notes': notes,
      'is_sold': isSold ? 1 : 0,
      'sale_date': saleDate?.toIso8601String(),
      'sale_price': salePrice,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  AssetModel copyWith({
    int? id,
    String? name,
    String? category,
    double? purchasePrice,
    double? currentValue,
    DateTime? purchaseDate,
    int? accountId,
    String? notes,
    bool? isSold,
    Object? saleDate = _unset,
    Object? salePrice = _unset,
    Object? createdAt = _unset,
  }) {
    return AssetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      currentValue: currentValue ?? this.currentValue,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      accountId: accountId ?? this.accountId,
      notes: notes ?? this.notes,
      isSold: isSold ?? this.isSold,
      saleDate: identical(saleDate, _unset)
          ? this.saleDate
          : saleDate as DateTime?,
      salePrice: identical(salePrice, _unset)
          ? this.salePrice
          : salePrice as double?,
      createdAt: identical(createdAt, _unset)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }
}

const Object _unset = Object();
