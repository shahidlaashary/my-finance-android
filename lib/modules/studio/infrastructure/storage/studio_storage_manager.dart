import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns Studio's private on-device media directory structure.
///
/// All media stays inside the app's support directory and is independent
/// from My Space's document library.
class StudioStorageManager {
  StudioStorageManager({Directory? rootDirectory})
      : _providedRootDirectory = rootDirectory;

  final Directory? _providedRootDirectory;
  Future<Directory>? _rootDirectoryFuture;

  Future<Directory> get rootDirectory {
    return _rootDirectoryFuture ??= _resolveRootDirectory();
  }

  Future<Directory> _resolveRootDirectory() async {
    final base = _providedRootDirectory ?? await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'studio'));
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> directoryFor(String category) async {
    const supported = {
      'audio',
      'video',
      'thumbnails',
      'fingerprints',
      'temporary',
    };
    if (!supported.contains(category)) {
      throw ArgumentError.value(category, 'category', 'Unsupported Studio storage category.');
    }

    final root = await rootDirectory;
    final directory = Directory(p.join(root.path, category));
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> allocateMediaFile({
    required String id,
    required String extension,
    required bool isVideo,
  }) async {
    if (id.trim().isEmpty || id.contains('/') || id.contains(r'\\')) {
      throw ArgumentError.value(id, 'id', 'A safe, non-empty media ID is required.');
    }
    final directory = await directoryFor(isVideo ? 'video' : 'audio');
    final normalizedExtension = extension.startsWith('.')
        ? extension
        : '.$extension';
    return File(p.join(directory.path, '$id$normalizedExtension'));
  }

  Future<File> allocateFingerprintFile({
    required String fingerprintId,
    required String extension,
  }) async {
    if (fingerprintId.trim().isEmpty ||
        fingerprintId.contains('/') ||
        fingerprintId.contains(r'\\')) {
      throw ArgumentError.value(
        fingerprintId,
        'fingerprintId',
        'A safe, non-empty fingerprint ID is required.',
      );
    }
    final directory = await directoryFor('fingerprints');
    final normalizedExtension =
        extension.startsWith('.') ? extension : '.$extension';
    return File(p.join(directory.path, '$fingerprintId$normalizedExtension'));
  }

  Future<int> calculateTotalBytes() async {
    final root = await rootDirectory;
    if (!await root.exists()) return 0;

    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<bool> fileExists(String path) async => File(path).exists();

  Future<void> deleteManagedFile(String path) async {
    final root = await rootDirectory;
    final normalizedRoot = p.normalize(root.absolute.path);
    final normalizedFile = p.normalize(p.absolute(path));
    if (!p.isWithin(normalizedRoot, normalizedFile)) {
      throw ArgumentError('Refusing to delete a file outside Studio storage.');
    }

    final file = File(normalizedFile);
    if (await file.exists()) await file.delete();
  }
}
