
/// Attachment file aur us ke owner se mutaliq database record represent karta hai.
class AttachmentModel {
  final int? id;
  final String ownerType;
  final int ownerId;
  final String filePath;
  final String fileName;
  final String fileType;
  final int fileSize;
  final DateTime createdAt;

  const AttachmentModel({
    this.id,
    required this.ownerType,
    required this.ownerId,
    required this.filePath,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.createdAt,
  });

  /// Model ko database columns ke mutabiq map mein convert karta hai.
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
    };
  }

  /// Database row se attachment model tayyar karta hai.
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
    );
  }

  /// Maujooda model ki selected values badal kar naya model deta hai.
  AttachmentModel copyWith({
    int? id,
    String? filePath,
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
    );
  }
}
