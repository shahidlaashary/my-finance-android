import 'package:flutter/widgets.dart';

/// Centralized English/Urdu text helper for app UI.
String appText(BuildContext context, String english, String urdu) {
  return Localizations.localeOf(context).languageCode == 'ur' ? urdu : english;
}
