import 'package:sqflite/sqflite.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

class DebtRecord {
  final int? id;
  final String name;
  final String lender;
  final String phone;
  final double originalAmount;
  final double balance;
  final double annualInterestRate;
  final double minimumPayment;
  final int walletId;
  final String startDate;
  final String? dueDate;
  final String notes;
  final String status;

  const DebtRecord({
    this.id,
    required this.name,
    required this.lender,
    this.phone = '',
    required this.originalAmount,
    required this.balance,
    this.annualInterestRate = 0,
    this.minimumPayment = 0,
    required this.walletId,
    required this.startDate,
    this.dueDate,
    this.notes = '',
    this.status = 'active',
  });

  double get paidAmount => (originalAmount - balance).clamp(0, originalAmount).toDouble();
  double get progress => originalAmount <= 0 ? 0 : (paidAmount / originalAmount).clamp(0, 1).toDouble();
  bool get isPaid => balance <= 0.000001;

  factory DebtRecord.fromMap(Map<String, dynamic> m) => DebtRecord(
    id: (m['id'] as num?)?.toInt(),
    name: m['name']?.toString() ?? '',
    lender: m['lender']?.toString() ?? '',
    phone: m['phone']?.toString() ?? '',
    originalAmount: (m['original_amount'] as num).toDouble(),
    balance: (m['balance'] as num).toDouble(),
    annualInterestRate: (m['annual_interest_rate'] as num).toDouble(),
    minimumPayment: (m['minimum_payment'] as num).toDouble(),
    walletId: (m['wallet_id'] as num).toInt(),
    startDate: m['start_date']?.toString() ?? '',
    dueDate: m['due_date']?.toString(),
    notes: m['notes']?.toString() ?? '',
    status: m['status']?.toString() ?? 'active',
  );
}

class DebtPayment {
  final int? id;
  final int debtId;
  final double amount;
  final int walletId;
  final String paymentDate;
  final String notes;

  const DebtPayment({
    this.id,
    required this.debtId,
    required this.amount,
    required this.walletId,
    required this.paymentDate,
    this.notes = '',
  });

  factory DebtPayment.fromMap(Map<String, dynamic> m) => DebtPayment(
    id: (m['id'] as num?)?.toInt(),
    debtId: (m['debt_id'] as num).toInt(),
    amount: (m['amount'] as num).toDouble(),
    walletId: (m['wallet_id'] as num).toInt(),
    paymentDate: m['payment_date']?.toString() ?? '',
    notes: m['notes']?.toString() ?? '',
  );
}

class DebtPayoffService {
  static Future<Database> get _db async {
    final db = await TransactionsService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        lender TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        original_amount REAL NOT NULL,
        balance REAL NOT NULL,
        annual_interest_rate REAL NOT NULL DEFAULT 0,
        minimum_payment REAL NOT NULL DEFAULT 0,
        wallet_id INTEGER NOT NULL,
        start_date TEXT NOT NULL,
        due_date TEXT,
        notes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debt_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        wallet_id INTEGER NOT NULL,
        payment_date TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(debt_id) REFERENCES debts(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_debt_payments_debt ON debt_payments(debt_id)');
    return db;
  }

  static Future<List<DebtRecord>> getDebts() async {
    final db = await _db;
    final rows = await db.query('debts', orderBy: "CASE WHEN status='active' THEN 0 ELSE 1 END, name COLLATE NOCASE");
    return rows.map(DebtRecord.fromMap).toList();
  }

  static Future<int> saveDebt(DebtRecord debt) async {
    final db = await _db;
    if (debt.name.trim().isEmpty || debt.lender.trim().isEmpty) throw Exception('Debt name and lender are required.');
    if (!debt.originalAmount.isFinite || debt.originalAmount <= 0) throw Exception('Enter a valid debt amount.');
    if (debt.balance < 0 || debt.balance > debt.originalAmount) throw Exception('Invalid outstanding balance.');
    if (debt.annualInterestRate < 0 || debt.minimumPayment < 0) throw Exception('Interest and minimum payment cannot be negative.');
    final wallets = await db.query('wallets', columns: ['id'], where: 'id=?', whereArgs: [debt.walletId], limit: 1);
    if (wallets.isEmpty) throw Exception('Linked account was not found.');
    final balance = debt.balance;
    final values = {
      'name': debt.name.trim(), 'lender': debt.lender.trim(), 'phone': debt.phone.trim(),
      'original_amount': debt.originalAmount, 'balance': balance,
      'annual_interest_rate': debt.annualInterestRate, 'minimum_payment': debt.minimumPayment,
      'wallet_id': debt.walletId, 'start_date': debt.startDate, 'due_date': debt.dueDate,
      'notes': debt.notes, 'status': debt.balance <= 0 ? 'paid' : 'active',
    };
    if (debt.id == null) {
      final id = await db.insert('debts', values);
      AppRefreshController.notifyChanged();
      return id;
    }
    await db.update('debts', values, where: 'id=?', whereArgs: [debt.id]);
    AppRefreshController.notifyChanged();
    return debt.id!;
  }

  static Future<int> addPayment(DebtPayment payment) async {
    final db = await _db;
    if (!payment.amount.isFinite || payment.amount <= 0) throw Exception('Enter a valid payment amount.');
    return db.transaction((txn) async {
      final debtRows = await txn.query('debts', where: 'id=?', whereArgs: [payment.debtId], limit: 1);
      if (debtRows.isEmpty) throw Exception('Debt not found.');
      final debt = DebtRecord.fromMap(debtRows.first);
      if (debt.isPaid || payment.amount > debt.balance + 0.000001) throw Exception('Payment exceeds outstanding debt.');
      final wallets = await txn.query('wallets', where: 'id=?', whereArgs: [payment.walletId], limit: 1);
      if (wallets.isEmpty) throw Exception('Selected account not found.');
      final debtWallets = await txn.query('wallets', columns: ['currency'], where: 'id=?', whereArgs: [debt.walletId], limit: 1);
      final paymentCurrency = (wallets.first['currency']?.toString() ?? 'PKR').toUpperCase();
      final debtCurrency = (debtWallets.isEmpty ? 'PKR' : debtWallets.first['currency']?.toString() ?? 'PKR').toUpperCase();
      if (paymentCurrency != debtCurrency) throw Exception('Payment account must use $debtCurrency.');
      final cash = (wallets.first['balance'] as num).toDouble();
      if (cash < payment.amount) throw Exception('Insufficient account balance.');
      await txn.rawUpdate('UPDATE wallets SET balance = balance - ? WHERE id=?', [payment.amount, payment.walletId]);
      final next = (debt.balance - payment.amount).clamp(0.0, debt.originalAmount).toDouble();
      await txn.update('debts', {'balance': next, 'status': next <= 0.000001 ? 'paid' : 'active'}, where: 'id=?', whereArgs: [payment.debtId]);
      final id = await txn.insert('debt_payments', {
        'debt_id': payment.debtId, 'amount': payment.amount, 'wallet_id': payment.walletId,
        'payment_date': payment.paymentDate, 'notes': payment.notes,
      });
      AppRefreshController.notifyChanged();
      return id;
    });
  }

  static Future<List<DebtPayment>> getPayments(int debtId) async {
    final db = await _db;
    final rows = await db.query('debt_payments', where: 'debt_id=?', whereArgs: [debtId], orderBy: 'payment_date DESC, id DESC');
    return rows.map(DebtPayment.fromMap).toList();
  }

  static Future<void> deletePayment(int paymentId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('debt_payments', where: 'id=?', whereArgs: [paymentId], limit: 1);
      if (rows.isEmpty) return;
      final p = DebtPayment.fromMap(rows.first);
      final debtRows = await txn.query('debts', where: 'id=?', whereArgs: [p.debtId], limit: 1);
      if (debtRows.isEmpty) throw Exception('Related debt not found.');
      final walletRows = await txn.query('wallets', where: 'id=?', whereArgs: [p.walletId], limit: 1);
      if (walletRows.isEmpty) throw Exception('Payment account not found.');
      final debt = DebtRecord.fromMap(debtRows.first);
      await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id=?', [p.amount, p.walletId]);
      final restored = (debt.balance + p.amount).clamp(0.0, debt.originalAmount).toDouble();
      await txn.update('debts', {'balance': restored, 'status': restored <= 0.000001 ? 'paid' : 'active'}, where: 'id=?', whereArgs: [p.debtId]);
      await txn.delete('debt_payments', where: 'id=?', whereArgs: [paymentId]);
      AppRefreshController.notifyChanged();
    });
  }

  static Future<void> deleteDebt(int debtId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final payments = await txn.query('debt_payments', where: 'debt_id=?', whereArgs: [debtId]);
      for (final row in payments) {
        final p = DebtPayment.fromMap(row);
        final exists = await txn.query('wallets', columns: ['id'], where: 'id=?', whereArgs: [p.walletId], limit: 1);
        if (exists.isEmpty) throw Exception('A payment account is missing; debt was not deleted.');
      }
      for (final row in payments) {
        final p = DebtPayment.fromMap(row);
        await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id=?', [p.amount, p.walletId]);
      }
      await txn.delete('debt_payments', where: 'debt_id=?', whereArgs: [debtId]);
      await txn.delete('debts', where: 'id=?', whereArgs: [debtId]);
      AppRefreshController.notifyChanged();
    });
  }
}
