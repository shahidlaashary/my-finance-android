/// App-wide services ke liye common file operations ka contract.
///
/// Native filesystem objects aur operations implementation ke andar rakhein.
/// Callers child paths bana sakte hain, lekin dart:io ko seedha use na karein.
/// File storage ke liye platform-independent operations define karta hai.
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
