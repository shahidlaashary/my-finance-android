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

  /// Creates a ZIP backup containing a consistent database snapshot
  /// and all available attachment files.
  static Future<Uint8List> createBackup({
    required Database database,
  }) async {
    if (!database.isOpen) {
      throw Exception('Database connection is not open.');
    }

    final databaseDirectory = await getDatabasesPath();

    final databaseFile = File(
      p.join(databaseDirectory, _databaseName),
    );

    if (!await databaseFile.exists()) {
      throw Exception('Finance database could not be found.');
    }

    final temporaryDirectory = await getTemporaryDirectory();

    final snapshotName =
        'my_finance_backup_${DateTime.now().microsecondsSinceEpoch}.db';

    final snapshotFile = File(
      p.join(temporaryDirectory.path, snapshotName),
    );

    try {
      // VACUUM INTO creates a consistent database snapshot,
      // including committed WAL changes.
      final escapedPath = snapshotFile.path.replaceAll("'", "''");

      await database.execute(
        "VACUUM INTO '$escapedPath'",
      );

      if (!await snapshotFile.exists()) {
        throw Exception(
          'Could not create database backup snapshot.',
        );
      }

      final databaseBytes = await snapshotFile.readAsBytes();

      if (databaseBytes.isEmpty) {
        throw Exception('Database backup snapshot is empty.');
      }

      final archive = Archive();

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
        p.join(
          documentsDirectory.path,
          _attachmentFolder,
        ),
      );

      var attachmentCount = 0;

      if (await attachmentDirectory.exists()) {
        await for (final entity
            in attachmentDirectory.list(recursive: true)) {
          if (entity is! File) continue;

          // Do not include symbolic links.
          final entityType = await FileSystemEntity.type(
            entity.path,
            followLinks: false,
          );

          if (entityType != FileSystemEntityType.file) {
            continue;
          }

          final relativePath = p.relative(
            entity.path,
            from: attachmentDirectory.path,
          );

          final normalizedRelativePath = p.posix.joinAll(
            p.split(relativePath),
          );

          final archivePath = p.posix.join(
            'attachments',
            normalizedRelativePath,
          );

          _validateArchivePath(archivePath);

          final bytes = await entity.readAsBytes();

          archive.addFile(
            ArchiveFile(
              archivePath,
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

      final manifestBytes = utf8.encode(
        jsonEncode(manifest),
      );

      archive.addFile(
        ArchiveFile(
          _manifestPath,
          manifestBytes.length,
          manifestBytes,
        ),
      );

      final zipBytes = ZipEncoder().encode(archive);

      return Uint8List.fromList(zipBytes);
    } finally {
      if (await snapshotFile.exists()) {
        await snapshotFile.delete();
      }
    }
  }

  /// Restores a previously created My Finance ZIP backup.
  ///
  /// IMPORTANT:
  /// The caller must close the active database connection
  /// before calling this method and reopen it afterwards.
  static Future<void> restoreBackup({
    required Uint8List backupBytes,
  }) async {
    if (backupBytes.isEmpty) {
      throw Exception('Backup file is empty.');
    }

    final archive = ZipDecoder().decodeBytes(backupBytes);

    final files = <String, ArchiveFile>{};

    for (final entry in archive.files) {
      if (!entry.isFile) continue;

      final normalizedPath = _validateArchivePath(
        entry.name,
      );

      if (files.containsKey(normalizedPath)) {
        throw Exception(
          'Backup contains duplicate file paths.',
        );
      }

      files[normalizedPath] = entry;
    }

    // Validate manifest.
    final manifestFile = files[_manifestPath];

    if (manifestFile == null) {
      throw Exception(
        'This ZIP is not a valid My Finance backup.',
      );
    }

    final manifestBytes = manifestFile.content as List<int>;

    final decodedManifest = jsonDecode(
      utf8.decode(manifestBytes),
    );

    if (decodedManifest is! Map<String, dynamic> ||
        decodedManifest['app'] != 'My Finance' ||
        decodedManifest['format_version'] != 1 ||
        decodedManifest['database'] != _backupDatabasePath ||
        decodedManifest['attachment_count'] is! int ||
        (decodedManifest['attachment_count'] as int) < 0) {
      throw Exception(
        'Unsupported or invalid backup format.',
      );
    }

    // Validate database file.
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

    // Validate attachment count.
    final actualAttachmentCount = files.keys
        .where((path) => path.startsWith('attachments/'))
        .length;

    if (actualAttachmentCount !=
        decodedManifest['attachment_count']) {
      throw Exception(
        'Backup attachment information is incomplete or invalid.',
      );
    }

    final databaseDirectory = await getDatabasesPath();

    final documentsDirectory =
        await getApplicationDocumentsDirectory();

    await Directory(databaseDirectory).create(
      recursive: true,
    );

    final currentDatabase = File(
      p.join(databaseDirectory, _databaseName),
    );

    final currentAttachments = Directory(
      p.join(
        documentsDirectory.path,
        _attachmentFolder,
      ),
    );

    final uniqueId = DateTime.now().microsecondsSinceEpoch;

    // Temporary files are created beside their final destinations
    // so rename operations stay on the same filesystem.
    final stagedDatabase = File(
      p.join(
        databaseDirectory,
        'my_finance_restore_$uniqueId.db',
      ),
    );

    final oldDatabase = File(
      p.join(
        databaseDirectory,
        'my_finance_previous_$uniqueId.db',
      ),
    );

    final stagedAttachments = Directory(
      p.join(
        documentsDirectory.path,
        'my_finance_attachments_restore_$uniqueId',
      ),
    );

    final oldAttachments = Directory(
      p.join(
        documentsDirectory.path,
        'my_finance_attachments_previous_$uniqueId',
      ),
    );

    var databaseMoved = false;
    var databaseInstalled = false;
    var attachmentsMoved = false;
    var attachmentsInstalled = false;

    try {
      // Write database into staging.
      await stagedDatabase.writeAsBytes(
        databaseBytes,
        flush: true,
      );

      // Validate SQLite database before replacing current data.
      final validationDatabase = await openDatabase(
        stagedDatabase.path,
        readOnly: true,
      );

      try {
        final integrity = await validationDatabase.rawQuery(
          'PRAGMA integrity_check',
        );

        if (integrity.isEmpty ||
            integrity.first.values.first
                    .toString()
                    .toLowerCase() !=
                'ok') {
          throw Exception(
            'Backup database failed integrity check.',
          );
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

      // Prepare attachment staging directory.
      await stagedAttachments.create(recursive: true);

      for (final entry in files.entries) {
        if (!entry.key.startsWith('attachments/')) {
          continue;
        }

        final relativePath = entry.key.substring(
          'attachments/'.length,
        );

        if (relativePath.isEmpty) {
          continue;
        }

        _validateArchivePath(relativePath);

        final outputPath = p.join(
          stagedAttachments.path,
          p.joinAll(p.posix.split(relativePath)),
        );

        final outputFile = File(outputPath);

        await outputFile.parent.create(
          recursive: true,
        );

        await outputFile.writeAsBytes(
          entry.value.content as List<int>,
          flush: true,
        );
      }

      // Move existing database aside.
      if (await currentDatabase.exists()) {
        await currentDatabase.rename(oldDatabase.path);
        databaseMoved = true;
      }

      // Remove SQLite WAL and shared-memory sidecar files.
      await _deleteDatabaseSidecars(currentDatabase.path);

      // Install restored database.
      await stagedDatabase.rename(currentDatabase.path);
      databaseInstalled = true;

      // Move existing attachments aside.
      if (await currentAttachments.exists()) {
        await currentAttachments.rename(oldAttachments.path);
        attachmentsMoved = true;
      }

      // Install restored attachments.
      await stagedAttachments.rename(
        currentAttachments.path,
      );

      attachmentsInstalled = true;
    } catch (error) {
      // Roll back attachments if installation failed.
      if (attachmentsInstalled &&
          await currentAttachments.exists()) {
        await currentAttachments.delete(recursive: true);
      }

      if (attachmentsMoved &&
          await oldAttachments.exists()) {
        await oldAttachments.rename(
          currentAttachments.path,
        );
      }

      // Roll back database if installation failed.
      if (databaseInstalled &&
          await currentDatabase.exists()) {
        await currentDatabase.delete();
      }

      if (databaseMoved &&
          await oldDatabase.exists()) {
        await oldDatabase.rename(
          currentDatabase.path,
        );
      }

      rethrow;
    } finally {
      if (await stagedDatabase.exists()) {
        await stagedDatabase.delete();
      }

      if (await stagedAttachments.exists()) {
        await stagedAttachments.delete(recursive: true);
      }
    }

    // Restore is now committed.
    // Old files are cleaned up separately so a cleanup error
    // cannot trigger rollback after successful installation.
    try {
      if (await oldDatabase.exists()) {
        await oldDatabase.delete();
      }
    } catch (_) {
      // Keep the previous database if cleanup fails.
    }

    try {
      if (await oldAttachments.exists()) {
        await oldAttachments.delete(recursive: true);
      }
    } catch (_) {
      // Keep previous attachments if cleanup fails.
    }
  }

  /// Validates archive paths to prevent directory traversal.
  static String _validateArchivePath(String path) {
    final normalized = path.replaceAll('\\', '/');

    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.startsWith('~') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      throw Exception(
        'Backup contains an unsafe file path.',
      );
    }

    final segments = normalized.split('/');

    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..',
    )) {
      throw Exception(
        'Backup contains an unsafe file path.',
      );
    }

    final result = p.posix.normalize(normalized);

    if (result == '.' ||
        result == '..' ||
        result.startsWith('../')) {
      throw Exception(
        'Backup contains an unsafe file path.',
      );
    }

    return result;
  }

  /// Removes SQLite WAL and shared-memory sidecar files.
  static Future<void> _deleteDatabaseSidecars(
    String databasePath,
  ) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('$databasePath$suffix');

      if (await sidecar.exists()) {
        await sidecar.delete();
      }
    }
  }
}
