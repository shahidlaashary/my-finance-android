import 'dart:async';

import 'package:flutter/foundation.dart';

/// App-wide signal used by tabs to reload data after a successful change.
class AppRefreshController {
  AppRefreshController._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Timer? _pendingRefresh;

  /// Coalesces several balance updates and lets SQLite transactions finish
  /// before screens start reloading their data.
  static void notifyChanged() {
    _pendingRefresh?.cancel();
    _pendingRefresh = Timer(const Duration(milliseconds: 300), () {
      revision.value++;
      _pendingRefresh = null;
    });
  }
}
