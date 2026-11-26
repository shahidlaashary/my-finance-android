import 'package:flutter/foundation.dart';

/// My Finance ke shared code mein support kiye gaye runtime platforms.
enum AppPlatform {
  android,
  ios,
  windows,
  macos,
  linux,
  web,
  fuchsia,
}

/// Shared app code ke liye current runtime platform ki pehchan deta hai.
///
/// dart:io ke bajaye Flutter target APIs istemal karta hai, is liye shared code
/// aur tests native dependencies ke baghair isay use kar sakte hain. Camera,
/// biometrics aur notifications jaisi capabilities alag plugin APIs se check hon.
class PlatformInfo {
  const PlatformInfo(this.platform);

  final AppPlatform platform;

  /// Har access par current Flutter target detect karta hai; result cache nahi hota.
  static PlatformInfo get current =>
      PlatformInfo.fromTarget(defaultTargetPlatform, isWeb: kIsWeb);

  /// Flutter target ko app ke apne platform enum mein map karta hai.
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
