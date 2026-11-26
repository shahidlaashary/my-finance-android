import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

// Ye tests rapid data updates ke darmiyan app-wide refresh debounce verify karte hain.
void main() {
  test('coalesces rapid data changes into one app-wide refresh', () async {
    final before = AppRefreshController.revision.value;

    AppRefreshController.notifyChanged();
    AppRefreshController.notifyChanged();

    expect(AppRefreshController.revision.value, before);

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(AppRefreshController.revision.value, before + 1);
  });
}
