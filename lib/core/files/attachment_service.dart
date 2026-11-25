
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/models/attachment_model.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

/// My Finance ke tamam modules ke liye attachment owner types.
class AttachmentOwnerTypes {
  static const String transaction = 'transaction';
  static const String asset = 'asset';
  static const String loan = 'loan';
  static const String goal = 'goal';
  static const String repayment = 'repayment';
  static const String vehicle = 'vehicle';
  static const String vehicleFuel = 'vehicle_fuel';
  static const String vehicleExpense = 'vehicle_expense';
  static const String document = 'document';
  static const String party = 'party';
  static const String recurring = 'recurring';
  static const String agreement = 'agreement';

  static const List<String> all = [
    transaction,
    asset,
    loan,
    goal,
    repayment,
    vehicle,
    vehicleFuel,
    vehicleExpense,
    document,
    party,
    recurring,
    agreement,
  ];
}

class AttachmentService {

  // Restore se pehle is service ka database connection band karta hai.
  static Future<void> closeDatabase() async {
    final currentDatabase = _databaseInstance;
    _databaseInstance = null;
    _databaseFuture = null;
    if (currentDatabase != null && currentDatabase.isOpen) {
      await currentDatabase.close();
    }
  }
  static const String _databaseName = 'my_finance.db';
  static const String _tableName = 'finance_attachments';

  static Database? _databaseInstance;
  static Future<Database>? _databaseFuture;

  static Future<Database> get _database async {
    if (_databaseInstance != null && _databaseInstance!.isOpen) {
      return _databaseInstance!;
    }

    final pendingFuture = _databaseFuture;

    if (pendingFuture != null) {
      return pendingFuture;
    }

    final future = _openDatabase();
    _databaseFuture = future;

    try {
      return await future;
    } catch (_) {
      if (identical(_databaseFuture, future)) {
        _databaseFuture = null;
      }
      rethrow;
    }
  }

  static Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, _databaseName);

    // openDatabase may reuse FinanceDB's already-open connection, in
    // which case its onOpen callback is not guaranteed to run.
    final db = await openDatabase(path);

    // Always ensure the attachment table exists on the shared connection.
    // CREATE TABLE IF NOT EXISTS preserves existing attachment records.
    await _createTable(db);

    _databaseInstance = db;
    return db;
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
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_attachments_owner
      ON $_tableName (owner_type, owner_id)
    ''');
  }

  static String _normalizeOwnerType(String ownerType) {
    final value = ownerType.trim().toLowerCase();

    if (!AttachmentOwnerTypes.all.contains(value)) {
      throw ArgumentError('Unsupported attachment owner type: $value');
    }

    return value;
  }

  static String _getFileType(String fileName) {
    final extension = p.extension(fileName).toLowerCase();

    if ([
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
    ].contains(extension)) {
      return 'image';
    }

    if (extension == '.pdf') {
      return 'pdf';
    }

    return 'file';
  }

  /// Asset save se pehle tamam selected files ko temporary storage mein copy karta hai.
  /// Is stage par database mein koi attachment row ya finance record create nahi hota.
  static Future<List<Map<String, dynamic>>> prepareAssetAttachments(
    List<Map<String, String>> sources,
  ) async {
    if (sources.isEmpty) return const <Map<String, dynamic>>[];

    final staged = <Map<String, dynamic>>[];
    try {
      final tempRoot = await getTemporaryDirectory();
      final stagingDir = Directory(p.join(
        tempRoot.path,
        'my_finance_asset_staging',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ));
      await stagingDir.create(recursive: true);
      for (final source in sources) {
        final sourcePath = source['path']!;
        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists()) {
          throw Exception('Selected attachment could not be found: ${source['name']}');
        }
        final name = source['name']!.trim().isEmpty
            ? p.basename(sourcePath)
            : source['name']!.trim();
        final target = File(p.join(stagingDir.path, '${staged.length}_${p.basename(name)}'));
        await sourceFile.copy(target.path);
        final size = await target.length();
        if (size <= 0) throw Exception('Selected attachment is empty or could not be copied: $name');
        staged.add({'path': target.path, 'name': name, 'size': size});
      }
      return staged;
    } catch (_) {
      await cleanupPreparedAssetAttachments(staged);
      rethrow;
    }
  }

  /// Asset transaction ke andar prepared files ko final folder mein copy aur
  /// attachment metadata insert karta hai. Transaction fail ho to caller files clean karta hai.
  static Future<void> insertPreparedAssetAttachments({
    required Transaction txn,
    required int assetId,
    required List<Map<String, dynamic>> prepared,
    required List<String> createdPaths,
  }) async {
    if (assetId <= 0) throw ArgumentError('A valid asset ID is required.');
    if (prepared.isEmpty) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(
      documentsDirectory.path,
      'my_finance_attachments',
      '${AttachmentOwnerTypes.asset}_$assetId',
    ));
    await directory.create(recursive: true);
    for (final item in prepared) {
      final name = item['name'] as String;
      final stagedFile = File(item['path'] as String);
      if (!await stagedFile.exists()) throw Exception('Prepared attachment is missing: $name');
      final uniqueName = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(name)}';
      final destination = File(p.join(directory.path, uniqueName));
      await stagedFile.copy(destination.path);
      createdPaths.add(destination.path);
      final size = await destination.length();
      if (size <= 0) throw Exception('Attachment could not be saved: $name');
      await txn.insert(_tableName, {
        'owner_type': AttachmentOwnerTypes.asset,
        'owner_id': assetId,
        'file_path': destination.path,
        'file_name': name,
        'file_type': _getFileType(name),
        'file_size': size,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  static Future<void> cleanupPreparedAssetAttachments(
    List<Map<String, dynamic>> prepared,
  ) async {
    for (final item in prepared) {
      try {
        final file = File(item['path'] as String);
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('Could not clean staged asset attachment: $error');
      }
    }
  }

  static Future<void> cleanupCreatedAssetAttachmentFiles(
    List<String> paths,
  ) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('Could not clean failed asset attachment: $error');
      }
    }
  }

  /// Kisi bhi finance record ke sath photo, PDF ya supported document save karta hai.
  static Future<AttachmentModel> addAttachment({
    required String ownerType,
    required int ownerId,
    required String sourcePath,
    String? originalFileName,
  }) async {
    final normalizedType = _normalizeOwnerType(ownerType);

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

    final documentsDirectory =
        await getApplicationDocumentsDirectory();

    final attachmentDirectory = Directory(
      p.join(
        documentsDirectory.path,
        'my_finance_attachments',
        '${normalizedType}_$ownerId',
      ),
    );

    await attachmentDirectory.create(recursive: true);

    final uniqueName =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(fileName)}';

    final savedPath = p.join(
      attachmentDirectory.path,
      uniqueName,
    );

    final savedFile = await sourceFile.copy(savedPath);
    final fileSize = await savedFile.length();

    final attachment = AttachmentModel(
      ownerType: normalizedType,
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
      AppRefreshController.notifyChanged();

      return attachment.copyWith(id: id);
    } catch (error) {
      if (await savedFile.exists()) {
        await savedFile.delete();
      }
      rethrow;
    }
  }

  /// Kisi khaas record ki attachments hasil karta hai.
  static Future<List<AttachmentModel>> getAttachments({
    required String ownerType,
    required int ownerId,
  }) async {
    final normalizedType = _normalizeOwnerType(ownerType);
    final db = await _database;

    final result = await db.query(
      _tableName,
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: [normalizedType, ownerId],
      orderBy: 'created_at DESC',
    );

    return result.map(AttachmentModel.fromMap).toList();
  }

  /// Har finance module ke liye asaan helper methods.
  static Future<List<AttachmentModel>> getTransactionAttachments(
    int transactionId,
  ) {
    return getAttachments(
      ownerType: AttachmentOwnerTypes.transaction,
      ownerId: transactionId,
    );
  }

  static Future<List<AttachmentModel>> getAssetAttachments(
    int assetId,
  ) {
    return getAttachments(
      ownerType: AttachmentOwnerTypes.asset,
      ownerId: assetId,
    );
  }

  static Future<List<AttachmentModel>> getLoanAttachments(
    int loanId,
  ) {
    return getAttachments(
      ownerType: AttachmentOwnerTypes.loan,
      ownerId: loanId,
    );
  }

  static Future<List<AttachmentModel>> getSavingsAttachments(
    int goalId,
  ) {
    return getAttachments(
      ownerType: AttachmentOwnerTypes.goal,
      ownerId: goalId,
    );
  }

  static Future<List<AttachmentModel>> getRepaymentAttachments(
    int repaymentId,
  ) {
    return getAttachments(
      ownerType: AttachmentOwnerTypes.repayment,
      ownerId: repaymentId,
    );
  }

  /// Attachment ka record aur uski local file delete karta hai.
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
    AppRefreshController.notifyChanged();

    final file = File(attachment.filePath);

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('Could not delete attachment file: $error');
    }
  }

  /// Kisi record ke sath linked tamam attachments delete karta hai.
  static Future<void> deleteOwnerAttachments({
    required String ownerType,
    required int ownerId,
  }) async {
    final attachments = await getAttachments(
      ownerType: ownerType,
      ownerId: ownerId,
    );

    for (final attachment in attachments) {
      if (attachment.id != null) {
        await deleteAttachment(attachment.id!);
      }
    }
  }

}
