import 'package:flutter/foundation.dart';

/// Supported runtime targets for the shared My Finance codebase.
enum AppPlatform {
  android,
  ios,
  windows,
  macos,
  linux,
  web,
  fuchsia,
}

/// Platform identification for shared app code.
///
/// Uses Flutter's target platform APIs rather than importing dart:io, so this
/// helper can be referenced by shared code and tests without native dependencies.
/// Capability checks (camera, biometrics, notifications, etc.) should remain
/// separate and use the relevant plugin/device APIs when needed.
class PlatformInfo {
  const PlatformInfo(this.platform);

  final AppPlatform platform;

  /// Detects the current Flutter target at access time (not cached).
  static PlatformInfo get current =>
      PlatformInfo.fromTarget(defaultTargetPlatform, isWeb: kIsWeb);

  factory PlatformInfo.fromTarget(
    TargetPlatform target, {
    bool isWeb = false,
  }) {
    if (isWeb) return const PlatformInfo(AppPlatform.web);

    switch (target) {
      case TargetPlatform.android:
        return const PlatformInfo(AppPlatform.android);
      case TargetPlatform.iOS:
        return const PlatformInfo(AppPlatform.ios);
      case TargetPlatform.windows:
        return const PlatformInfo(AppPlatform.windows);
      case TargetPlatform.macOS:
        return const PlatformInfo(AppPlatform.macos);
      case TargetPlatform.linux:
        return const PlatformInfo(AppPlatform.linux);
      case TargetPlatform.fuchsia:
        return const PlatformInfo(AppPlatform.fuchsia);
    }
  }

  bool get isAndroid => platform == AppPlatform.android;
  bool get isIOS => platform == AppPlatform.ios;
  bool get isWindows => platform == AppPlatform.windows;
  bool get isMacOS => platform == AppPlatform.macos;
  bool get isLinux => platform == AppPlatform.linux;
  bool get isWeb => platform == AppPlatform.web;
  bool get isFuchsia => platform == AppPlatform.fuchsia;

  bool get isMobile => isAndroid || isIOS;
  bool get isDesktop => isWindows || isMacOS || isLinux;
}
