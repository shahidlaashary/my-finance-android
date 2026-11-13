import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/core/preferences/language_settings_service.dart';

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  static const _languages = <_LanguageOption>[
    _LanguageOption('en', 'English', 'English', '🇬🇧', false),
    _LanguageOption('ur', 'اردو', 'Urdu', '🇵🇰', true),
    _LanguageOption('ar', 'العربية', 'Arabic', '🇸🇦', true),
    _LanguageOption('hi', 'हिन्दी', 'Hindi', '🇮🇳', false),
    _LanguageOption('pa', 'پنجابی', 'Punjabi (Shahmukhi)', '🇵🇰', true),
    _LanguageOption('skr', 'سرائیکی', 'Saraiki', '🇵🇰', true),
    _LanguageOption('sd', 'سنڌي', 'Sindhi', '🇵🇰', true),
    _LanguageOption('bal', 'بلوچی', 'Balochi', '🇵🇰', true),
    _LanguageOption('ps', 'پښتو', 'Pashto', '🇵🇰', true),
  ];

  Future<void> _select(BuildContext context, String code) async {
    try {
      await LanguageSettingsService.instance.setLanguage(code);
      if (!context.mounted) return;
      final selected = _languages.firstWhere((item) => item.code == code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_successMessage(code, selected.nativeName)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save language: $error')),
      );
    }
  }

  String _successMessage(String code, String name) {
    switch (code) {
      case 'ur': return 'زبان اردو میں تبدیل کر دی گئی';
      case 'ar': return 'تم تغيير اللغة إلى العربية';
      case 'hi': return 'भाषा हिंदी में बदल दी गई है';
      case 'pa': return 'زبان پنجابی وچ تبدیل کر دتی گئی اے';
      case 'skr': return 'ٻولي سرائيڪي ۾ تبديل ڪئي وئي';
      case 'sd': return 'ٻولي سنڌي ۾ تبديل ڪئي وئي';
      case 'bal': return 'زبان بلوچیءَ میں تبدیل کرتگ بوت';
      case 'ps': return 'ژبه پښتو ته بدله شوه';
      default: return 'Language changed to $name';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageSettingsService.instance.locale,
      builder: (context, selectedLocale, _) {
        final isUrdu = selectedLocale.languageCode == 'ur';
        final isRtl = const {'ur', 'ar', 'pa', 'skr', 'sd', 'bal', 'ps'}
            .contains(selectedLocale.languageCode);
        return Scaffold(
          appBar: AppBar(
            title: Text(appText(context, 'Languages', 'زبانیں')),
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
              child: Column(
                children: [
                  for (final language in _languages)
                    Expanded(
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _select(context, language.code),
                          child: Directionality(
                            // Keep the radio, flag and text columns aligned
                            // identically for both LTR and RTL app languages.
                            textDirection: TextDirection.ltr,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 42,
                                  child: Radio<String>(
                                    value: language.code,
                                    groupValue: selectedLocale.languageCode,
                                    onChanged: (_) =>
                                        _select(context, language.code),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                SizedBox(
                                  width: 30,
                                  child: Center(
                                    child: Text(
                                      language.flag,
                                      style: const TextStyle(fontSize: 19),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          language.nativeName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textDirection: language.rtl
                                              ? TextDirection.rtl
                                              : TextDirection.ltr,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            height: 1.15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          language.englishName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.1,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 31,
                    child: Align(
                      alignment: isRtl
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
                        isUrdu
                            ? 'زبان تبدیل کرنے سے ایپ کی سمت بھی تبدیل ہو جائے گی۔'
                            : selectedLocale.languageCode == 'bal'
                                ? 'زبان بدلگ ءَ ایپ ءِ لکھت ءِ سمت ھم بدل بیت۔'
                                : selectedLocale.languageCode == 'ps'
                                    ? 'د ژبې په بدلولو سره د اپ د متن لوری هم بدلېږي.'
                                    : 'Changing the language also changes the app text direction.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: isRtl ? TextAlign.right : TextAlign.left,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanguageOption {
  const _LanguageOption(
    this.code,
    this.nativeName,
    this.englishName,
    this.flag,
    this.rtl,
  );

  final String code;
  final String nativeName;
  final String englishName;
  final String flag;
  final bool rtl;
}
