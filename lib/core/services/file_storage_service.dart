import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Shared local file storage and opening operations for app modules.
class FileStorageService {
  FileStorageService._();

  /// Copies a picked file into the app's private documents directory.
  static Future<String?> storePickedFile(
    PlatformFile file, {
    required String directory,
  }) async {
    final sourcePath = file.path;
    if (sourcePath == null || sourcePath.isEmpty) return null;

    final root = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory(p.join(root.path, directory));
    await targetDirectory.create(recursive: true);

    final safeName = p.basename(file.name);
    final uniqueName = '${DateTime.now().microsecondsSinceEpoch}_$safeName';
    final targetPath = p.join(targetDirectory.path, uniqueName);
    return (await File(sourcePath).copy(targetPath)).path;
  }

  /// Deletes only files stored inside this app's private documents directory.
  /// Returns false for paths outside the app-managed storage area.
  static Future<bool> deleteStoredFile(String path) async {
    if (path.trim().isEmpty) return false;
    final root = await getApplicationDocumentsDirectory();
    final rootPath = p.normalize(p.absolute(root.path));
    final targetPath = p.normalize(p.absolute(path));
    if (!p.isWithin(rootPath, targetPath)) return false;
    final file = File(targetPath);
    if (!await file.exists()) return true;
    await file.delete();
    return true;
  }

  /// Opens a file using the platform's registered viewer.
  static Future<bool> openFile(String path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }
}
