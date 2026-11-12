
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/features/finance/services/transactions_service.dart';

class ReportsService {
  Future<Database> get _database => TransactionsService.database;

  String _date(DateTime date) {
    final value = DateTime(date.year, date.month, date.day);

    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  String _nextDate(DateTime date) {
    return _date(date.add(const Duration(days: 1)));
  }

  void _validateDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    if (endDate.isBefore(startDate)) {
      throw ArgumentError(
        'End date cannot be before start date.',
      );
    }
  }

  // --------------------------------------------------
  // FINANCIAL SUMMARY BY CURRENCY
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _validateDateRange(startDate, endDate);

    final db = await _database;

    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(a.currency, 'PKR') AS currency,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'income'
            THEN t.amount ELSE 0
          END
        ) AS income,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'expense'
            THEN t.amount ELSE 0
          END
        ) AS expense,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'transfer'
            THEN t.amount ELSE 0
          END
        ) AS transfers,

        COUNT(t.id) AS transaction_count

      FROM transactions t

      LEFT JOIN wallets a
        ON a.id = t.wallet_id

      WHERE t.date >= ?
        AND t.date < ?

      GROUP BY COALESCE(a.currency, 'PKR')
      ORDER BY currency ASC
      ''',
      [
        _date(startDate),
        _nextDate(endDate),
      ],
    );

    return rows.map((row) {
      final income = _number(row['income']);
      final expense = _number(row['expense']);

      return {
        'currency': row['currency'],
        'income': income,
        'expense': expense,
        'transfers': _number(row['transfers']),
        'net': income - expense,
        'transaction_count':
            (row['transaction_count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  // --------------------------------------------------
  // INCOME AND EXPENSE TOTALS
  // --------------------------------------------------

  Future<Map<String, double>> getIncomeExpenseTotals({
    required DateTime startDate,
    required DateTime endDate,
    String? currency,
  }) async {
    _validateDateRange(startDate, endDate);

    final db = await _database;

    final conditions = <String>[
      't.date >= ?',
      't.date < ?',
    ];

    final arguments = <Object?>[
      _date(startDate),
      _nextDate(endDate),
    ];

    if (currency != null && currency.isNotEmpty) {
      conditions.add('a.currency = ?');
      arguments.add(currency);
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        SUM(
          CASE
            WHEN LOWER(t.type) = 'income'
            THEN t.amount ELSE 0
          END
        ) AS income,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'expense'
            THEN t.amount ELSE 0
          END
        ) AS expense

      FROM transactions t

      LEFT JOIN wallets a
        ON a.id = t.wallet_id

      WHERE ${conditions.join(' AND ')}
      ''',
      arguments,
    );

    final row = rows.first;

    final income = _number(row['income']);
    final expense = _number(row['expense']);

    return {
      'income': income,
      'expense': expense,
      'net': income - expense,
    };
  }

  // --------------------------------------------------
  // MONTHLY INCOME AND EXPENSE TREND
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getMonthlyTrend({
    required DateTime startDate,
    required DateTime endDate,
    String? currency,
  }) async {
    _validateDateRange(startDate, endDate);

    final db = await _database;

    final conditions = <String>[
      't.date >= ?',
      't.date < ?',
      "LOWER(t.type) IN ('income', 'expense')",
    ];

    final arguments = <Object?>[
      _date(startDate),
      _nextDate(endDate),
    ];

    if (currency != null && currency.isNotEmpty) {
      conditions.add('a.currency = ?');
      arguments.add(currency);
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        SUBSTR(t.date, 1, 7) AS month,
        COALESCE(a.currency, 'PKR') AS currency,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'income'
            THEN t.amount ELSE 0
          END
        ) AS income,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'expense'
            THEN t.amount ELSE 0
          END
        ) AS expense

      FROM transactions t

      LEFT JOIN wallets a
        ON a.id = t.wallet_id

      WHERE ${conditions.join(' AND ')}

      GROUP BY
        SUBSTR(t.date, 1, 7),
        COALESCE(a.currency, 'PKR')

      ORDER BY month ASC
      ''',
      arguments,
    );

    return rows.map((row) {
      final income = _number(row['income']);
      final expense = _number(row['expense']);

      return {
        'month': row['month'],
        'currency': row['currency'],
        'income': income,
        'expense': expense,
        'net': income - expense,
      };
    }).toList();
  }

  // --------------------------------------------------
  // CATEGORY-WISE INCOME / EXPENSE BREAKDOWN
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getCategoryBreakdown({
    required DateTime startDate,
    required DateTime endDate,
    String type = 'expense',
    String? currency,
  }) async {
    _validateDateRange(startDate, endDate);

    final normalizedType = type.toLowerCase();

    if (!['income', 'expense'].contains(normalizedType)) {
      throw ArgumentError(
        'Category breakdown supports income or expense only.',
      );
    }

    final db = await _database;

    final conditions = <String>[
      't.date >= ?',
      't.date < ?',
      'LOWER(t.type) = ?',
    ];

    final arguments = <Object?>[
      _date(startDate),
      _nextDate(endDate),
      normalizedType,
    ];

    if (currency != null && currency.isNotEmpty) {
      conditions.add('a.currency = ?');
      arguments.add(currency);
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(NULLIF(t.category, ''), 'Uncategorized') AS category_name,
        COALESCE(a.currency, 'PKR') AS currency,

        SUM(t.amount) AS total,
        COUNT(t.id) AS transaction_count

      FROM transactions t


      LEFT JOIN wallets a
        ON a.id = t.wallet_id

      WHERE ${conditions.join(' AND ')}

      GROUP BY
        COALESCE(NULLIF(t.category, ''), 'Uncategorized'),
        COALESCE(a.currency, 'PKR')

      ORDER BY total DESC
      ''',
      arguments,
    );

    return rows.map((row) {
      return {
        'category_name': row['category_name'],
        'currency': row['currency'],
        'total': _number(row['total']),
        'transaction_count':
            (row['transaction_count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  // --------------------------------------------------
  // ACCOUNT-WISE TRANSACTION SUMMARY
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getAccountBreakdown({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _validateDateRange(startDate, endDate);

    final db = await _database;

    final rows = await db.rawQuery(
      '''
      SELECT
        a.id AS wallet_id,
        a.name AS wallet_name,
        a.currency AS currency,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'income'
            THEN t.amount ELSE 0
          END
        ) AS income,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'expense'
            THEN t.amount ELSE 0
          END
        ) AS expense,

        SUM(
          CASE
            WHEN LOWER(t.type) = 'transfer'
            THEN t.amount ELSE 0
          END
        ) AS transfers,

        COUNT(t.id) AS transaction_count

      FROM wallets a

      LEFT JOIN transactions t
        ON t.wallet_id = a.id
        AND t.date >= ?
        AND t.date < ?

      GROUP BY
        a.id,
        a.name,
        a.currency

      ORDER BY a.name ASC
      ''',
      [
        _date(startDate),
        _nextDate(endDate),
      ],
    );

    return rows.map((row) {
      final income = _number(row['income']);
      final expense = _number(row['expense']);

      return {
        'wallet_id': row['wallet_id'],
        'wallet_name': row['wallet_name'],
        'currency': row['currency'],
        'income': income,
        'expense': expense,
        'transfers': _number(row['transfers']),
        'net': income - expense,
        'transaction_count':
            (row['transaction_count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  // --------------------------------------------------
  // TRANSACTION HISTORY FOR A SELECTED PERIOD
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getTransactionHistory({
    required DateTime startDate,
    required DateTime endDate,
    String? type,
    int? walletId,
    String? currency,
    int limit = 500,
  }) async {
    _validateDateRange(startDate, endDate);

    final db = await _database;

    final conditions = <String>[
      't.date >= ?',
      't.date < ?',
    ];

    final arguments = <Object?>[
      _date(startDate),
      _nextDate(endDate),
    ];

    if (type != null && type.isNotEmpty) {
      final normalizedType = type.toLowerCase();

      if (!['income', 'expense', 'transfer'].contains(normalizedType)) {
        throw ArgumentError('Invalid transaction type.');
      }

      conditions.add('LOWER(t.type) = ?');
      arguments.add(normalizedType);
    }

    if (walletId != null) {
      conditions.add(
        '(t.wallet_id = ? OR t.to_wallet_id = ?)',
      );

      arguments.add(walletId);
      arguments.add(walletId);
    }

    if (currency != null && currency.isNotEmpty) {
      conditions.add('a.currency = ?');
      arguments.add(currency);
    }

    arguments.add(limit.clamp(1, 5000));

    return db.rawQuery(
      '''
      SELECT
        t.id,
        t.type,
        t.amount,
        t.wallet_id,
        t.to_wallet_id,
        t.category,
        t.note,
        t.date,

        a.name AS wallet_name,
        a.currency AS currency,

        destination.name AS destination_wallet_name,

        t.category AS category_name

      FROM transactions t

      LEFT JOIN wallets a
        ON a.id = t.wallet_id

      LEFT JOIN wallets destination
        ON destination.id = t.to_wallet_id


      WHERE ${conditions.join(' AND ')}

      ORDER BY t.date DESC, t.id DESC

      LIMIT ?
      ''',
      arguments,
    );
  }

  // --------------------------------------------------
  // AVAILABLE CURRENCIES
  // --------------------------------------------------

  Future<List<String>> getAvailableCurrencies() async {
    final db = await _database;

    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT currency
      FROM wallets
      WHERE currency IS NOT NULL
        AND currency != ''
      ORDER BY currency ASC
      ''',
    );

    return rows
        .map((row) => row['currency'].toString())
        .toList();
  }

  // --------------------------------------------------
  // TOTAL ACCOUNT BALANCES BY CURRENCY
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getBalancesByCurrency() async {
    final db = await _database;

    final rows = await db.rawQuery(
      '''
      SELECT
        currency,
        SUM(balance) AS total_balance,
        COUNT(id) AS account_count

      FROM wallets

      WHERE exclude_total = 0

      GROUP BY currency

      ORDER BY currency ASC
      ''',
    );

    return rows.map((row) {
      return {
        'currency': row['currency'],
        'total_balance': _number(row['total_balance']),
        'account_count':
            (row['account_count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  // --------------------------------------------------
  // RECENT TRANSACTIONS
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getRecentTransactions({
    int limit = 10,
  }) async {
    final db = await _database;

    return db.rawQuery(
      '''
      SELECT
        t.*,
        a.name AS wallet_name,
        a.currency AS currency,
        destination.name AS destination_wallet_name,
        t.category AS category_name

      FROM transactions t

      LEFT JOIN wallets a
        ON a.id = t.wallet_id

      LEFT JOIN wallets destination
        ON destination.id = t.to_wallet_id


      ORDER BY t.date DESC, t.id DESC

      LIMIT ?
      ''',
      [limit.clamp(1, 5000)],
    );
  }

  // --------------------------------------------------
  // HELPER
  // --------------------------------------------------

  double _number(Object? value) {
    return (value as num?)?.toDouble() ?? 0.0;
  }
}
