import 'package:my_finance/modules/studio/infrastructure/database/studio_database_manager.dart';

class StudioDashboardSummary {
  const StudioDashboardSummary({
    required this.mediaFiles,
    required this.pendingJobs,
    required this.failedJobs,
  });

  final int mediaFiles;
  final int pendingJobs;
  final int failedJobs;
}

class StudioDashboardService {
  StudioDashboardService._();

  static final StudioDashboardService instance = StudioDashboardService._();

  Future<StudioDashboardSummary> loadSummary() async {
    final db = await StudioDatabaseManager.instance.initialize();

    final mediaFiles = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM studio_media_files',
    );
    final pendingJobs = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM studio_processing_jobs "
      "WHERE status IN ('pending', 'queued', 'running')",
    );
    final failedJobs = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM studio_processing_jobs "
      "WHERE status = 'failed'",
    );

    int count(List<Map<String, Object?>> rows) =>
        (rows.first['total'] as int?) ?? 0;

    return StudioDashboardSummary(
      mediaFiles: count(mediaFiles),
      pendingJobs: count(pendingJobs),
      failedJobs: count(failedJobs),
    );
  }
}
