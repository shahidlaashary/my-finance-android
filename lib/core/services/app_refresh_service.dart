import 'dart:async';

import 'package:flutter/foundation.dart';

/// Ye shared signal successful data change ke baad app tabs ko refresh karta hai.
class AppRefreshController {
  AppRefreshController._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Timer? _pendingRefresh;

  /// Qareebi updates ko aik refresh mein jama karta hai taake SQLite transaction
  /// mukammal hone ke baad screens apna data dobara load karein.
  /// Pending refresh timer reset karke tamam listeners ko tabdeel ki khabar deta hai.
  static void notifyChanged() {
    _pendingRefresh?.cancel();
    _pendingRefresh = Timer(const Duration(milliseconds: 60), () {
      revision.value++;
      _pendingRefresh = null;
    });
  }
}
