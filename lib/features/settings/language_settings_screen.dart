import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/language_settings_service.dart';

import 'package:my_finance/core/localization/app_text.dart';
class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  Future<void> _select(BuildContext context, String code) async {
    try {
      await LanguageSettingsService.instance.setLanguage(code);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(code == 'ur'
              ? 'زبان اردو میں تبدیل کر دی گئی'
              : 'Language changed to English'),
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageSettingsService.instance.locale,
      builder: (context, selectedLocale, _) {
        final isUrdu = selectedLocale.languageCode == 'ur';
        return Scaffold(
          appBar: AppBar(
            title: Text(isUrdu ? 'زبان' : 'Language'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: RadioListTile<String>(
                  value: 'en',
                  groupValue: selectedLocale.languageCode,
                  secondary: const Text('🇬🇧', style: TextStyle(fontSize: 24)),
                  title: const Text('English'),
                  subtitle: Text(appText(context, 'Left to right (LTR)', 'بائیں سے دائیں (LTR)')),
                  onChanged: (_) => _select(context, 'en'),
                ),
              ),
              Card(
                child: RadioListTile<String>(
                  value: 'ur',
                  groupValue: selectedLocale.languageCode,
                  secondary: const Text('🇵🇰', style: TextStyle(fontSize: 24)),
                  title: const Text('اردو'),
                  subtitle: const Text('دائیں سے بائیں (RTL)'),
                  onChanged: (_) => _select(context, 'ur'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isUrdu
                    ? 'زبان تبدیل کرنے سے ایپ کی سمت بھی تبدیل ہو جائے گی۔'
                    : 'Changing the language also changes the app direction.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: isUrdu ? TextAlign.right : TextAlign.left,
              ),
            ],
          ),
        );
      },
    );
  }
}
