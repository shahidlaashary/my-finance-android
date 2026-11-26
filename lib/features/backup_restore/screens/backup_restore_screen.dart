import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';

/// Testing phase ke dauran backup aur restore screen filhal intentionally unavailable hai.
class BackupRestoreScreen extends StatelessWidget {
  const BackupRestoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context, 'Backup & Restore', 'بیک اپ اور بحالی')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.science_outlined,
                    size: 42,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    appText(
                      context,
                      'Unavailable During Testing',
                      'ٹیسٹنگ کے دوران دستیاب نہیں',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appText(
                      context,
                      'Backup and restore are turned off until the app is finalized. Test data will not be exported or restored.',
                      'ایپ مکمل ہونے تک بیک اپ اور بحالی بند ہیں۔ ٹیسٹنگ ڈیٹا نہ بیک اپ ہوگا اور نہ بحال کیا جا سکے گا۔',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
