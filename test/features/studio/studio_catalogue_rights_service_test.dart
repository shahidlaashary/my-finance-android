import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_catalogue_rights_service.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late StudioCatalogueRightsService rights;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    rights = StudioCatalogueRightsService(databaseProvider: () async => database);
    await rights.addHolder(name: 'Rights Holder A', type: 'person');
    await rights.addHolder(name: 'Rights Holder B', type: 'person');
  });

  tearDown(() async => database.close());

  Future<List<Map<String, Object?>>> holders() => rights.holders();

  test('rejects overlapping ownership shares above 100 percent', () async {
    final ids = await holders();
    await rights.addOwnership(
      holderId: ids[0]['id']! as String,
      assetType: 'track',
      assetId: 'track-1',
      share: 60,
      territory: 'Worldwide',
    );

    await expectLater(
      rights.addOwnership(
        holderId: ids[1]['id']! as String,
        assetType: 'track',
        assetId: 'track-1',
        share: 50,
        territory: 'Worldwide',
      ),
      throwsA(isA<StateError>()),
    );
    expect((await rights.ownerships()).length, 1);
  });

  test('allows shares in non-overlapping territories and date periods', () async {
    final ids = await holders();
    await rights.addOwnership(
      holderId: ids[0]['id']! as String,
      assetType: 'track',
      assetId: 'track-2',
      share: 70,
      territory: 'United States',
      startDate: '2024-01-01',
      endDate: '2024-06-30',
    );
    await rights.addOwnership(
      holderId: ids[1]['id']! as String,
      assetType: 'track',
      assetId: 'track-2',
      share: 70,
      territory: 'United States',
      startDate: '2024-07-01',
      endDate: '2024-12-31',
    );
    await rights.addOwnership(
      holderId: ids[1]['id']! as String,
      assetType: 'track',
      assetId: 'track-2',
      share: 70,
      territory: 'Canada',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    );
    expect((await rights.ownerships()).length, 3);
  });

  test('rejects overlapping active exclusive licenses', () async {
    await rights.addLicense(
      assetType: 'track',
      assetId: 'track-license-1',
      licensor: 'Owner A',
      licensee: 'Platform A',
      usage: 'streaming',
      territory: 'Worldwide',
      startDate: '2025-01-01',
      endDate: '2025-12-31',
      exclusive: true,
    );

    await expectLater(
      rights.addLicense(
        assetType: 'track',
        assetId: 'track-license-1',
        licensor: 'Owner A',
        licensee: 'Platform B',
        usage: 'streaming',
        territory: 'United States',
        startDate: '2025-06-01',
        endDate: '2026-01-01',
        exclusive: true,
      ),
      throwsA(isA<StateError>()),
    );
    expect((await rights.licenses()).length, 1);
  });

  test('allows non-overlapping exclusive license periods', () async {
    await rights.addLicense(
      assetType: 'track',
      assetId: 'track-license-2',
      licensor: 'Owner A',
      licensee: 'Platform A',
      usage: 'streaming',
      territory: 'United States',
      startDate: '2025-01-01',
      endDate: '2025-06-30',
      exclusive: true,
    );
    await rights.addLicense(
      assetType: 'track',
      assetId: 'track-license-2',
      licensor: 'Owner A',
      licensee: 'Platform B',
      usage: 'streaming',
      territory: 'United States',
      startDate: '2025-07-01',
      endDate: '2025-12-31',
      exclusive: true,
    );
    expect((await rights.licenses()).length, 2);
  });

  test('rejects invalid license date ranges', () async {
    await expectLater(
      rights.addLicense(
        assetType: 'track',
        assetId: 'track-license-3',
        licensor: 'Owner A',
        licensee: 'Platform A',
        usage: 'streaming',
        territory: 'Worldwide',
        startDate: '2025-12-31',
        endDate: '2025-01-01',
        exclusive: true,
      ),
      throwsArgumentError,
    );
  });

  test('rejects invalid ownership date ranges', () async {
    final ids = await holders();
    await expectLater(
      rights.addOwnership(
        holderId: ids[0]['id']! as String,
        assetType: 'track',
        assetId: 'track-3',
        share: 20,
        territory: 'Worldwide',
        startDate: '2025-12-31',
        endDate: '2025-01-01',
      ),
      throwsArgumentError,
    );
  });

  test('normalizes claim type and priority before saving', () async {
    final id = await rights.createClaim(
      claimType: ' COPYRIGHT ',
      assetType: 'track',
      assetId: 'track-normalized',
      claimantName: 'Claimant',
      title: 'Copyright claim',
      description: 'Description',
      priority: ' HIGH ',
    );
    final saved = await rights.claim(id);
    expect(saved!['claim_type'], 'copyright');
    expect(saved['priority'], 'high');
  });

  test('rejects counterclaims against a different asset', () async {
    final parentId = await rights.createClaim(
      claimType: 'copyright',
      assetType: 'track',
      assetId: 'track-parent',
      claimantName: 'Claimant A',
      title: 'Original claim',
      description: 'Description',
    );
    await expectLater(
      rights.createClaim(
        claimType: 'ownership',
        assetType: 'track',
        assetId: 'track-other',
        claimantName: 'Claimant B',
        title: 'Counterclaim',
        description: 'Description',
        parentClaimId: parentId,
      ),
      throwsArgumentError,
    );
  });

  test('rejects evidence with malformed checksum or checksum without file', () async {
    final claimId = await rights.createClaim(
      claimType: 'copyright',
      assetType: 'track',
      assetId: 'track-evidence',
      claimantName: 'Claimant',
      title: 'Evidence claim',
      description: 'Description',
    );
    await expectLater(
      rights.addClaimEvidence(
        claimId: claimId,
        evidenceType: 'document',
        title: 'Bad checksum',
        filePath: '/tmp/evidence.pdf',
        checksumSha256: 'not-a-sha256',
      ),
      throwsArgumentError,
    );
    await expectLater(
      rights.addClaimEvidence(
        claimId: claimId,
        evidenceType: 'document',
        title: 'Checksum without file',
        checksumSha256: List.filled(64, 'a').join(),
      ),
      throwsArgumentError,
    );
    expect(await rights.claimEvidence(claimId), isEmpty);
  });

  test('removes evidence record and records removal event atomically', () async {
    final claimId = await rights.createClaim(
      claimType: 'copyright',
      assetType: 'track',
      assetId: 'track-evidence-remove',
      claimantName: 'Claimant',
      title: 'Evidence removal claim',
      description: 'Description',
    );
    await rights.addClaimEvidence(
      claimId: claimId,
      evidenceType: 'document',
      title: 'Signed agreement',
      filePath: '/managed/evidence/agreement.pdf',
    );
    final evidence = await rights.claimEvidence(claimId);
    final evidenceId = evidence.single['id']! as String;

    await rights.removeClaimEvidence(evidenceId);

    expect(await rights.claimEvidence(claimId), isEmpty);
    final events = await rights.claimEvents(claimId);
    expect(events.any((event) => event['event_type'] == 'evidence_removed'), isTrue);
  });

  test('does not create a removal event when evidence record is missing', () async {
    final claimId = await rights.createClaim(
      claimType: 'copyright',
      assetType: 'track',
      assetId: 'track-missing-evidence',
      claimantName: 'Claimant',
      title: 'Missing evidence claim',
      description: 'Description',
    );

    await expectLater(
      rights.removeClaimEvidence('missing-evidence-id'),
      throwsArgumentError,
    );

    final events = await rights.claimEvents(claimId);
    expect(events.any((event) => event['event_type'] == 'evidence_removed'), isFalse);
  });

  test('requires a decision note when rejecting a claim', () async {
    final claimId = await rights.createClaim(
      claimType: 'copyright',
      assetType: 'track',
      assetId: 'track-reject',
      claimantName: 'Claimant',
      title: 'Claim to reject',
      description: 'Description',
    );
    await rights.transitionClaim(claimId: claimId, status: 'submitted');
    await rights.transitionClaim(claimId: claimId, status: 'under_review');
    await expectLater(
      rights.transitionClaim(claimId: claimId, status: 'rejected'),
      throwsArgumentError,
    );
    final saved = await rights.claim(claimId);
    expect(saved!['status'], 'under_review');
  });

}
