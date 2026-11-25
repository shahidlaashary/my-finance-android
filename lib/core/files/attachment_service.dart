
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/database_manager.dart';

import 'package:my_finance/core/files/file_storage.dart';
import 'package:my_finance/core/files/local_file_storage.dart';
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
  static final FileStorage _fileStorage = LocalFileStorage();

  // Shared connection is closed centrally by DatabaseManager.
  static Future<void> closeDatabase() => DatabaseManager.instance.close();

  static const String _tableName = 'finance_attachments';

  static Future<Database> get _database async {
    final db = DatabaseManager.instance.database;
    await _createTable(db);
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
      final tempRoot = await _fileStorage.getTemporaryPath();
      final stagingDir = p.join(
        tempRoot,
        'my_finance_asset_staging',
        DateTime.now().microsecondsSinceEpoch.toString(),
      );
      await _fileStorage.createDirectory(stagingDir);
      for (final source in sources) {
        final sourcePath = source['path']!;
        if (!await _fileStorage.fileExists(sourcePath)) {
          throw Exception('Selected attachment could not be found: ${source['name']}');
        }
        final name = source['name']!.trim().isEmpty
            ? p.basename(sourcePath)
            : source['name']!.trim();
        final targetPath = p.join(
          stagingDir,
          '${staged.length}_${p.basename(name)}',
        );
        await _fileStorage.copyFile(
          sourcePath: sourcePath,
          destinationPath: targetPath,
        );
        final size = await _fileStorage.fileLength(targetPath);
        if (size <= 0) throw Exception('Selected attachment is empty or could not be copied: $name');
        staged.add({'path': targetPath, 'name': name, 'size': size});
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

    final documentsDirectory = await _fileStorage.getApplicationDocumentsPath();
    final directory = p.join(
      documentsDirectory,
      'my_finance_attachments',
      '${AttachmentOwnerTypes.asset}_$assetId',
    );
    await _fileStorage.createDirectory(directory);
    for (final item in prepared) {
      final name = item['name'] as String;
      final stagedPath = item['path'] as String;
      if (!await _fileStorage.fileExists(stagedPath)) throw Exception('Prepared attachment is missing: $name');
      final uniqueName = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(name)}';
      final destinationPath = p.join(directory, uniqueName);
      await _fileStorage.copyFile(
        sourcePath: stagedPath,
        destinationPath: destinationPath,
      );
      createdPaths.add(destinationPath);
      final size = await _fileStorage.fileLength(destinationPath);
      if (size <= 0) throw Exception('Attachment could not be saved: $name');
      await txn.insert(_tableName, {
        'owner_type': AttachmentOwnerTypes.asset,
        'owner_id': assetId,
        'file_path': destinationPath,
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
        await _fileStorage.deleteFile(item['path'] as String);
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
        await _fileStorage.deleteFile(path);
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

    if (!await _fileStorage.fileExists(sourcePath)) {
      throw Exception('Selected file could not be found.');
    }

    final fileName = originalFileName?.trim().isNotEmpty == true
        ? originalFileName!.trim()
        : p.basename(sourcePath);

    final documentsDirectory =
        await _fileStorage.getApplicationDocumentsPath();

    final attachmentDirectory = p.join(
      documentsDirectory,
      'my_finance_attachments',
      '${normalizedType}_$ownerId',
    );

    await _fileStorage.createDirectory(attachmentDirectory);

    final uniqueName =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(fileName)}';

    final savedPath = p.join(
      attachmentDirectory,
      uniqueName,
    );

    await _fileStorage.copyFile(
      sourcePath: sourcePath,
      destinationPath: savedPath,
    );
    final fileSize = await _fileStorage.fileLength(savedPath);

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
      await _fileStorage.deleteFile(savedPath);
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

    try {
      await _fileStorage.deleteFile(attachment.filePath);
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
