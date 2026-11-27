import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_ai_music_service.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late StudioAiMusicService service;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    service = StudioAiMusicService(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('creates and lists a song draft without claiming audio was generated', () async {
    final project = await service.createProject(
      title: 'Test song',
      prompt: 'Soft Urdu acoustic ballad',
      lyrics: 'A short original lyric',
      genre: 'Acoustic',
      language: 'Urdu',
      mood: 'Peaceful',
    );

    expect(project.status, 'draft');
    expect((await service.listProjects()).single.title, 'Test song');
  });

  test('requires a valid consented voice profile before assigning it', () async {
    final profile = await service.addVoiceProfile(
      displayName: 'My voice',
      ownerName: 'Voice owner',
      samplePath: '/studio/audio/voice.wav',
      consentScope: 'Authorized AI singing generation',
    );

    final project = await service.createProject(
      title: 'Voice test',
      prompt: 'A melody',
      lyrics: '',
      genre: 'Pop',
      language: 'English',
      mood: 'Happy',
      voiceProfileId: profile.id,
    );
    expect(project.voiceProfileId, profile.id);

    await service.revokeVoiceConsent(profile.id);
    expect(await service.listVoiceProfiles(), isEmpty);
    final stored = await database.query(
      'studio_ai_music_projects',
      columns: ['voice_profile_id'],
      where: 'id = ?',
      whereArgs: [project.id],
    );
    expect(stored.single['voice_profile_id'], isNull);
  });

  test('rejects a voice profile without an explicit permission scope', () async {
    await expectLater(
      service.addVoiceProfile(
        displayName: 'Unapproved',
        ownerName: 'Owner',
        samplePath: '/studio/audio/sample.wav',
        consentScope: ' ',
      ),
      throwsArgumentError,
    );
  });
}
