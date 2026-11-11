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
      id: map['id'] as int?,
      title: map['title']?.toString() ?? '',
      category: map['category']?.toString() ?? 'Other',
      documentNumber: map['document_number']?.toString() ?? '',
      issueDate: DateTime.tryParse(map['issue_date']?.toString() ?? ''),
      expiryDate: DateTime.tryParse(map['expiry_date']?.toString() ?? ''),
      reminderDays: (map['reminder_days'] as num?)?.toInt() ?? 30,
      notes: map['notes']?.toString() ?? '',
      isFavorite: (map['is_favorite'] as num?)?.toInt() == 1,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'category': category,
    'document_number': documentNumber,
    'issue_date': issueDate?.toIso8601String(),
    'expiry_date': expiryDate?.toIso8601String(),
    'reminder_days': reminderDays,
    'notes': notes,
    'is_favorite': isFavorite ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  MyDocumentModel copyWith({int? id}) => MyDocumentModel(
    id: id ?? this.id,
    title: title,
    category: category,
    documentNumber: documentNumber,
    issueDate: issueDate,
    expiryDate: expiryDate,
    reminderDays: reminderDays,
    notes: notes,
    isFavorite: isFavorite,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Additive document storage. It creates only its own table and never alters
/// existing finance tables or the database version.
class MyDocumentsService {
  MyDocumentsService._();
  static final MyDocumentsService instance = MyDocumentsService._();

  static const String _databaseName = 'my_finance.db';
  static const String _tableName = 'my_documents';
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        document_number TEXT NOT NULL DEFAULT '',
        issue_date TEXT,
        expiry_date TEXT,
        reminder_days INTEGER NOT NULL DEFAULT 30,
        notes TEXT NOT NULL DEFAULT '',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_my_documents_category
      ON $_tableName (category)
    ''');
    _database = db;
    return db;
  }

  Future<List<MyDocumentModel>> getDocuments({
    String search = '',
    String category = 'All',
    String filter = 'All',
  }) async {
    final db = await _db;
    final rows = await db.query(_tableName, orderBy: 'updated_at DESC');
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
        final days = expiry.difference(today).inDays;
        if (days < 0 || days > document.reminderDays) return false;
      }
      if (filter == 'Expired') {
        final expiry = document.expiryDate;
        if (expiry == null || !expiry.isBefore(today)) return false;
      }
      return true;
    }).toList();
  }

  Future<int> addDocument(MyDocumentModel document) async {
    final db = await _db;
    return db.insert(_tableName, document.toMap());
  }

  Future<void> updateDocument(MyDocumentModel document) async {
    if (document.id == null) throw ArgumentError('Document ID is required.');
    final db = await _db;
    await db.update(
      _tableName,
      document.toMap(),
      where: 'id = ?',
      whereArgs: [document.id],
    );
  }

  Future<void> toggleFavorite(MyDocumentModel document) async {
    if (document.id == null) return;
    final db = await _db;
    await db.update(
      _tableName,
      {'is_favorite': document.isFavorite ? 0 : 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [document.id],
    );
  }

  Future<void> deleteDocument(int id) async {
    final db = await _db;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }
}
