import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/features/backup_restore/services/backup_service.dart';

void main() {
  group('BackupService.resolveRestoredAttachmentPath', () {
    test('maps an Android absolute path to the current attachment directory', () {
      final result = BackupService.resolveRestoredAttachmentPath(
        storedPath: '/data/old.app/files/my_finance_attachments/asset_42/photo.jpg',
        attachmentsDirectory: '/data/new.app/files/my_finance_attachments',
      );

      expect(
        result,
        '/data/new.app/files/my_finance_attachments/asset_42/photo.jpg',
      );
    });

    test('normalizes Windows separators before mapping the path', () {
      final result = BackupService.resolveRestoredAttachmentPath(
        storedPath: r'C:\Users\old\my_finance_attachments\transaction_9\receipt.pdf',
        attachmentsDirectory: '/current/docs/my_finance_attachments',
      );

      expect(
        result,
        '/current/docs/my_finance_attachments/transaction_9/receipt.pdf',
      );
    });

    test('preserves legacy or external paths without attachment marker', () {
      const legacyPath = '/external/storage/receipts/receipt.pdf';

      final result = BackupService.resolveRestoredAttachmentPath(
        storedPath: legacyPath,
        attachmentsDirectory: '/current/docs/my_finance_attachments',
      );

      expect(result, legacyPath);
    });

    test('rejects traversal inside the attachment-relative path', () {
      expect(
        () => BackupService.resolveRestoredAttachmentPath(
          storedPath: '/old/my_finance_attachments/asset_1/../../secret.txt',
          attachmentsDirectory: '/current/docs/my_finance_attachments',
        ),
        throwsException,
      );
    });
  });
}
