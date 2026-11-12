import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class MyDocumentModel {
  final int? id;
  final String title;
  final String category;
  final String documentNumber;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final int reminderDays;
  final String notes;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MyDocumentModel({
    this.id,
    required this.title,
    required this.category,
    this.documentNumber = '',
    this.issueDate,
    this.expiryDate,
    this.reminderDays = 30,
    this.notes = '',
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MyDocumentModel.fromMap(Map<String, dynamic> map) {
    return MyDocumentModel(
      id: (map['id'] as num?)?.toInt(),
      title: map['title']?.toString() ?? '',
      category: map['category']?.toString() ?? 'Other',
      documentNumber: map['document_number']?.toString() ?? '',
      issueDate: DateTime.tryParse(map['issue_date']?.toString() ?? ''),
      expiryDate: DateTime.tryParse(map['expiry_date']?.toString() ?? ''),
      reminderDays: (map['reminder_days'] as num?)?.toInt() ?? 30,
      notes: map['notes']?.toString() ?? '',
      isFavorite: map['is_favorite'] == true || map['is_favorite'] == 1,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'category': category,
    'document_number': documentNumber,
    'issue_date': issueDate?.toIso8601String(),
    'expiry_date': expiryDate?.toIso8601String(),
    'reminder_days': reminderDays,
    'notes': notes,
    'is_favorite': isFavorite,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  MyDocumentModel copyWith({int? id, bool? isFavorite, DateTime? updatedAt}) => MyDocumentModel(
    id: id ?? this.id,
    title: title,
    category: category,
    documentNumber: documentNumber,
    issueDate: issueDate,
    expiryDate: expiryDate,
    reminderDays: reminderDays,
    notes: notes,
    isFavorite: isFavorite ?? this.isFavorite,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Document metadata is stored in the existing app_settings key-value table.
/// This avoids database-version changes, migrations, and changes to finance tables.
class MyDocumentsService {
  MyDocumentsService._();
  static final MyDocumentsService instance = MyDocumentsService._();

  static const String _databaseName = 'my_finance.db';
  static const String _storageKey = 'my_documents_records';
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get _db async {
    if (_database != null && _database!.isOpen) return _database!;
    final pending = _opening;
    if (pending != null) return pending;
    final future = _open();
    _opening = future;
    try {
      return await future;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final directory = await getDatabasesPath();
    final db = await openDatabase(p.join(directory, _databaseName));
    _database = db;
    _opening = null;
    return db;
  }

  Future<List<Map<String, dynamic>>> _readMaps(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [_storageKey],
      limit: 1,
    );
    if (rows.isEmpty) return [];
    final raw = rows.first['setting_value']?.toString() ?? '';
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeMaps(DatabaseExecutor executor, List<Map<String, dynamic>> records) async {
    await executor.insert(
      'app_settings',
      {'setting_key': _storageKey, 'setting_value': jsonEncode(records)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MyDocumentModel>> getDocuments({
    String search = '',
    String category = 'All',
    String filter = 'All',
  }) async {
    final db = await _db;
    final rows = await _readMaps(db);
    final query = search.trim().toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return rows.map(MyDocumentModel.fromMap).where((document) {
      if (category != 'All' && document.category != category) return false;
      if (query.isNotEmpty &&
          !document.title.toLowerCase().contains(query) &&
          !document.category.toLowerCase().contains(query) &&
          !document.documentNumber.toLowerCase().contains(query) &&
          !document.notes.toLowerCase().contains(query)) return false;
      if (filter == 'Favorites' && !document.isFavorite) return false;
      if (filter == 'Expiring Soon') {
        final expiry = document.expiryDate;
        if (expiry == null) return false;
        final days = DateTime(expiry.year, expiry.month, expiry.day).difference(today).inDays;
        if (days < 0 || days > document.reminderDays) return false;
      }
      if (filter == 'Expired') {
        final expiry = document.expiryDate;
        if (expiry == null || !DateTime(expiry.year, expiry.month, expiry.day).isBefore(today)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<int> addDocument(MyDocumentModel document) async {
    final db = await _db;
    return db.transaction((txn) async {
      final records = await _readMaps(txn);
      final id = DateTime.now().microsecondsSinceEpoch;
      records.add(document.copyWith(id: id).toMap());
      await _writeMaps(txn, records);
      return id;
    });
  }

  Future<void> updateDocument(MyDocumentModel document) async {
    if (document.id == null) throw ArgumentError('Document ID is required.');
    final db = await _db;
    await db.transaction((txn) async {
      final records = await _readMaps(txn);
      final index = records.indexWhere((item) => (item['id'] as num?)?.toInt() == document.id);
      if (index < 0) throw StateError('Document not found.');
      records[index] = document.toMap();
      await _writeMaps(txn, records);
    });
  }

  Future<void> toggleFavorite(MyDocumentModel document) async {
    if (document.id == null) return;
    final db = await _db;
    await db.transaction((txn) async {
      final records = await _readMaps(txn);
      final index = records.indexWhere((item) => (item['id'] as num?)?.toInt() == document.id);
      if (index < 0) return;
      records[index]['is_favorite'] = !document.isFavorite;
      records[index]['updated_at'] = DateTime.now().toIso8601String();
      await _writeMaps(txn, records);
    });
  }

  Future<void> deleteDocument(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final records = await _readMaps(txn);
      records.removeWhere((item) => (item['id'] as num?)?.toInt() == id);
      await _writeMaps(txn, records);
    });
  }
}
