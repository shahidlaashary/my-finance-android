import 'package:sqflite/sqflite.dart';
import 'package:my_finance/modules/space/services/my_space_service.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

/// My Space document ka metadata, dates, reminder aur favorite status represent karta hai.
class SpaceDocumentModel {
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

  const SpaceDocumentModel({
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

  factory SpaceDocumentModel.fromMap(Map<String, dynamic> map) {
    return SpaceDocumentModel(
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

  SpaceDocumentModel copyWith({int? id, bool? isFavorite, DateTime? updatedAt}) => SpaceDocumentModel(
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

/// Document metadata is stored in the My Space database (space.db).
/// The module shares MySpaceService's connection and backup/restore lifecycle.
/// My Space documents ka metadata aur document-related operations manage karta hai.
class SpaceDocumentsService {
  SpaceDocumentsService._();
  static final SpaceDocumentsService instance = SpaceDocumentsService._();

  static const String _table = 'space_documents';

  Future<Database> get _db async {
    final db = await MySpaceService.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'Other',
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
    return db;
  }

  Future<List<SpaceDocumentModel>> getDocuments({
    String category = 'All',
    String filter = 'All',
  }) async {
    final db = await _db;
    final rows = await db.query(_table, orderBy: 'updated_at DESC');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return rows.map((row) => SpaceDocumentModel.fromMap(
      Map<String, dynamic>.from(row),
    )).where((document) {
      if (category != 'All' && document.category != category) return false;
      if (filter == 'Favorites' && !document.isFavorite) return false;
      if (filter == 'Expiring Soon') {
        final expiry = document.expiryDate;
        if (expiry == null) return false;
        final days = DateTime(expiry.year, expiry.month, expiry.day)
            .difference(today).inDays;
        if (days < 0 || days > document.reminderDays) return false;
      }
      if (filter == 'Expired') {
        final expiry = document.expiryDate;
        if (expiry == null ||
            !DateTime(expiry.year, expiry.month, expiry.day).isBefore(today)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<int> addDocument(SpaceDocumentModel document) async {
    final db = await _db;
    final id = document.id ?? DateTime.now().microsecondsSinceEpoch;
    await db.insert(_table, document.copyWith(id: id).toMap());
    AppRefreshController.notifyChanged();
    return id;
  }

  Future<void> updateDocument(SpaceDocumentModel document) async {
    if (document.id == null) throw ArgumentError('Document ID is required.');
    final db = await _db;
    final changed = await db.update(
      _table, document.toMap(),
      where: 'id = ?', whereArgs: [document.id],
    );
    if (changed == 0) throw StateError('Document not found.');
    AppRefreshController.notifyChanged();
  }

  Future<void> toggleFavorite(SpaceDocumentModel document) async {
    if (document.id == null) return;
    final db = await _db;
    await db.update(_table, {
      'is_favorite': document.isFavorite ? 0 : 1,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [document.id]);
    AppRefreshController.notifyChanged();
  }

  Future<void> deleteDocument(int id) async {
    final db = await _db;
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final record = Map<String, dynamic>.from(rows.first);
    await RecycleBinService.archive(
      type: 'Document',
      title: record['title']?.toString() ?? 'Document',
      table: 'space_documents_records',
      id: id,
      record: record,
    );
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }

  /// Restores a document payload from the app-wide Recycle Bin into space.db.
  Future<void> restoreArchivedRecord(Map<String, dynamic> record) async {
    final db = await _db;
    final id = (record['id'] as num?)?.toInt();
    if (id == null) throw StateError('Archived document has an invalid ID.');
    final existing = await db.query(
      _table, columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1,
    );
    if (existing.isNotEmpty) {
      throw StateError('A document with this ID already exists.');
    }
    await db.insert(_table, record);
    AppRefreshController.notifyChanged();
  }
}
