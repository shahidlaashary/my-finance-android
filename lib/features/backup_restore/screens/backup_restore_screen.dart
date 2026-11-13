import 'dart:io';
import 'dart:typed_data';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/backup_restore/services/backup_service.dart';
import 'package:my_finance/features/backup_restore/services/automatic_backup_service.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/features/finance/services/budgets_service.dart';
import 'package:my_finance/features/finance/services/goals_service.dart';
import 'package:my_finance/features/finance/services/recurring_transaction_service.dart';
import 'package:my_finance/features/finance/services/category_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/core/services/attachment_service.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isProcessing = false;
  bool _automaticEnabled = false;
  DateTime? _lastAutomaticBackup;
  String? _automaticStatus;

  @override
  void initState() { super.initState(); _loadAutomaticBackupState(); }

  Future<void> _loadAutomaticBackupState() async {
    final enabled = await AutomaticBackupService.isEnabled();
    final last = await AutomaticBackupService.lastSuccessfulBackup();
    final status = await AutomaticBackupService.lastStatus();
    if (!mounted) return;
    setState(() { _automaticEnabled = enabled; _lastAutomaticBackup = last; _automaticStatus = status; });
  }

  Future<void> _toggleAutomaticBackup(bool enabled) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try { await AutomaticBackupService.setEnabled(enabled); await _loadAutomaticBackupState(); if (mounted) _showMessage(enabled ? 'Automatic backup enabled. Pehla backup abhi bana diya gaya.' : 'Automatic backup disabled.'); }
    catch (error) { if (mounted) _showMessage('Automatic backup failed: $error', isError: true); await _loadAutomaticBackupState(); }
    finally { if (mounted) setState(() => _isProcessing = false); }
  }

  Future<void> _createAutomaticBackupNow() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try { await AutomaticBackupService.createBackupNow(); await _loadAutomaticBackupState(); if (mounted) _showMessage('Automatic backup successfully created.'); }
    catch (error) { if (mounted) _showMessage('Automatic backup failed: $error', isError: true); await _loadAutomaticBackupState(); }
    finally { if (mounted) setState(() => _isProcessing = false); }
  }

  // User ke liye manual ZIP backup banata hai.
  Future<void> _createBackup() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final backupBytes = await BackupService.createBackup(
        database: FinanceDB.instance.db,
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
      _showMessage(
        savedPath == null
            ? 'Backup save cancelled.'
            : 'Backup created successfully.',
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Backup failed: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // User ki select ki hui ZIP file se database aur attachments restore karta hai.
  Future<void> _selectAndRestoreBackup() async {
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
      Uint8List? backupBytes = selectedFile.bytes;

      if (backupBytes == null && selectedFile.path != null) {
        backupBytes = await File(selectedFile.path!).readAsBytes();
      }

      if (backupBytes == null || backupBytes.isEmpty) {
        _showMessage('Selected backup file parhi nahi ja saki.', isError: true);
        return;
      }

      if (!mounted) return;
      final confirmed = await _confirmRestore();
      if (!mounted || confirmed != true) return;

      setState(() => _isProcessing = true);

      try {
        // Restore se pehle tamam database connections band karta hai.
        await TransactionsService.closeDatabase();
        await BudgetsService.closeDatabase();
        await GoalsService.closeDatabase();
        await RecurringTransactionService.closeDatabase();
        await CategoryService.closeDatabase();
        await LoansService.closeDatabase();
        await AttachmentService.closeDatabase();
        await FinanceDB.instance.close();

        await BackupService.restoreBackup(backupBytes: backupBytes);
      } finally {
        // Restore kamyab ho ya fail, main database dobara kholta hai.
        await FinanceDB.instance.reopen();
      }

      if (mounted) {
        _showMessage('Backup restore successfully complete ho gaya.');
      }
    } catch (error) {
      if (mounted) _showMessage('Restore failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Restore se pehle user se tasdeeq leta hai.
  Future<bool?> _confirmRestore() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appText(context, 'Restore Backup?', 'بیک اپ بحال کریں؟')),
        content: const Text(
          'Restore karne se mojooda finance database aur attachments '
          'backup wali files se replace ho jayengi. Is ke baad ki '
          'tabdeeliyan zaya ho sakti hain. Kya aap jari rakhna chahte hain?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(appText(context, 'Restore', 'بحال کریں')),
          ),
        ],
      ),
    );
  }

  // Screen par natija dikhata hai.
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
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
      appBar: AppBar(title: Text(appText(context, 'Backup & Restore', 'بیک اپ اور بحالی'))),
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
                    Icon(
                      Icons.backup_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    SizedBox(height: 12),
                    const Text(
                      'Protect Your Finance Data',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    const Text(
                      'Apne finance data aur attachments ka manual backup banayein '
                      'ya pehle banaya gaya backup restore karein.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.autorenew_rounded), const SizedBox(width: 10), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Automatic Local Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text('Daily backup on this device')])), Switch.adaptive(value: _automaticEnabled, onChanged: _isProcessing ? null : _toggleAutomaticBackup)]),
                const Divider(),
                Text('Last successful backup: ' + (_lastAutomaticBackup == null ? 'Not yet' : DateFormat('d MMM yyyy, h:mm a').format(_lastAutomaticBackup!))),
                if (_automaticStatus == 'failed') const Text('Last backup failed. Try again.', style: TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _isProcessing ? null : _createAutomaticBackupNow, icon: const Icon(Icons.backup_rounded), label: const Text('Back Up Now'))),
                const SizedBox(height: 6),
                const Text('7 newest backups are kept privately on this device. A due backup is created when the app starts; it does not run while the app is fully closed.', style: TextStyle(fontSize: 12)),
              ]))),
              SizedBox(height: 16),
              _buildActionCard(
                icon: Icons.cloud_upload_rounded,
                title: 'Create Manual Backup',
                description: 'Database aur attachments ki ZIP file save karein.',
                buttonText: 'Create Backup',
                color: Colors.indigo,
                onPressed: _createBackup,
              ),
              SizedBox(height: 16),
              _buildActionCard(
                icon: Icons.settings_backup_restore_rounded,
                title: 'Restore Backup',
                description: 'Pehle banayi hui My Finance ZIP file restore karein.',
                buttonText: 'Select Backup File',
                color: Colors.teal,
                onPressed: _selectAndRestoreBackup,
              ),
              SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Zaroori: Backup restore karne se current database aur '
                  'attachments replace ho jayenge. Restore se pehle confirm '
                  'kar lein ke selected ZIP file sahi hai.',
                  style: TextStyle(height: 1.45),
                ),
              ),
            ],
          ),
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
                          Text(appText(context, 'Please wait...', 'براہ کرم انتظار کریں')),
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

  // Backup aur restore ke action cards banata hai.
  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Card(
      elevation: 2,
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
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(description),
            SizedBox(height: 15),
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
}
