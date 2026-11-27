import 'package:sqflite/sqflite.dart';
import '../../infrastructure/database/studio_database_manager.dart';

class StudioReportSummary{
  const StudioReportSummary({required this.media,required this.audio,required this.video,required this.fingerprints,required this.tracks,required this.artists,required this.releases,required this.holders,required this.ownerships,required this.licenses,required this.comparisons,required this.pendingJobs,required this.failedJobs});
  final int media,audio,video,fingerprints,tracks,artists,releases,holders,ownerships,licenses,comparisons,pendingJobs,failedJobs;
}
class StudioReportsService{
  Future<StudioReportSummary> load()async{
    final db=await StudioDatabaseManager.instance.initialize();
    final counts=await Future.wait([
      _count(db,'studio_media_files'),_count(db,'studio_fingerprints'),_count(db,'studio_tracks'),_count(db,'studio_artists'),_count(db,'studio_releases'),_count(db,'studio_rights_holders'),_count(db,'studio_ownership_records'),_count(db,'studio_licenses'),_count(db,'studio_comparison_history'),
    ]);
    final audio=await db.rawQuery("SELECT COUNT(*) AS c FROM studio_media_files WHERE media_type='audio'");
    final video=await db.rawQuery("SELECT COUNT(*) AS c FROM studio_media_files WHERE media_type='video'");
    final pending=await db.rawQuery("SELECT COUNT(*) AS c FROM studio_processing_jobs WHERE status IN ('pending','queued','running')");
    final failed=await db.rawQuery("SELECT COUNT(*) AS c FROM studio_processing_jobs WHERE status='failed'");
    return StudioReportSummary(media:counts[0],audio:audio.first['c'] as int,video:video.first['c'] as int,fingerprints:counts[1],tracks:counts[2],artists:counts[3],releases:counts[4],holders:counts[5],ownerships:counts[6],licenses:counts[7],comparisons:counts[8],pendingJobs:pending.first['c'] as int,failedJobs:failed.first['c'] as int);
  }
  Future<int> _count(Database db,String table)async{
    const allowed={'studio_media_files','studio_fingerprints','studio_tracks','studio_artists','studio_releases','studio_rights_holders','studio_ownership_records','studio_licenses','studio_comparison_history'};
    if(!allowed.contains(table))throw ArgumentError('Unsupported report table');
    final rows=await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return rows.first['c'] as int;
  }
}
