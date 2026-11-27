import 'package:sqflite/sqflite.dart';

import '../domain/entities/studio_ai_music_project.dart';
import '../domain/entities/studio_ai_voice_profile.dart';
import '../infrastructure/database/studio_database_manager.dart';

/// Local application boundary for AI music projects and consented voice samples.
///
/// Song generation is intentionally delegated to a provider adapter. This
/// service never pretends a draft is a generated song.
class StudioAiMusicService {
  StudioAiMusicService({Database? database}) : _providedDatabase = database;

  final Database? _providedDatabase;

  Future<Database> get _database async =>
      _providedDatabase ?? StudioDatabaseManager.instance.initialize();

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  Future<StudioAiMusicProject> createProject({
    required String title,
    required String prompt,
    required String lyrics,
    required String genre,
    required String language,
    required String mood,
    String? voiceProfileId,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError('A song project title is required.');
    }
    if (prompt.trim().isEmpty && lyrics.trim().isEmpty) {
      throw ArgumentError('Add a description or lyrics before saving the project.');
    }

    final db = await _database;
    if (voiceProfileId != null) {
      final profiles = await db.query(
        'studio_ai_voice_profiles',
        columns: ['id'],
        where: 'id = ? AND consent_granted = 1',
        whereArgs: [voiceProfileId],
        limit: 1,
      );
      if (profiles.isEmpty) {
        throw StateError('The selected voice profile is missing or not authorized.');
      }
    }

    final now = DateTime.now().toUtc();
    final project = StudioAiMusicProject(
      id: _newId('music'),
      title: normalizedTitle,
      prompt: prompt.trim(),
      lyrics: lyrics.trim(),
      genre: genre,
      language: language,
      mood: mood,
      status: 'draft',
      voiceProfileId: voiceProfileId,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('studio_ai_music_projects', {
      'id': project.id,
      'title': project.title,
      'prompt': project.prompt,
      'lyrics': project.lyrics,
      'genre': project.genre,
      'language': project.language,
      'mood': project.mood,
      'voice_profile_id': project.voiceProfileId,
      'status': project.status,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await _log(db, 'music_project_created', 'music_project', project.id,
        'Created AI music draft: ${project.title}');
    return project;
  }

  Future<List<StudioAiMusicProject>> listProjects() async {
    final rows = await (await _database).query(
      'studio_ai_music_projects',
      orderBy: 'updated_at DESC',
      limit: 200,
    );
    return rows.map(StudioAiMusicProject.fromMap).toList(growable: false);
  }

  Future<StudioAiVoiceProfile> addVoiceProfile({
    required String displayName,
    required String ownerName,
    required String samplePath,
    required String consentScope,
  }) async {
    if (displayName.trim().isEmpty || ownerName.trim().isEmpty) {
      throw ArgumentError('Voice profile and voice owner names are required.');
    }
    if (samplePath.trim().isEmpty) {
      throw ArgumentError('A voice sample file is required.');
    }
    if (consentScope.trim().isEmpty) {
      throw ArgumentError('The consent scope must be recorded.');
    }

    final db = await _database;
    final now = DateTime.now().toUtc();
    final profile = StudioAiVoiceProfile(
      id: _newId('voice'),
      displayName: displayName.trim(),
      ownerName: ownerName.trim(),
      samplePath: samplePath,
      consentGranted: true,
      consentScope: consentScope.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('studio_ai_voice_profiles', {
      'id': profile.id,
      'display_name': profile.displayName,
      'owner_name': profile.ownerName,
      'sample_path': profile.samplePath,
      'consent_granted': 1,
      'consent_scope': profile.consentScope,
      'consent_recorded_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await _log(db, 'voice_consent_recorded', 'voice_profile', profile.id,
        'Recorded voice-use consent for ${profile.ownerName}');
    return profile;
  }

  Future<List<StudioAiVoiceProfile>> listVoiceProfiles() async {
    final rows = await (await _database).query(
      'studio_ai_voice_profiles',
      where: 'consent_granted = 1',
      orderBy: 'created_at DESC',
      limit: 100,
    );
    return rows.map(StudioAiVoiceProfile.fromMap).toList(growable: false);
  }

  Future<void> revokeVoiceConsent(String profileId) async {
    final db = await _database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'studio_ai_voice_profiles',
      {'consent_granted': 0, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [profileId],
    );
    await db.update(
      'studio_ai_music_projects',
      {'voice_profile_id': null, 'updated_at': now},
      where: 'voice_profile_id = ?',
      whereArgs: [profileId],
    );
    await _log(db, 'voice_consent_revoked', 'voice_profile', profileId,
        'Revoked voice-use consent and detached the profile from drafts');
  }

  Future<void> _log(
    Database db,
    String eventType,
    String entityType,
    String entityId,
    String description,
  ) async {
    await db.insert('studio_activity_logs', {
      'event_type': eventType,
      'entity_type': entityType,
      'entity_id': entityId,
      'description': description,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
