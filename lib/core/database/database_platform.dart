import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance/core/platform/platform_info.dart';

/// Database open hone se pehle munasib SQLite implementation select karta hai.
///
/// Android aur iOS native sqflite istemal karte hain. Windows, macOS aur Linux
/// FFI istemal karte hain aur database writable Application Support folder mein rakhte hain.
/// Desktop par SQLite FFI initialize karta hai; mobile par native setup barqarar rakhta hai.
Future<void> initializeDatabasePlatform() async {
  if (PlatformInfo.current.isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final supportDirectory = await getApplicationSupportDirectory();
    final databasesDirectory = p.join(supportDirectory.path, 'databases');
    await databaseFactory.setDatabasesPath(databasesDirectory);
  }
}
