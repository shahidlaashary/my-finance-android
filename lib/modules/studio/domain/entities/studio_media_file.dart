enum StudioMediaType {
  audio,
  video;

  static StudioMediaType fromDatabase(String value) {
    return StudioMediaType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => throw FormatException('Unsupported Studio media type: $value'),
    );
  }
}

enum StudioMediaImportStatus {
  pending,
  imported,
  missing,
  failed;

  static StudioMediaImportStatus fromDatabase(String value) {
    return StudioMediaImportStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw FormatException('Unsupported Studio import status: $value'),
    );
  }
}

/// Domain representation of a media asset registered in Studio.
///
/// The actual media bytes stay in managed file storage. SQLite stores only
/// metadata and the path to the managed file.
class StudioMediaFile {
  const StudioMediaFile({
    required this.id,
    required this.mediaType,
    required this.originalName,
    required this.storagePath,
    required this.fileSizeBytes,
    required this.importStatus,
    required this.createdAt,
    required this.updatedAt,
    this.mimeType,
    this.fileExtension,
    this.durationMs,
    this.checksumSha256,
  });

  final String id;
  final StudioMediaType mediaType;
  final String originalName;
  final String storagePath;
  final String? mimeType;
  final String? fileExtension;
  final int fileSizeBytes;
  final int? durationMs;
  final String? checksumSha256;
  final StudioMediaImportStatus importStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory StudioMediaFile.fromMap(Map<String, Object?> map) {
    return StudioMediaFile(
      id: map['id'] as String,
      mediaType: StudioMediaType.fromDatabase(map['media_type'] as String),
      originalName: map['original_name'] as String,
      storagePath: map['storage_path'] as String,
      mimeType: map['mime_type'] as String?,
      fileExtension: map['file_extension'] as String?,
      fileSizeBytes: map['file_size_bytes'] as int,
      durationMs: map['duration_ms'] as int?,
      checksumSha256: map['checksum_sha256'] as String?,
      importStatus: StudioMediaImportStatus.fromDatabase(
        map['import_status'] as String,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'media_type': mediaType.name,
      'original_name': originalName,
      'storage_path': storagePath,
      'mime_type': mimeType,
      'file_extension': fileExtension,
      'file_size_bytes': fileSizeBytes,
      'duration_ms': durationMs,
      'checksum_sha256': checksumSha256,
      'import_status': importStatus.name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
