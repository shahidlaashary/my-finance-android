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
}
