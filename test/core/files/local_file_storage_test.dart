import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/core/files/local_file_storage.dart';

void main() {
  late Directory sandbox;
  late LocalFileStorage storage;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('my_finance_file_storage_');
    final documents = Directory('${sandbox.path}/documents');
    final temporary = Directory('${sandbox.path}/temporary');
    storage = LocalFileStorage(
      documentsDirectoryProvider: () async => documents,
      temporaryDirectoryProvider: () async => temporary,
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('returns configured application directories', () async {
    expect(await storage.getApplicationDocumentsPath(),
        '${sandbox.path}/documents');
    expect(await storage.getTemporaryPath(), '${sandbox.path}/temporary');
  });

  test('creates directories and copies files', () async {
    final source = File('${sandbox.path}/source.txt');
    await source.writeAsString('attachment content');
    final destination = '${sandbox.path}/nested/copy.txt';

    await storage.createDirectory('${sandbox.path}/nested');
    final copiedPath = await storage.copyFile(
      sourcePath: source.path,
      destinationPath: destination,
    );

    expect(copiedPath, destination);
    expect(await storage.fileExists(destination), isTrue);
    expect(await storage.fileLength(destination), 'attachment content'.length);
    expect(await File(destination).readAsString(), 'attachment content');
  });

  test('writes bytes to a file and flushes the content', () async {
    final path = '${sandbox.path}/written/report.bin';
    final bytes = [0, 1, 2, 255];

    await storage.createDirectory('${sandbox.path}/written');
    await storage.writeBytes(path: path, bytes: bytes);

    expect(await storage.fileExists(path), isTrue);
    expect(await File(path).readAsBytes(), bytes);
  });

  test('deletes files and safely ignores missing files', () async {
    final file = File('${sandbox.path}/remove.txt');
    await file.writeAsString('remove me');

    await storage.deleteFile(file.path);
    await storage.deleteFile(file.path);

    expect(await storage.fileExists(file.path), isFalse);
  });
}
