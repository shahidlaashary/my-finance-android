import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'file_storage.dart';

/// Android, iOS, Windows aur macOS ke liye native filesystem adapter.
///
/// Directory providers inject kiye ja sakte hain taake tests host platform ke
/// asal application folders par depend kiye baghair filesystem check kar sakein.
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

  /// App documents folder ka path return karta hai.
  @override
  Future<String> getApplicationDocumentsPath() async =>
      (await _documentsDirectoryProvider()).path;

  /// Temporary files ke folder ka path return karta hai.
  @override
  Future<String> getTemporaryPath() async =>
      (await _temporaryDirectoryProvider()).path;

  /// Diye gaye path par zaroorat ke mutabiq parent folders bhi banata hai.
  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  /// Source file ko destination par copy karke naya path return karta hai.
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
  Future<void> writeBytes({
    required String path,
    required List<int> bytes,
  }) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
