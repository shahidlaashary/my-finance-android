import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'file_storage.dart';

/// Native filesystem adapter for Android, iOS, Windows and macOS.
///
/// Directory providers are injectable so filesystem behavior can be tested
/// without depending on the host platform's application directories.
class LocalFileStorage implements FileStorage {
  LocalFileStorage({
    Future<Directory> Function()? documentsDirectoryProvider,
    Future<Directory> Function()? temporaryDirectoryProvider,
  })  : _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory;

  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<Directory> Function() _temporaryDirectoryProvider;

  @override
  Future<String> getApplicationDocumentsPath() async =>
      (await _documentsDirectoryProvider()).path;

  @override
  Future<String> getTemporaryPath() async =>
      (await _temporaryDirectoryProvider()).path;

  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<String> copyFile({
    required String sourcePath,
    required String destinationPath,
  }) async {
    final copied = await File(sourcePath).copy(destinationPath);
    return copied.path;
  }

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<int> fileLength(String path) => File(path).length();

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
