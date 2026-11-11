import 'package:flutter/foundation.dart';

/// App-wide signal used by tabs to reload data after a successful change.
class AppRefreshController {
  AppRefreshController._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyChanged() {
    revision.value++;
  }
}
