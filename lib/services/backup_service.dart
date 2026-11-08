import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
class BackupService {
  BackupService._();
  static const String _databaseName = 'my_finance.db';
  static const String _attachmentFolder = 'my_finance_attachments';
  static const String _backupDatabasePath = 'database/my_finance.db';
  static const String _manifestPath = 'manifest.json';
  /// Creates a ZIP backup containing the database and all attachments.
  ///
  /// The caller must ensure the database is not being modified during
  /// backup creation. A WAL checkpoint is performed before reading it.
  static Future<Uint8List> createBackup({
    required Database database,
  }) async {
    final databaseDirectory = await getDatabasesPath();
    final databaseFile = File(
      p.join(databaseDirectory, _databaseName),
    );
    if (!await databaseFile.exists()) {
      throw Exception('Finance database could not be found.');
    }
    // Flush pending SQLite WAL changes into the main database file.
    await database.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final archive = Archive();
    final databaseBytes = await databaseFile.readAsBytes();
    archive.addFile(
      ArchiveFile(
        _backupDatabasePath,
        databaseBytes.length,
        databaseBytes,
      ),
    );
    final documentsDirectory =
        await getApplicationDocumentsDirectory();
    final attachmentDirectory = Directory(
      p.join(documentsDirectory.path, _attachmentFolder),
    );
    var attachmentCount = 0;
    if (await attachmentDirectory.exists()) {
      await for (final entity
          in attachmentDirectory.list(recursive: true)) {
        if (entity is! File) continue;
        final relativePath = p.relative(
          entity.path,
          from: attachmentDirectory.path,
        );
        final normalizedPath = p.posix.join(
          'attachments',
          p.posix.joinAll(p.split(relativePath)),
        );
        final bytes = await entity.readAsBytes();
        archive.addFile(
          ArchiveFile(
            normalizedPath,
            bytes.length,
            bytes,
          ),
        );
        attachmentCount++;
      }
    }
    final manifest = {
      'app': 'My Finance',
      'format_version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'database': _backupDatabasePath,
      'attachment_count': attachmentCount,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile(
        _manifestPath,
        manifestBytes.length,
        manifestBytes,
      ),
    );
    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes);
  }
  /// Restores a previously created My Finance ZIP backup.
  ///
  /// The caller MUST close the active database connection before calling
  /// this method, then reopen it after a successful restore.
  static Future<void> restoreBackup({
    required Uint8List backupBytes,
  }) async {
    final archive = ZipDecoder().decodeBytes(backupBytes);
    final files = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final fileName = entry.name.replaceAll('\\', '/');
      final normalized = p.posix.normalize(fileName);
      if (normalized.startsWith('/') ||
          normalized == '..' ||
          normalized.startsWith('../') ||
          normalized.contains('/../')) {
        throw Exception('Backup contains an unsafe file path.');
      }
      files[normalized] = entry;
    }
    final manifestFile = files[_manifestPath];
    if (manifestFile == null) {
      throw Exception('This ZIP is not a valid My Finance backup.');
    }
    final manifestBytes = manifestFile.content as List<int>;
    final manifest = jsonDecode(
      utf8.decode(manifestBytes),
    );
    if (manifest is! Map<String, dynamic> ||
        manifest['app'] != 'My Finance' ||
        manifest['format_version'] != 1) {
      throw Exception('Unsupported or invalid backup format.');
    }
    final databaseArchiveFile = files[_backupDatabasePath];
    if (databaseArchiveFile == null) {
      throw Exception('Backup database file is missing.');
    }
    final databaseBytes = Uint8List.fromList(
      databaseArchiveFile.content as List<int>,
    );
    if (databaseBytes.isEmpty) {
      throw Exception('Backup database file is empty.');
    }
    final temporaryDirectory =
        await getTemporaryDirectory();
    final stagingDirectory = Directory(
      p.join(
        temporaryDirectory.path,
        'my_finance_restore_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await stagingDirectory.create(recursive: true);
    try {
      // Validate the database before replacing the existing one.
      final stagedDatabase = File(
        p.join(stagingDirectory.path, _databaseName),
      );
      await stagedDatabase.writeAsBytes(
        databaseBytes,
        flush: true,
      );
      final validationDatabase = await openDatabase(
        stagedDatabase.path,
        readOnly: true,
      );
      try {
        final integrity = await validationDatabase.rawQuery(
          'PRAGMA integrity_check',
        );
        if (integrity.isEmpty ||
            integrity.first.values.first.toString().toLowerCase() !=
                'ok') {
          throw Exception('Backup database failed integrity check.');
        }
        final tables = await validationDatabase.rawQuery('''
          SELECT name
          FROM sqlite_master
          WHERE type = 'table'
            AND name NOT LIKE 'sqlite_%'
        ''');
        final tableNames = tables
            .map((row) => row['name']?.toString())
            .whereType<String>()
            .toSet();
        if (!tableNames.contains('accounts') ||
            !tableNames.contains('transactions')) {
          throw Exception(
            'Backup does not contain the required finance tables.',
          );
        }
      } finally {
        await validationDatabase.close();
      }
      // Extract attachment files into a separate staging directory.
      final stagedAttachments = Directory(
        p.join(stagingDirectory.path, _attachmentFolder),
      );
      await stagedAttachments.create(recursive: true);
      for (final entry in files.entries) {
        if (!entry.key.startsWith('attachments/')) continue;
        final relativePath = entry.key.substring(
          'attachments/'.length,
        );
        if (relativePath.isEmpty) continue;
        final outputPath = p.join(
          stagedAttachments.path,
          p.joinAll(p.posix.split(relativePath)),
        );
        final outputFile = File(outputPath);
        await outputFile.parent.create(recursive: true);
        await outputFile.writeAsBytes(
          entry.value.content as List<int>,
          flush: true,
        );
      }
      final databaseDirectory = await getDatabasesPath();
      final currentDatabase = File(
        p.join(databaseDirectory, _databaseName),
      );
      final documentsDirectory =
          await getApplicationDocumentsDirectory();
      final currentAttachments = Directory(
        p.join(documentsDirectory.path, _attachmentFolder),
      );
      // Keep the old files temporarily so a failed copy can be rolled back.
      final oldDatabase = File(
        p.join(stagingDirectory.path, 'old_database.db'),
      );
      final oldAttachments = Directory(
        p.join(stagingDirectory.path, 'old_attachments'),
      );
      var databaseReplaced = false;
      var attachmentsReplaced = false;
      try {
        if (await currentDatabase.exists()) {
          await currentDatabase.copy(oldDatabase.path);
        }
        if (await currentAttachments.exists()) {
          await currentAttachments.rename(oldAttachments.path);
        }
        await stagedAttachments.rename(currentAttachments.path);
        attachmentsReplaced = true;
        await stagedDatabase.copy(currentDatabase.path);
        databaseReplaced = true;
      } catch (error) {
        // Restore previous files if replacement fails.
        if (databaseReplaced && await oldDatabase.exists()) {
          await oldDatabase.copy(currentDatabase.path);
        }
        if (attachmentsReplaced &&
            await currentAttachments.exists()) {
          await currentAttachments.delete(recursive: true);
        }
        if (await oldAttachments.exists()) {
          await oldAttachments.rename(currentAttachments.path);
        }
        rethrow;
      }
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
  }
}
