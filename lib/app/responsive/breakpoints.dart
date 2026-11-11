/// Shared responsive layout thresholds.
///
/// Keep these values centralized so mobile, tablet and desktop screens
/// use consistent layout decisions.
abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;

  static bool isCompact(double width) => width < compact;

  static bool isMedium(double width) =>
      width >= compact && width < expanded;

  static bool isExpanded(double width) => width >= expanded;
}
