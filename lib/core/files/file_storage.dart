/// Shared file operations used by app-wide services.
///
/// Keep platform-specific filesystem APIs inside the implementation. Paths are
/// opaque strings to callers and must not be assembled outside this boundary.
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

  Future<void> deleteFile(String path);
}
