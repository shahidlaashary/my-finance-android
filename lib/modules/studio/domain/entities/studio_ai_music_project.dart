class StudioAiMusicProject {
  const StudioAiMusicProject({
    required this.id,
    required this.title,
    required this.prompt,
    required this.lyrics,
    required this.genre,
    required this.language,
    required this.mood,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.voiceProfileId,
  });

  final String id;
  final String title;
  final String prompt;
  final String lyrics;
  final String genre;
  final String language;
  final String mood;
  final String status;
  final String? voiceProfileId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory StudioAiMusicProject.fromMap(Map<String, Object?> map) {
    return StudioAiMusicProject(
      id: map['id'] as String,
      title: map['title'] as String,
      prompt: map['prompt'] as String,
      lyrics: map['lyrics'] as String,
      genre: map['genre'] as String,
      language: map['language'] as String,
      mood: map['mood'] as String,
      status: map['status'] as String,
      voiceProfileId: map['voice_profile_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
