import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/core/platform/platform_info.dart';

// Ye tests mukhtalif Flutter targets ki platform mapping aur capability flags verify karte hain.
void main() {
  group('PlatformInfo.fromTarget', () {
    test('maps Android and iOS as mobile platforms', () {
      expect(
        PlatformInfo.fromTarget(TargetPlatform.android).platform,
        AppPlatform.android,
      );
      expect(
        PlatformInfo.fromTarget(TargetPlatform.iOS).platform,
        AppPlatform.ios,
      );
      expect(PlatformInfo.fromTarget(TargetPlatform.android).isMobile, isTrue);
      expect(PlatformInfo.fromTarget(TargetPlatform.iOS).isMobile, isTrue);
    });

    test('maps desktop targets as desktop platforms', () {
      for (final target in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(PlatformInfo.fromTarget(target).isDesktop, isTrue);
        expect(PlatformInfo.fromTarget(target).isMobile, isFalse);
      }
    });

    test('web takes precedence over target platform', () {
      expect(
        PlatformInfo.fromTarget(TargetPlatform.android, isWeb: true).platform,
        AppPlatform.web,
      );
      expect(
        PlatformInfo.fromTarget(TargetPlatform.android, isWeb: true).isMobile,
        isFalse,
      );
    });

    test('maps Fuchsia', () {
      expect(
        PlatformInfo.fromTarget(TargetPlatform.fuchsia).platform,
        AppPlatform.fuchsia,
      );
    });
  });
}
