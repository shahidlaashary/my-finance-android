import 'studio_media_file.dart';

enum StudioFingerprintStatus {
  pending,
  generated,
  indexed,
  failed,
  stale;

  static StudioFingerprintStatus fromDatabase(String value) {
    return StudioFingerprintStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw FormatException('Unsupported fingerprint status: $value'),
    );
  }
}

/// Metadata for a fingerprint artifact. Fingerprint bytes remain in managed
/// storage; SQLite stores their path, format and integrity metadata.
class StudioFingerprint {
  const StudioFingerprint({
    required this.id,
    required this.mediaFileId,
    required this.mediaType,
    required this.algorithmKey,
    required this.algorithmVersion,
    required this.fingerprintFormat,
    required this.dataFilePath,
    required this.frameCount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.checksumSha256,
    this.sampleRate,
    this.channels,
    this.durationMs,
  });

  final String id;
  final String mediaFileId;
  final StudioMediaType mediaType;
  final String algorithmKey;
  final String algorithmVersion;
  final String fingerprintFormat;
  final String dataFilePath;
  final String? checksumSha256;
  final int? sampleRate;
  final int? channels;
  final int? durationMs;
  final int frameCount;
  final StudioFingerprintStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory StudioFingerprint.fromMap(Map<String, Object?> map) {
    return StudioFingerprint(
      id: map['id'] as String,
      mediaFileId: map['media_file_id'] as String,
      mediaType: StudioMediaType.fromDatabase(map['media_type'] as String),
      algorithmKey: map['algorithm_key'] as String,
      algorithmVersion: map['algorithm_version'] as String,
      fingerprintFormat: map['fingerprint_format'] as String,
      dataFilePath: map['data_file_path'] as String,
      checksumSha256: map['checksum_sha256'] as String?,
      sampleRate: map['sample_rate'] as int?,
      channels: map['channels'] as int?,
      durationMs: map['duration_ms'] as int?,
      frameCount: map['frame_count'] as int,
      status: StudioFingerprintStatus.fromDatabase(map['status'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'media_file_id': mediaFileId,
        'media_type': mediaType.name,
        'algorithm_key': algorithmKey,
        'algorithm_version': algorithmVersion,
        'fingerprint_format': fingerprintFormat,
        'data_file_path': dataFilePath,
        'checksum_sha256': checksumSha256,
        'sample_rate': sampleRate,
        'channels': channels,
        'duration_ms': durationMs,
        'frame_count': frameCount,
        'status': status.name,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}

class StudioFingerprintSegment {
  const StudioFingerprintSegment({
    required this.fingerprintId,
    required this.segmentIndex,
    required this.startMs,
    required this.endMs,
    required this.dataOffsetBytes,
    required this.dataLengthBytes,
    this.signatureHash,
  });

  final String fingerprintId;
  final int segmentIndex;
  final int startMs;
  final int endMs;
  final int dataOffsetBytes;
  final int dataLengthBytes;
  final String? signatureHash;

  factory StudioFingerprintSegment.fromMap(Map<String, Object?> map) {
    return StudioFingerprintSegment(
      fingerprintId: map['fingerprint_id'] as String,
      segmentIndex: map['segment_index'] as int,
      startMs: map['start_ms'] as int,
      endMs: map['end_ms'] as int,
      dataOffsetBytes: map['data_offset_bytes'] as int,
      dataLengthBytes: map['data_length_bytes'] as int,
      signatureHash: map['signature_hash'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
        'fingerprint_id': fingerprintId,
        'segment_index': segmentIndex,
        'start_ms': startMs,
        'end_ms': endMs,
        'data_offset_bytes': dataOffsetBytes,
        'data_length_bytes': dataLengthBytes,
        'signature_hash': signatureHash,
      };
}
