import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/backup_service.dart';
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});
  @override
  State<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}
class _BackupRestoreScreenState
    extends State<BackupRestoreScreen> {
  bool _isProcessing = false;
  Future<void> _createBackup() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });
    try {
      final database = FinanceDB.instance.db;
      final Uint8List backupBytes =
          await BackupService.createBackup(
        database: database,
      );
      if (!mounted) return;
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save My Finance Backup',
        fileName: 'My_Finance_Backup.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: backupBytes,
      );
      if (!mounted) return;
      if (savedPath == null) {
        _showMessage('Backup save cancelled.');
      } else {
        _showMessage('Backup created successfully.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Backup failed: ${error.toString()}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
  Future<void> _selectAndRestoreBackup() async {
    if (_isProcessing) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select My Finance Backup',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }
      final selectedFile = result.files.single;
      Uint8List? backupBytes = selectedFile.bytes;
      if (backupBytes == null && selectedFile.path != null) {
        backupBytes = await File(selectedFile.path!).readAsBytes();
      }
      if (backupBytes == null || backupBytes.isEmpty) {
        _showMessage(
          'Could not read the selected backup file.',
          isError: true,
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await _confirmRestore();
      if (!mounted || confirmed != true) return;
      setState(() {
        _isProcessing = true;
      });
      // Close the active database before replacing its file.
      await FinanceDB.instance.close();
      try {
        await BackupService.restoreBackup(
          backupBytes: backupBytes,
        );
      } finally {
        // Reopen the database whether restore succeeds or fails.
        await FinanceDB.instance.reopen();
      }
      if (!mounted) return;
      _showMessage(
        'Backup restored successfully. Your finance data has been updated.',
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Restore failed: ${error.toString()}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
  Future<bool?> _confirmRestore() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restore Backup?'),
          content: const Text(
            'Restoring this backup will replace your current '
            'finance database and attachments.\n\n'
            'Any data added after this backup was created '
            'may be lost.\n\n'
            'Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );
  }
  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.backup,
                      size: 55,
                      color: Colors.indigo,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Protect Your Finance Data',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a backup of your finance database '
                      'and attachments, or restore your data '
                      'from an existing backup.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildFeatureCard(
                icon: Icons.cloud_upload,
                title: 'Create Backup',
                description:
                    'Save your finance data and attachments '
                    'in a ZIP backup file.',
                buttonText: 'Create Backup',
                color: Colors.indigo,
                onPressed: _createBackup,
              ),
              const SizedBox(height: 16),
              _buildFeatureCard(
                icon: Icons.settings_backup_restore,
                title: 'Restore Backup',
                description:
                    'Select a previously created My Finance '
                    'ZIP backup to restore your data.',
                buttonText: 'Select Backup File',
                color: Colors.teal,
                onPressed: _selectAndRestoreBackup,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Keep your backup ZIP file in a safe '
                        'location. Restoring a backup replaces '
                        'your current finance data.',
                        style: TextStyle(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Please wait...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    icon,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : onPressed,
                icon: Icon(icon),
                label: Text(buttonText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
