import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

/// Owns wallet data operations while sharing the application's single
/// DatabaseManager connection.
class WalletService {
  WalletService._();

  static Future<List<Map<String, dynamic>>> getWallets() {
    return DatabaseManager.instance.database.query(
      'wallets',
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  static Future<Map<String, dynamic>?> getWallet(int id) async {
    final rows = await DatabaseManager.instance.database.query(
      'wallets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<int> addWallet({
    required String name,
    required String type,
    String? customType,
    required String currency,
    required double openingBalance,
    String? walletNumber,
    required int iconCode,
    required bool excludeTotal,
  }) async {
    final normalizedName = name.trim();
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedName.isEmpty ||
        normalizedCurrency.isEmpty ||
        !openingBalance.isFinite) {
      throw Exception(
        'Wallet name, currency aur opening balance durust enter karein.',
      );
    }

    final id = await DatabaseManager.instance.database.insert('wallets', {
      'name': normalizedName,
      'type': type,
      'custom_type': customType,
      'currency': normalizedCurrency,
      'balance': openingBalance,
      'opening_balance': openingBalance,
      'wallet_number': walletNumber,
      'icon_code': iconCode,
      'exclude_total': excludeTotal ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    AppRefreshController.notifyChanged();
    return id;
  }
}
