/// Shared responsive layout thresholds.
///
/// Compact layouts target phones, medium layouts target small tablets,
/// wide layouts target larger tablets/small desktop windows, and expanded
/// layouts target desktop-sized windows.
abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;

  static bool isCompact(double width) => width < compact;

  static bool isMedium(double width) =>
      width >= compact && width < medium;

  static bool isWide(double width) =>
      width >= medium && width < expanded;

  static bool isExpanded(double width) => width >= expanded;
}
