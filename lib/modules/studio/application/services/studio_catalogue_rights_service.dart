import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../../infrastructure/database/studio_database_manager.dart';

/// Application service for Studio Catalogue and Rights persistent records.
class StudioCatalogueRightsService {
  Future<Database> get _db => StudioDatabaseManager.instance.initialize();
  String _id(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(99999)}';
  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<List<Map<String,Object?>>> tracks() async => (await _db).query('studio_tracks', orderBy:'title COLLATE NOCASE');
  Future<void> addTrack(String title) async {
    final db=await _db; final now=_now();
    await db.insert('studio_tracks',{'id':_id('track'),'title':title.trim(),'created_at':now,'updated_at':now});
  }
  Future<List<Map<String,Object?>>> holders() async => (await _db).query('studio_rights_holders',orderBy:'name COLLATE NOCASE');
  Future<void> addHolder({required String name,required String type,String? contact,String? notes}) async {
    final now=_now(); await (await _db).insert('studio_rights_holders',{'id':_id('holder'),'name':name.trim(),'holder_type':type,'contact':contact,'notes':notes,'created_at':now,'updated_at':now});
  }
  Future<List<Map<String,Object?>>> ownerships() async => (await _db).rawQuery('SELECT o.*, h.name holder_name FROM studio_ownership_records o JOIN studio_rights_holders h ON h.id=o.holder_id ORDER BY o.created_at DESC');
  Future<void> addOwnership({required String holderId,required String assetType,required String assetId,required double share,required String territory,String? notes}) async {
    if(share<=0||share>100) throw ArgumentError('Share must be greater than 0 and at most 100.');
    await (await _db).insert('studio_ownership_records',{'id':_id('own'),'holder_id':holderId,'asset_type':assetType,'asset_id':assetId,'share_percent':share,'territory':territory,'notes':notes,'created_at':_now()});
  }
  Future<List<Map<String,Object?>>> licenses() async => (await _db).query('studio_licenses',orderBy:'created_at DESC');
  Future<void> addLicense({required String assetType,required String assetId,required String licensor,required String licensee,required String usage,required String territory,String? startDate,String? endDate,bool exclusive=false,String? notes}) async {
    final now=_now(); await (await _db).insert('studio_licenses',{'id':_id('lic'),'asset_type':assetType,'asset_id':assetId,'licensor':licensor.trim(),'licensee':licensee.trim(),'usage_type':usage.trim(),'territory':territory,'start_date':startDate,'end_date':endDate,'exclusive':exclusive?1:0,'status':'active','notes':notes,'created_at':now,'updated_at':now});
  }
  Future<void> saveComparison({required String leftId,required String rightId,required double score,required int matches,required int offsetMs,required String algorithm,required String version,Map<String,Object?>? result}) async {
    await (await _db).insert('studio_comparison_history',{'id':_id('cmp'),'left_media_id':leftId,'right_media_id':rightId,'match_score':score,'matched_landmarks':matches,'offset_ms':offsetMs,'algorithm_key':algorithm,'algorithm_version':version,'result_json':result==null?null:jsonEncode(result),'created_at':_now()});
  }
  Future<List<Map<String,Object?>>> comparisonHistory() async => (await _db).rawQuery('SELECT c.*, l.original_name left_name, r.original_name right_name FROM studio_comparison_history c JOIN studio_media_files l ON l.id=c.left_media_id JOIN studio_media_files r ON r.id=c.right_media_id ORDER BY c.created_at DESC LIMIT 100');
}
