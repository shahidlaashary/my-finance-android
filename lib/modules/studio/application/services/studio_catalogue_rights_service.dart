import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../../infrastructure/database/studio_database_manager.dart';

/// Application service for Studio Catalogue and Rights persistent records.
class StudioCatalogueRightsService {
  StudioCatalogueRightsService({Future<Database> Function()? databaseProvider})
      : _databaseProvider = databaseProvider ??
            StudioDatabaseManager.instance.initialize;

  final Future<Database> Function() _databaseProvider;
  Future<Database> get _db => _databaseProvider();
  String _id(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(99999)}';
  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<List<Map<String,Object?>>> tracks() async => (await _db).query('studio_tracks', orderBy:'title COLLATE NOCASE');
  Future<List<Map<String,Object?>>> artists() async => (await _db).query('studio_artists', orderBy:'display_name COLLATE NOCASE');
  Future<List<Map<String,Object?>>> releases() async => (await _db).query('studio_releases', orderBy:'title COLLATE NOCASE');
  Future<void> addArtist(String displayName,{String? legalName,String? notes}) async { final now=_now(); await (await _db).insert('studio_artists',{'id':_id('artist'),'display_name':displayName.trim(),'legal_name':legalName,'notes':notes,'created_at':now,'updated_at':now}); }
  Future<void> addRelease(String title,{required String releaseType,String? releaseDate,String? notes}) async { final now=_now(); await (await _db).insert('studio_releases',{'id':_id('release'),'title':title.trim(),'release_type':releaseType,'release_date':releaseDate,'notes':notes,'created_at':now,'updated_at':now}); }
  Future<void> addTrack(String title) async {
    final db=await _db; final now=_now();
    await db.insert('studio_tracks',{'id':_id('track'),'title':title.trim(),'created_at':now,'updated_at':now});
  }
  Future<List<Map<String,Object?>>> holders() async => (await _db).query('studio_rights_holders',orderBy:'name COLLATE NOCASE');
  Future<void> addHolder({required String name,required String type,String? contact,String? notes}) async {
    final now=_now(); await (await _db).insert('studio_rights_holders',{'id':_id('holder'),'name':name.trim(),'holder_type':type,'contact':contact,'notes':notes,'created_at':now,'updated_at':now});
  }
  Future<List<Map<String,Object?>>> ownerships() async => (await _db).rawQuery('SELECT o.*, h.name holder_name FROM studio_ownership_records o JOIN studio_rights_holders h ON h.id=o.holder_id ORDER BY o.created_at DESC');
  DateTime? _ownershipDate(String? value, String field) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) throw ArgumentError('Invalid ownership $field.');
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  bool _territoriesOverlap(String first, String second) {
    final a = first.trim().toLowerCase();
    final b = second.trim().toLowerCase();
    return a == b || a == 'worldwide' || b == 'worldwide';
  }

  bool _dateRangesOverlap(DateTime? aStart, DateTime? aEnd,
      DateTime? bStart, DateTime? bEnd) {
    return (aEnd == null || bStart == null || !aEnd.isBefore(bStart)) &&
        (bEnd == null || aStart == null || !bEnd.isBefore(aStart));
  }

  Future<void> addOwnership({
    required String holderId,
    required String assetType,
    required String assetId,
    required double share,
    required String territory,
    String? startDate,
    String? endDate,
    String? notes,
  }) async {
    if (!share.isFinite || share <= 0 || share > 100) {
      throw ArgumentError('Share must be greater than 0 and at most 100.');
    }
    if (assetType.trim().isEmpty || assetId.trim().isEmpty ||
        territory.trim().isEmpty) {
      throw ArgumentError('Asset type, asset ID and territory are required.');
    }
    final start = _ownershipDate(startDate, 'start date');
    final end = _ownershipDate(endDate, 'end date');
    if (start != null && end != null && end.isBefore(start)) {
      throw ArgumentError('Ownership end date cannot be before its start date.');
    }

    final db = await _db;
    await db.transaction((txn) async {
      final holder = await txn.query('studio_rights_holders',
          columns: ['id'], where: 'id = ?', whereArgs: [holderId], limit: 1);
      if (holder.isEmpty) throw ArgumentError('Rights holder was not found.');

      final existing = await txn.query('studio_ownership_records',
          where: 'asset_type = ? AND asset_id = ?',
          whereArgs: [assetType.trim(), assetId.trim()]);
      final overlapping = <Map<String, Object?>>[];
      final boundaries = <DateTime>{};
      if (start != null) boundaries.add(start);
      if (end != null) boundaries.add(end);

      for (final record in existing) {
        final recordStart = _ownershipDate(record['start_date'] as String?, 'start date');
        final recordEnd = _ownershipDate(record['end_date'] as String?, 'end date');
        if (!_territoriesOverlap(territory, record['territory']?.toString() ?? 'Worldwide') ||
            !_dateRangesOverlap(start, end, recordStart, recordEnd)) {
          continue;
        }
        overlapping.add(record);
        if (recordStart != null) boundaries.add(recordStart);
        if (recordEnd != null) boundaries.add(recordEnd);
      }

      // Ownership shares may not exceed 100% at any point in an overlapping
      // territory. Checking every interval boundary catches staggered terms.
      if (boundaries.isEmpty) boundaries.add(DateTime.utc(2000));
      for (final point in boundaries) {
        if ((start == null || !point.isBefore(start)) &&
            (end == null || !point.isAfter(end))) {
          var total = share;
          for (final record in overlapping) {
            final recordStart =
                _ownershipDate(record['start_date'] as String?, 'start date');
            final recordEnd =
                _ownershipDate(record['end_date'] as String?, 'end date');
            if ((recordStart == null || !point.isBefore(recordStart)) &&
                (recordEnd == null || !point.isAfter(recordEnd))) {
              total += (record['share_percent'] as num).toDouble();
            }
          }
          if (total > 100.000001) {
            throw StateError(
              'Ownership shares would exceed 100% for this asset, territory and date range.',
            );
          }
        }
      }

      await txn.insert('studio_ownership_records', {
        'id': _id('own'),
        'holder_id': holderId,
        'asset_type': assetType.trim(),
        'asset_id': assetId.trim(),
        'share_percent': share,
        'territory': territory.trim(),
        'start_date': startDate,
        'end_date': endDate,
        'notes': notes,
        'created_at': _now(),
      });
    });
  }
  Future<List<Map<String,Object?>>> licenses() async => (await _db).query('studio_licenses',orderBy:'created_at DESC');
  Future<void> addLicense({required String assetType,required String assetId,required String licensor,required String licensee,required String usage,required String territory,String? startDate,String? endDate,bool exclusive=false,String? notes}) async {
    final now=_now(); await (await _db).insert('studio_licenses',{'id':_id('lic'),'asset_type':assetType,'asset_id':assetId,'licensor':licensor.trim(),'licensee':licensee.trim(),'usage_type':usage.trim(),'territory':territory,'start_date':startDate,'end_date':endDate,'exclusive':exclusive?1:0,'status':'active','notes':notes,'created_at':now,'updated_at':now});
  }
  Future<void> saveComparison({required String leftId,required String rightId,required double score,required int matches,required int offsetMs,required String algorithm,required String version,Map<String,Object?>? result}) async {
    await (await _db).insert('studio_comparison_history',{'id':_id('cmp'),'left_media_id':leftId,'right_media_id':rightId,'match_score':score,'matched_landmarks':matches,'offset_ms':offsetMs,'algorithm_key':algorithm,'algorithm_version':version,'result_json':result==null?null:jsonEncode(result),'created_at':_now()});
  }
  Future<List<Map<String,Object?>>> comparisonHistory() async => (await _db).rawQuery('SELECT c.*, l.original_name left_name, r.original_name right_name FROM studio_comparison_history c JOIN studio_media_files l ON l.id=c.left_media_id JOIN studio_media_files r ON r.id=c.right_media_id ORDER BY c.created_at DESC LIMIT 100');

  /// Returns claims with evidence counts, newest activity first.
  Future<List<Map<String,Object?>>> claims({String? status}) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT c.*, COUNT(e.id) AS evidence_count
      FROM studio_rights_claims c
      LEFT JOIN studio_claim_evidence e ON e.claim_id = c.id
      WHERE (? IS NULL OR c.status = ?)
      GROUP BY c.id
      ORDER BY c.updated_at DESC
    ''', [status, status]);
  }

  Future<Map<String,Object?>?> claim(String id) async {
    final rows = await (await _db).query(
      'studio_rights_claims', where: 'id = ?', whereArgs: [id], limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> createClaim({
    required String claimType,
    required String assetType,
    required String assetId,
    required String claimantName,
    String? respondentName,
    required String title,
    required String description,
    String priority = 'normal',
    String? parentClaimId,
  }) async {
    const types = {'ownership','copyright','license','content_match','other'};
    const priorities = {'low','normal','high','urgent'};
    if (!types.contains(claimType)) throw ArgumentError('Invalid claim type.');
    if (!priorities.contains(priority)) throw ArgumentError('Invalid priority.');
    if (assetType.trim().isEmpty || assetId.trim().isEmpty ||
        claimantName.trim().isEmpty || title.trim().isEmpty ||
        description.trim().isEmpty) {
      throw ArgumentError('Complete all required claim fields.');
    }
    final db = await _db;
    final now = _now();
    final id = _id('claim');
    await db.transaction((txn) async {
      if (parentClaimId != null) {
        final parent = await txn.query('studio_rights_claims',
            columns: ['id'], where: 'id = ?', whereArgs: [parentClaimId], limit: 1);
        if (parent.isEmpty) throw ArgumentError('Original claim was not found.');
      }
      await txn.insert('studio_rights_claims', {
        'id': id, 'claim_type': claimType, 'asset_type': assetType.trim(),
        'asset_id': assetId.trim(), 'claimant_name': claimantName.trim(),
        'respondent_name': respondentName?.trim(), 'title': title.trim(),
        'description': description.trim(), 'priority': priority,
        'parent_claim_id': parentClaimId, 'status': 'draft',
        'created_at': now, 'updated_at': now,
      });
      await txn.insert('studio_claim_events', {
        'claim_id': id, 'event_type': parentClaimId == null ? 'created' : 'counterclaim_created',
        'to_status': 'draft', 'note': 'Claim created as draft.', 'created_at': now,
      });
    });
    return id;
  }

  Future<void> addClaimEvidence({
    required String claimId,
    required String evidenceType,
    required String title,
    String? description,
    String? filePath,
    String? checksumSha256,
  }) async {
    if (title.trim().isEmpty || evidenceType.trim().isEmpty) {
      throw ArgumentError('Evidence type and title are required.');
    }
    final db = await _db;
    final now = _now();
    await db.transaction((txn) async {
      final rows = await txn.query('studio_rights_claims',
          columns: ['status'], where: 'id = ?', whereArgs: [claimId], limit: 1);
      if (rows.isEmpty) throw ArgumentError('Claim not found.');
      if (rows.first['status'] == 'resolved' || rows.first['status'] == 'rejected' ||
          rows.first['status'] == 'withdrawn') {
        throw StateError('Evidence cannot be added to a closed claim.');
      }
      await txn.insert('studio_claim_evidence', {
        'id': _id('evidence'), 'claim_id': claimId,
        'evidence_type': evidenceType.trim(), 'title': title.trim(),
        'description': description?.trim(), 'file_path': filePath,
        'checksum_sha256': checksumSha256, 'created_at': now,
      });
      await txn.insert('studio_claim_events', {
        'claim_id': claimId, 'event_type': 'evidence_added',
        'note': 'Evidence added: ${title.trim()}', 'created_at': now,
      });
      await txn.update('studio_rights_claims', {'updated_at': now},
          where: 'id = ?', whereArgs: [claimId]);
    });
  }

  Future<List<Map<String,Object?>>> claimEvidence(String claimId) async =>
      (await _db).query('studio_claim_evidence',
          where: 'claim_id = ?', whereArgs: [claimId], orderBy: 'created_at DESC');

  Future<List<Map<String,Object?>>> claimEvents(String claimId) async =>
      (await _db).query('studio_claim_events',
          where: 'claim_id = ?', whereArgs: [claimId], orderBy: 'created_at DESC');

  Future<void> removeClaimEvidence(String evidenceId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'studio_claim_evidence',
        columns: ['claim_id'],
        where: 'id = ?',
        whereArgs: [evidenceId],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Evidence record not found.');
      final claimId = rows.first['claim_id'].toString();
      await txn.delete('studio_claim_evidence',
          where: 'id = ?', whereArgs: [evidenceId]);
      await txn.insert('studio_claim_events', {
        'claim_id': claimId,
        'event_type': 'evidence_removed',
        'note': 'Evidence attachment/record removed.',
        'created_at': _now(),
      });
      await txn.update('studio_rights_claims', {'updated_at': _now()},
          where: 'id = ?', whereArgs: [claimId]);
    });
  }

  Future<void> transitionClaim({
    required String claimId,
    required String status,
    String? note,
    String? resolution,
    DateTime? dueAt,
  }) async {
    const allowed = {
      'draft': {'submitted','withdrawn'},
      'submitted': {'under_review','withdrawn'},
      'under_review': {'resolved','rejected','withdrawn'},
      'resolved': <String>{}, 'rejected': <String>{}, 'withdrawn': <String>{},
    };
    if (!allowed.containsKey(status)) throw ArgumentError('Invalid claim status.');
    final db = await _db;
    final now = _now();
    await db.transaction((txn) async {
      final rows = await txn.query('studio_rights_claims',
          where: 'id = ?', whereArgs: [claimId], limit: 1);
      if (rows.isEmpty) throw ArgumentError('Claim not found.');
      final previous = rows.first['status'] as String;
      if (!allowed[previous]!.contains(status)) {
        throw StateError('Cannot move claim from $previous to $status.');
      }
      if (status == 'resolved' && (resolution == null || resolution.trim().isEmpty)) {
        throw ArgumentError('A resolution note is required.');
      }
      await txn.update('studio_rights_claims', {
        'status': status, 'updated_at': now,
        if (status == 'submitted') 'submitted_at': now,
        if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
        if (status == 'resolved' || status == 'rejected') 'resolved_at': now,
        if (resolution != null) 'resolution': resolution.trim(),
      }, where: 'id = ?', whereArgs: [claimId]);
      await txn.insert('studio_claim_events', {
        'claim_id': claimId, 'event_type': 'status_changed',
        'from_status': previous, 'to_status': status,
        'note': note?.trim() ?? resolution?.trim(), 'created_at': now,
      });
    });
  }
}
