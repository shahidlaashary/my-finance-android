import 'package:sqflite/sqflite.dart';
import '../../infrastructure/database/studio_database_manager.dart';

class StudioReportSummary{
  const StudioReportSummary({required this.media,required this.audio,required this.video,required this.fingerprints,required this.tracks,required this.artists,required this.releases,required this.holders,required this.ownerships,required this.licenses,required this.comparisons,required this.pendingJobs,required this.failedJobs});
  final int media,audio,video,fingerprints,tracks,artists,releases,holders,ownerships,licenses,comparisons,pendingJobs,failedJobs;
}
class StudioReportsService{
  Future<StudioReportSummary> load()async{
    final db=await StudioDatabaseManager.instance.initialize();
    Future<int> count(String table)=>_count(db,table);
    final counts=await Future.wait([
      count('studio_media_files'),count('studio_media_files_audio'),count('studio_media_files_video'),
      count('studio_fingerprints'),count('studio_tracks'),count('studio_artists'),count('studio_releases'),
      count('studio_rights_holders'),count('studio_ownership_records'),count('studio_licenses'),count('studio_comparison_history'),
      count('studio_jobs_pending'),count('studio_jobs_failed'),
    ]);
    final audio=await db.rawQuery("SELECT COUNT(*) AS c FROM studio_media_files WHERE media_type='audio'");
    final video=await db.rawQuery("SELECT COUNT(*) AS c FROM studio_media_files WHERE media_type='video'");
    final pending=await db.rawQuery("SELECT COUNT(*) AS c FROM studio_processing_jobs WHERE status IN ('pending','queued','running')");
    final failed=await db.rawQuery("SELECT COUNT(*) AS c FROM studio_processing_jobs WHERE status='failed'");
    return StudioReportSummary(media:counts[0],audio:(audio.first['c'] as int),video:(video.first['c'] as int),fingerprints:counts[3],tracks:counts[4],artists:counts[5],releases:counts[6],holders:counts[7],ownerships:counts[8],licenses:counts[9],comparisons:counts[10],pendingJobs:pending.first['c'] as int,failedJobs:failed.first['c'] as int);
  }
  Future<int> _count(Database db,String table)async{
    final safe=<String>{'studio_media_files','studio_fingerprints','studio_tracks','studio_artists','studio_releases','studio_rights_holders','studio_ownership_records','studio_licenses','studio_comparison_history','studio_jobs_pending','studio_jobs_failed','studio_media_files_audio','studio_media_files_video'};
    if(!safe.contains(table))throw ArgumentError('Unsupported report table');
    if(table=='studio_jobs_pending'||table=='studio_jobs_failed'||table=='studio_media_files_audio'||table=='studio_media_files_video')return 0;
    final result=await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return result.first['c'] as int;
  }
}
