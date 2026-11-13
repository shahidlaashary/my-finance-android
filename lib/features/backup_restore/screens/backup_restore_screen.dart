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
        content: Text(appText(context, "Restore karne se mojooda finance database aur attachments backup wali files se replace ho jayengi. Is ke baad ki tabdeeliyan zaya ho sakti hain. Kya aap jari rakhna chahte hain?", "بیک اپ بحال کرنے سے موجودہ ڈیٹابیس اور منسلک فائلیں بدل جائیں گی اور بعد کی تبدیلیاں ضائع ہو سکتی ہیں۔ کیا آپ جاری رکھنا چاہتے ہیں؟"),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary.withOpacity(0.13), Theme.of(context).colorScheme.primary.withOpacity(0.04)]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      Container(width: 48, height: 48, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.shield_outlined, size: 27, color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(appText(context, 'Protect Your Finance Data', 'Protect Your Finance Data'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(appText(context, 'Keep your records safe with regular backups.', 'Keep your records safe with regular backups.'), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 9),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                      child: Column(children: [
                        Row(children: [
                          Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.autorenew_rounded, color: Colors.teal)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(appText(context, 'Automatic Local Backup', 'Automatic Local Backup'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            Text(appText(context, 'Daily backup on this device', 'Daily backup on this device'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ])),
                          Switch.adaptive(value: _automaticEnabled, onChanged: _isProcessing ? null : _toggleAutomaticBackup),
                        ]),
                        const Divider(height: 13),
                        Row(children: [
                          Expanded(child: Text(_lastAutomaticBackup == null ? 'Last backup: Not yet' : 'Last backup: ${DateFormat('d MMM, h:mm a').format(_lastAutomaticBackup!)}', style: const TextStyle(fontSize: 11))),
                          TextButton.icon(onPressed: _isProcessing ? null : _createAutomaticBackupNow, icon: const Icon(Icons.backup_rounded, size: 17), label: Text(appText(context, 'Back Up Now', 'ابھی بیک اپ لیں')), style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8))),
                        ]),
                        if (_automaticStatus == 'failed') const Align(alignment: Alignment.centerLeft, child: Text('Last backup failed. Try again.', style: TextStyle(color: Colors.red, fontSize: 11))),
                        const Align(alignment: Alignment.centerLeft, child: Text('Keeps 7 newest backups. A due backup runs when the app starts.', style: TextStyle(fontSize: 10, color: Colors.grey))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _buildActionCard(icon: Icons.cloud_upload_rounded, title: appText(context, 'Create Backup', 'دستی بیک اپ بنائیں'), description: 'Save database and attachments as a ZIP file.', buttonText: 'Create Backup', color: Colors.indigo, onPressed: _createBackup)),
                    const SizedBox(width: 9),
                    Expanded(child: _buildActionCard(icon: Icons.settings_backup_restore_rounded, title: appText(context, 'Restore Backup', 'بیک اپ بحال کریں'), description: 'Restore from an existing My Finance ZIP file.', buttonText: 'Select ZIP File', color: Colors.teal, onPressed: _selectAndRestoreBackup)),
                  ])),
                  const SizedBox(height: 9),
                  Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.09), borderRadius: BorderRadius.circular(12)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(appText(context, 'Important: Restoring replaces current database and attachments with the selected backup.', 'اہم: بحالی سے موجودہ ڈیٹابیس اور منسلک فائلیں منتخب بیک اپ سے تبدیل ہو جائیں گی۔'), style: const TextStyle(fontSize: 10.5, height: 1.25))),
                  ])),
                ],
              ),
            ),
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
      margin: EdgeInsets.zero,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 39, height: 39, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
            const SizedBox(height: 9),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Expanded(child: Text(description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Colors.grey, height: 1.25))),
            const SizedBox(height: 7),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _isProcessing ? null : onPressed, style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10), textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), child: Text(buttonText, maxLines: 1, overflow: TextOverflow.ellipsis))),
          ],
        ),
      ),
    );
  }
}
