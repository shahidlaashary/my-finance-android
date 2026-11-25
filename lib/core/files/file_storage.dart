/// Shared file operations used by app-wide services.
///
/// Keep native filesystem objects and operations inside the implementation.
/// Callers may compose child paths, but must not use dart:io directly.
abstract interface class FileStorage {
  Future<String> getApplicationDocumentsPath();

  Future<String> getTemporaryPath();

  Future<void> createDirectory(String path);

  Future<String> copyFile({
    required String sourcePath,
    required String destinationPath,
  });

  Future<bool> fileExists(String path);

  Future<int> fileLength(String path);

  Future<void> writeBytes({
    required String path,
    required List<int> bytes,
  });

  Future<void> deleteFile(String path);
}
