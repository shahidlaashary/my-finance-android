import 'dart:io';
import '../../domain/entities/studio_media_file.dart';
import '../../application/services/studio_media_library_service.dart';
import '../../application/services/studio_fingerprint_catalogue_service.dart';
import '../../application/services/studio_catalogue_rights_service.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import '../../engines/video_fingerprint/studio_video_fingerprint_engine.dart';
import '../../domain/entities/studio_video_fingerprint_match.dart';

class StudioVideoIdentificationService{
  static const algorithmKey = StudioVideoFingerprintEngine.key;
  static const algorithmVersion = StudioVideoFingerprintEngine.version;
  StudioVideoIdentificationService({StudioMediaLibraryService? mediaLibrary,StudioFingerprintCatalogueService? catalogue,StudioStorageManager? storage})
    :mediaLibrary=mediaLibrary??StudioMediaLibraryService(),catalogue=catalogue??StudioFingerprintCatalogueService(),storage=storage??StudioStorageManager();
  final StudioMediaLibraryService mediaLibrary;final StudioFingerprintCatalogueService catalogue;final StudioStorageManager storage;
  StudioVideoFingerprintEngine get engine=>StudioVideoFingerprintEngine(storage:storage,media:mediaLibrary,catalogue:catalogue);
  Future<List<StudioMediaFile>> videos()=>mediaLibrary.browse(mediaType:StudioMediaType.video,limit:500);
  Future<void> fingerprint(String id)=>engine.generate(id).then((_) {});
  Future<StudioVideoFingerprintMatch> compare(String first,String second)async{
    final result=await engine.compare(first,second);
    await StudioCatalogueRightsService().saveComparison(leftId:first,rightId:second,score:result.confidence,matches:result.matches,offsetMs:result.offsetMs,algorithm:StudioVideoFingerprintEngine.key,version:StudioVideoFingerprintEngine.version,result:{'queryFrames':result.queryFrames,'referenceFrames':result.referenceFrames});
    return result;
  }
  Future<List<Map<String,Object?>>> history()=>StudioCatalogueRightsService().comparisonHistory();
}
