import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Selects the SQLite implementation before the app opens its database.
///
/// Android and iOS continue to use the native sqflite implementation.
/// Windows, macOS and Linux use the FFI implementation.
Future<void> initializeDatabasePlatform() async {
  final platform = defaultTargetPlatform;
  final useDesktopFfi = platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux;

  if (useDesktopFfi) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
