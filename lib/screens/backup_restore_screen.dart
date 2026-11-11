import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../main.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import '../services/google_drive_backup_service.dart';
import '../services/transactions_service.dart';
import '../services/budgets_service.dart';
import '../services/goals_service.dart';
import '../services/recurring_transaction_service.dart';
import '../services/category_service.dart';
import '../services/loans_service.dart';
import '../services/attachment_service.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isProcessing = false;
  bool _loadingCloud = true;
  bool _autoEnabled = false;
  String _frequency = 'daily';
  String? _googleEmail;
  String? _lastSuccess;

  @override
  void initState() {
    super.initState();
    _loadCloudSettings();
  }

  Future<String?> _readSetting(String key) async {
    final rows = await FinanceDB.instance.db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value']?.toString();
  }

  Future<void> _writeSetting(String key, String value) async {
    await FinanceDB.instance.db.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _loadCloudSettings() async {
    try {
      final enabled = await _readSetting('auto_backup_enabled');
      final frequency = await _readSetting('auto_backup_frequency');
      final last = await _readSetting('auto_backup_last_success');
      String? connectedEmail;
      try {
        connectedEmail =
            (await GoogleDriveBackupService.signInSilently())?.email;
      } catch (_) {
        connectedEmail = null;
      }
      if (!mounted) return;
      setState(() {
        _autoEnabled = enabled == '1';
        _frequency = frequency == 'weekly' ? 'weekly' : 'daily';
        _googleEmail = connectedEmail;
        _lastSuccess = last;
        _loadingCloud = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCloud = false);
    }
  }

  Future<bool> _connectDrive() async {
    try {
      final email = await GoogleDriveBackupService.connect();
      if (email == null) return false;
      await _writeSetting('google_drive_email', email);
      if (!mounted) return false;
      setState(() => _googleEmail = email);
      _showMessage('Google Drive connected: $email');
      return true;
    } catch (error) {
      _showMessage(
        'Google Drive connection failed. Check Android OAuth setup: $error',
        isError: true,
      );
      return false;
    }
  }

  Future<void> _setAutomaticBackup(bool enabled) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      if (enabled && _googleEmail == null) {
        final connected = await _connectDrive();
        if (!connected) return;
      }
      await _writeSetting('auto_backup_enabled', enabled ? '1' : '0');
      await _writeSetting('auto_backup_frequency', _frequency);
      await AutoBackupService.configure(
        enabled: enabled,
        frequency: _frequency,
      );
      if (!mounted) return;
      setState(() => _autoEnabled = enabled);
      _showMessage(enabled
          ? 'Automatic Google Drive backup scheduled.'
          : 'Automatic backup disabled.');
    } catch (error) {
      _showMessage('Could not update automatic backup: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _changeFrequency(String? value) async {
    if (value == null) return;
    setState(() => _frequency = value);
    await _writeSetting('auto_backup_frequency', value);
    if (_autoEnabled) {
      try {
        await AutoBackupService.configure(enabled: true, frequency: value);
        _showMessage('Backup frequency updated.');
      } catch (error) {
        _showMessage('Could not update schedule: $error', isError: true);
      }
    }
  }

  Future<void> _runCloudBackup() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      if (_googleEmail == null) {
        final connected = await _connectDrive();
        if (!connected) return;
      }
      await AutoBackupService.runNow();
      await _loadCloudSettings();
      if (mounted) _showMessage('Backup uploaded to Google Drive successfully.');
    } catch (error) {
      _showMessage('Google Drive backup failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<Directory> _getBackupDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'My Finance Backups'));
    await directory.create(recursive: true);
    return directory;
  }

  // Existing ZIP backup service is reused; only its destination is changed.
  Future<void> _createBackup() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final backupBytes = await BackupService.createBackup(
        database: FinanceDB.instance.db,
      );
      final directory = await _getBackupDirectory();
      final now = DateTime.now();
      final fileName =
          'My_Finance_Backup_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}.zip';
      final backupFile = File(p.join(directory.path, fileName));
      await backupFile.writeAsBytes(backupBytes, flush: true);

      if (mounted) {
        _showMessage('Backup saved in phone storage: ${backupFile.path}');
      }
    } catch (error) {
      if (mounted) _showMessage('Backup failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  Future<void> _restoreLocalBackup() async {
    if (_isProcessing) return;
    try {
      final directory = await _getBackupDirectory();
      final files = await directory
          .list()
          .where((entry) => entry is File && entry.path.toLowerCase().endsWith('.zip'))
          .cast<File>()
          .toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      if (!mounted) return;
      if (files.isEmpty) {
        _showMessage('No internal backup found. Create a backup first.', isError: true);
        return;
      }

      final selected = await showDialog<File>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Select Internal Backup'),
          children: [
            SizedBox(
              width: double.maxFinite,
              height: 280,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  return ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(p.basename(file.path),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(file.lastModifiedSync().toString()),
                    onTap: () => Navigator.pop(dialogContext, file),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      await _restoreBackupBytes(bytes);
    } catch (error) {
      if (mounted) _showMessage('Unable to read internal backup: $error', isError: true);
    }
  }

  Future<void> _importBackupFile() async {
    if (_isProcessing) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select My Finance Backup',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;

      final selectedFile = result.files.single;
      Uint8List? bytes = selectedFile.bytes;
      if (bytes == null && selectedFile.path != null) {
        bytes = await File(selectedFile.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        _showMessage('Selected backup file could not be read.', isError: true);
        return;
      }
      await _restoreBackupBytes(bytes);
    } catch (error) {
      if (mounted) _showMessage('Unable to import backup: $error', isError: true);
    }
  }

  Future<void> _restoreBackupBytes(Uint8List backupBytes) async {
    if (!mounted) return;
    final confirmed = await _confirmRestore();
    if (!mounted || confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      await TransactionsService.closeDatabase();
      await BudgetsService.closeDatabase();
      await GoalsService.closeDatabase();
      await RecurringTransactionService.closeDatabase();
      await CategoryService.closeDatabase();
      await LoansService.closeDatabase();
      await AttachmentService.closeDatabase();
      await FinanceDB.instance.close();

      await BackupService.restoreBackup(backupBytes: backupBytes);
      if (mounted) _showMessage('Backup restore successfully complete ho gaya.');
    } catch (error) {
      if (mounted) _showMessage('Restore failed: $error', isError: true);
    } finally {
      await FinanceDB.instance.reopen();
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool?> _confirmRestore() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: const Text(
          'Restore karne se mojooda finance database aur attachments '
          'backup wali files se replace ho jayengi. Is ke baad ki '
          'tabdeeliyan zaya ho sakti hain. Kya aap jari rakhna chahte hain?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildCloudBackupCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  child: Icon(Icons.cloud_sync_rounded),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Automatic Google Drive Backup',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Keep a scheduled copy of your finance data in Drive.',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                if (_loadingCloud)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(_googleEmail ?? 'Google account not connected'),
              subtitle: const Text('Google Drive account'),
              trailing: TextButton(
                onPressed: _isProcessing ? null : _connectDrive,
                child: Text(_googleEmail == null ? 'Connect' : 'Reconnect'),
              ),
            ),
            const Divider(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Automatic Backup'),
              subtitle: const Text('Runs in the background when Android allows it'),
              value: _autoEnabled,
              onChanged: _loadingCloud || _isProcessing
                  ? null
                  : _setAutomaticBackup,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Backup Frequency'),
              trailing: DropdownButton<String>(
                value: _frequency,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                ],
                onChanged: _autoEnabled ? _changeFrequency : null,
              ),
            ),
            if (_lastSuccess != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Last successful backup: $_lastSuccess',
                  style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isProcessing ? null : _runCloudBackup,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Back Up to Google Drive Now'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: Android may delay background jobs due to battery and network restrictions. '
              'The first cloud backup can be started manually.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(description),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : onPressed,
                icon: Icon(icon),
                label: Text(buttonText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(Icons.backup_rounded,
                        size: 48, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 10),
                    const Text('Protect Your Finance Data',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 7),
                    const Text(
                      'Keep a local copy on your phone or schedule a cloud backup to Google Drive.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildCloudBackupCard(),
              const SizedBox(height: 16),
              _buildActionCard(
                icon: Icons.save_alt_rounded,
                title: 'Manual Backup',
                description: 'Save a ZIP copy of your database and attachments in My Finance Backups inside the app storage.',
                buttonText: 'Create Internal Backup',
                color: Colors.indigo,
                onPressed: _createBackup,
              ),
              const SizedBox(height: 12),
              _buildActionCard(
                icon: Icons.folder_open_rounded,
                title: 'Restore Internal Backup',
                description: 'Choose a backup previously saved on this phone by My Finance.',
                buttonText: 'Choose Internal Backup',
                color: Colors.teal,
                onPressed: _restoreLocalBackup,
              ),
              const SizedBox(height: 12),
              _buildActionCard(
                icon: Icons.file_open_rounded,
                title: 'Import Backup ZIP',
                description: 'Restore a My Finance ZIP file selected from another folder or device.',
                buttonText: 'Select ZIP File',
                color: Colors.blueGrey,
                onPressed: _importBackupFile,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Important: Restoring a backup replaces your current database and attachments. '
                  'Always verify the selected ZIP before continuing.',
                  style: TextStyle(height: 1.45, fontSize: 12),
                ),
              ),
            ],
          ),
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
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
}
