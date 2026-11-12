import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/app/responsive/breakpoints.dart';

void main() {
  test('classifies compact widths', () {
    expect(AppBreakpoints.isCompact(599), isTrue);
    expect(AppBreakpoints.isCompact(600), isFalse);
  });

  test('classifies medium widths', () {
    expect(AppBreakpoints.isMedium(600), isTrue);
    expect(AppBreakpoints.isMedium(839), isTrue);
    expect(AppBreakpoints.isMedium(840), isFalse);
  });

  test('classifies wide widths', () {
    expect(AppBreakpoints.isWide(840), isTrue);
    expect(AppBreakpoints.isWide(1199), isTrue);
    expect(AppBreakpoints.isWide(1200), isFalse);
  });

  test('classifies expanded widths', () {
    expect(AppBreakpoints.isExpanded(1200), isTrue);
    expect(AppBreakpoints.isExpanded(1440), isTrue);
  });
}
