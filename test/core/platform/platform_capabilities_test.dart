import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/core/platform/platform_capabilities.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('identifies Android as a mobile platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final capabilities = PlatformCapabilities.current();

    expect(capabilities.platform, AppPlatform.android);
    expect(capabilities.isMobile, isTrue);
    expect(capabilities.isDesktop, isFalse);
  });

  test('identifies iOS as a mobile platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final capabilities = PlatformCapabilities.current();

    expect(capabilities.platform, AppPlatform.ios);
    expect(capabilities.isMobile, isTrue);
    expect(capabilities.isDesktop, isFalse);
  });

  test('identifies desktop platforms', () {
    for (final target in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = target;

      final capabilities = PlatformCapabilities.current();

      expect(capabilities.isDesktop, isTrue);
      expect(capabilities.isMobile, isFalse);
    }
  });
}
