import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/studio_media_file.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_media_library_service.dart';

/// Copies a user-selected source file into Studio-managed storage and
/// registers its metadata in the independent Studio database.
class StudioMediaImportService {
  StudioMediaImportService({
    required StudioStorageManager storageManager,
    required StudioMediaLibraryService mediaLibrary,
  })  : _storageManager = storageManager,
        _mediaLibrary = mediaLibrary;

  final StudioStorageManager _storageManager;
  final StudioMediaLibraryService _mediaLibrary;
  final Random _random = Random.secure();

  String _newMediaId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final entropy = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'media_${timestamp}_$entropy';
  }

  Future<StudioMediaFile> importFile({
    required String sourcePath,
    required StudioMediaType mediaType,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Selected media file does not exist.', sourcePath);
    }

    final sourceSize = await source.length();
    if (sourceSize <= 0) {
      throw FileSystemException('Empty media files cannot be imported.', sourcePath);
    }

    final id = _newMediaId();
    final extension = p.extension(sourcePath).toLowerCase();
    final destination = await _storageManager.allocateMediaFile(
      id: id,
      extension: extension.isEmpty ? '.bin' : extension,
      isVideo: mediaType == StudioMediaType.video,
    );

    try {
      final copied = await source.copy(destination.path);
      final checksum = await sha256.bind(copied.openRead()).first;
      final now = DateTime.now().toUtc();
      final mediaFile = StudioMediaFile(
        id: id,
        mediaType: mediaType,
        originalName: p.basename(sourcePath),
        storagePath: copied.path,
        mimeType: _mimeType(extension, mediaType),
        fileExtension: extension.isEmpty ? null : extension.replaceFirst('.', ''),
        fileSizeBytes: await copied.length(),
        checksumSha256: checksum.toString(),
        importStatus: StudioMediaImportStatus.imported,
        createdAt: now,
        updatedAt: now,
      );

      await _mediaLibrary.register(mediaFile);
      return mediaFile;
    } catch (_) {
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }

  String? _mimeType(String extension, StudioMediaType type) {
    final normalized = extension.replaceFirst('.', '');
    const audioTypes = {
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'flac': 'audio/flac',
      'ogg': 'audio/ogg',
    };
    const videoTypes = {
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'avi': 'video/x-msvideo',
    };

    return type == StudioMediaType.audio
        ? audioTypes[normalized]
        : videoTypes[normalized];
  }
}
