import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Selects the SQLite implementation before the app opens its database.
///
/// Android and iOS continue to use the native sqflite implementation.
/// Windows, macOS and Linux use the FFI implementation and store the
/// database under the app's writable Application Support directory.
Future<void> initializeDatabasePlatform() async {
  final platform = defaultTargetPlatform;
  final useDesktopFfi = platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux;

  if (useDesktopFfi) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final supportDirectory = await getApplicationSupportDirectory();
    final databasesDirectory = p.join(supportDirectory.path, 'databases');
    await databaseFactory.setDatabasesPath(databasesDirectory);
  }
}
