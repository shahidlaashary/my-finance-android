class StudioAiVoiceProfile {
  const StudioAiVoiceProfile({
    required this.id,
    required this.displayName,
    required this.ownerName,
    required this.samplePath,
    required this.consentGranted,
    required this.consentScope,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String displayName;
  final String ownerName;
  final String samplePath;
  final bool consentGranted;
  final String consentScope;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory StudioAiVoiceProfile.fromMap(Map<String, Object?> map) {
    return StudioAiVoiceProfile(
      id: map['id'] as String,
      displayName: map['display_name'] as String,
      ownerName: map['owner_name'] as String,
      samplePath: map['sample_path'] as String,
      consentGranted: (map['consent_granted'] as int) == 1,
      consentScope: map['consent_scope'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
