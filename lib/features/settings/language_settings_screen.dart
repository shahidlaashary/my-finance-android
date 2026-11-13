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
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final language in _languages)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: RadioListTile<String>(
                    value: language.code,
                    groupValue: selectedLocale.languageCode,
                    secondary: Text(language.flag,
                        style: const TextStyle(fontSize: 24)),
                    title: Text(language.nativeName,
                        textDirection: language.rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr),
                    subtitle: Text(language.englishName),
                    onChanged: (_) => _select(context, language.code),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                isUrdu
                    ? 'زبان تبدیل کرنے سے ایپ کی سمت بھی تبدیل ہو جائے گی۔'
                    : selectedLocale.languageCode == 'bal'
                        ? 'زبان بدلگ ءَ ایپ ءِ لکھت ءِ سمت ھم بدل بیت۔'
                        : selectedLocale.languageCode == 'ps'
                            ? 'د ژبې په بدلولو سره د اپ د متن لوری هم بدلېږي.'
                            : 'Changing the language also changes the app text direction.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
            ],
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
