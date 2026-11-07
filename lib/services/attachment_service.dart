
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/attachment_model.dart';

class AttachmentService {
  static const String _databaseName = 'my_finance.db';
  static const String _tableName = 'finance_attachments';

  static Future<Database> get _database async {
    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, _databaseName);

    return openDatabase(
      path,
      onOpen: (db) async {
        await _createTable(db);
      },
    );
  }

  static Future<void> _createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_type TEXT NOT NULL,
        owner_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_type TEXT NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        remote_url TEXT,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_attachments_owner
      ON $_tableName (owner_type, owner_id)
    ''');
  }

  static String _getFileType(String fileName) {
    final extension = p.extension(fileName).toLowerCase();

    if (['.jpg', '.jpeg', '.png', '.webp', '.heic'].contains(extension)) {
      return 'image';
    }

    if (extension == '.pdf') {
      return 'pdf';
    }

    return 'file';
  }

  /// Copies a selected file into permanent app storage and saves its record.
  static Future<AttachmentModel> addAttachment({
    required String ownerType,
    required int ownerId,
    required String sourcePath,
    String? originalFileName,
  }) async {
    if (ownerType.trim().isEmpty) {
      throw ArgumentError('Attachment owner type is required.');
    }

    if (ownerId <= 0) {
      throw ArgumentError('A valid owner ID is required.');
    }

    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw Exception('Selected file could not be found.');
    }

    final fileName = originalFileName?.trim().isNotEmpty == true
        ? originalFileName!.trim()
        : p.basename(sourcePath);

    final documentsDirectory = await getApplicationDocumentsDirectory();

    final attachmentDirectory = Directory(
      p.join(
        documentsDirectory.path,
        'my_finance_attachments',
        '${ownerType}_$ownerId',
      ),
    );

    await attachmentDirectory.create(recursive: true);

    final uniqueName =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(fileName)}';

    final savedPath = p.join(attachmentDirectory.path, uniqueName);

    final savedFile = await sourceFile.copy(savedPath);
    final fileSize = await savedFile.length();

    final attachment = AttachmentModel(
      ownerType: ownerType,
      ownerId: ownerId,
      filePath: savedPath,
      fileName: fileName,
      fileType: _getFileType(fileName),
      fileSize: fileSize,
      createdAt: DateTime.now(),
    );

    try {
      final db = await _database;
      final id = await db.insert(
        _tableName,
        attachment.toMap()..remove('id'),
      );

      return attachment.copyWith(id: id);
    } catch (error) {
      if (await savedFile.exists()) {
        await savedFile.delete();
      }
      rethrow;
    }
  }

  /// Returns all attachments belonging to a transaction or another record.
  static Future<List<AttachmentModel>> getAttachments({
    required String ownerType,
    required int ownerId,
  }) async {
    final db = await _database;

    final result = await db.query(
      _tableName,
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: [ownerType, ownerId],
      orderBy: 'created_at DESC',
    );

    return result.map(AttachmentModel.fromMap).toList();
  }

  /// Deletes the database record and its local file.
  static Future<void> deleteAttachment(int id) async {
    final db = await _database;

    final records = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (records.isEmpty) return;

    final attachment = AttachmentModel.fromMap(records.first);

    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );

    final file = File(attachment.filePath);

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('Could not delete attachment file: $error');
    }
  }

  /// Updates the cloud URL after a successful Firebase upload.
  static Future<void> updateRemoteUrl({
    required int id,
    required String remoteUrl,
  }) async {
    final db = await _database;

    await db.update(
      _tableName,
      {
        'remote_url': remoteUrl,
        'is_synced': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks an attachment as pending cloud synchronization.
  static Future<void> markPendingSync(int id) async {
    final db = await _database;

    await db.update(
      _tableName,
      {'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns attachments that still need cloud synchronization.
  static Future<List<AttachmentModel>> getPendingSync() async {
    final db = await _database;

    final result = await db.query(
      _tableName,
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );

    return result.map(AttachmentModel.fromMap).toList();
  }
}
