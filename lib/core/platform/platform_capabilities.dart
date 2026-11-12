import 'package:flutter/foundation.dart';

/// Logical platform groups used by shared application code.
///
/// Keep platform checks in this layer instead of scattering
/// [defaultTargetPlatform] checks across feature screens.
enum AppPlatform {
  android,
  ios,
  windows,
  macos,
  linux,
  web,
  fuchsia,
}

class PlatformCapabilities {
  const PlatformCapabilities._(this.platform);

  factory PlatformCapabilities.current() {
    final platform = kIsWeb
        ? AppPlatform.web
        : _fromTargetPlatform(defaultTargetPlatform);
    return PlatformCapabilities._(platform);
  }

  final AppPlatform platform;

  bool get isMobile =>
      platform == AppPlatform.android || platform == AppPlatform.ios;

  bool get isDesktop =>
      platform == AppPlatform.windows ||
      platform == AppPlatform.macos ||
      platform == AppPlatform.linux;

  bool get isWeb => platform == AppPlatform.web;

  static AppPlatform _fromTargetPlatform(TargetPlatform value) {
    switch (value) {
      case TargetPlatform.android:
        return AppPlatform.android;
      case TargetPlatform.iOS:
        return AppPlatform.ios;
      case TargetPlatform.windows:
        return AppPlatform.windows;
      case TargetPlatform.macOS:
        return AppPlatform.macos;
      case TargetPlatform.linux:
        return AppPlatform.linux;
      case TargetPlatform.fuchsia:
        return AppPlatform.fuchsia;
    }
  }
}
