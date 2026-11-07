
class AttachmentModel {
  final int? id;
  final String ownerType;
  final int ownerId;
  final String filePath;
  final String fileName;
  final String fileType;
  final int fileSize;
  final DateTime createdAt;
  final String? remoteUrl;
  final bool isSynced;

  const AttachmentModel({
    this.id,
    required this.ownerType,
    required this.ownerId,
    required this.filePath,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.createdAt,
    this.remoteUrl,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_type': ownerType,
      'owner_id': ownerId,
      'file_path': filePath,
      'file_name': fileName,
      'file_type': fileType,
      'file_size': fileSize,
      'created_at': createdAt.toIso8601String(),
      'remote_url': remoteUrl,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory AttachmentModel.fromMap(Map<String, dynamic> map) {
    return AttachmentModel(
      id: map['id'] as int?,
      ownerType: map['owner_type'] as String,
      ownerId: map['owner_id'] as int,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String,
      fileType: map['file_type'] as String,
      fileSize: map['file_size'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      remoteUrl: map['remote_url'] as String?,
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
    );
  }

  AttachmentModel copyWith({
    int? id,
    String? filePath,
    String? remoteUrl,
    bool? isSynced,
  }) {
    return AttachmentModel(
      id: id ?? this.id,
      ownerType: ownerType,
      ownerId: ownerId,
      filePath: filePath ?? this.filePath,
      fileName: fileName,
      fileType: fileType,
      fileSize: fileSize,
      createdAt: createdAt,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
