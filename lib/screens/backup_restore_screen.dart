
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../main.dart';
import '../services/backup_service.dart';
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
  State<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState
    extends State<BackupRestoreScreen> {
  bool _isProcessing = false;
  bool _isLoadingPreferences = true;

  bool _automaticBackupEnabled = false;
  String _backupFrequency = 'weekly';

  DateTime? _lastAutomaticBackup;
  DateTime? _lastManualBackup;

  static const String _preferencesFileName =
      'my_finance_backup_preferences.json';

  static const String _automaticBackupFolder =
      'my_finance_automatic_backups';

  @override
  void initState() {
    super.initState();
    _loadPreferencesAndCheckBackup();
  }

  // --------------------------------------------------
  // BACKUP PREFERENCES
  // --------------------------------------------------

  Future<File> _getPreferencesFile() async {
    final directory =
        await getApplicationDocumentsDirectory();

    return File(
      p.join(
        directory.path,
        _preferencesFileName,
      ),
    );
  }

  Future<void> _loadPreferencesAndCheckBackup() async {
    try {
      final file = await _getPreferencesFile();

      if (await file.exists()) {
        final content = await file.readAsString();

        final decoded = jsonDecode(content);

        if (decoded is Map<String, dynamic>) {
          _automaticBackupEnabled =
              decoded['automatic_backup_enabled'] == true;

          final frequency =
              decoded['backup_frequency']?.toString();

          if ([
            'daily',
            'weekly',
            'monthly',
          ].contains(frequency)) {
            _backupFrequency = frequency!;
          }

          _lastAutomaticBackup = DateTime.tryParse(
            decoded['last_automatic_backup']?.toString() ?? '',
          );

          _lastManualBackup = DateTime.tryParse(
            decoded['last_manual_backup']?.toString() ?? '',
          );
        }
      }
    } catch (error) {
      debugPrint(
        'Backup preferences load error: $error',
      );
    }

    if (!mounted) return;

    setState(() {
      _isLoadingPreferences = false;
    });

    await _runAutomaticBackupIfDue();
  }

  Future<void> _savePreferences() async {
    final file = await _getPreferencesFile();

    final preferences = {
      'automatic_backup_enabled':
          _automaticBackupEnabled,
      'backup_frequency': _backupFrequency,
      'last_automatic_backup':
          _lastAutomaticBackup?.toIso8601String(),
      'last_manual_backup':
          _lastManualBackup?.toIso8601String(),
    };

    await file.parent.create(recursive: true);

    await file.writeAsString(
      jsonEncode(preferences),
      flush: true,
    );
  }

  Future<void> _updateAutomaticBackup(bool enabled) async {
    final previousValue = _automaticBackupEnabled;

    setState(() {
      _automaticBackupEnabled = enabled;
    });

    try {
      await _savePreferences();

      if (enabled) {
        // Create the first automatic backup immediately.
        await _runAutomaticBackupIfDue(force: true);
      } else {
        _showMessage('Automatic Backup disabled.');
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _automaticBackupEnabled = previousValue;
      });

      _showMessage(
        'Could not save backup preferences: $error',
        isError: true,
      );
    }
  }

  Future<void> _updateBackupFrequency(
    String? frequency,
  ) async {
    if (frequency == null) return;

    final previousValue = _backupFrequency;

    setState(() {
      _backupFrequency = frequency;
    });

    try {
      await _savePreferences();

      _showMessage(
        'Backup frequency updated.',
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _backupFrequency = previousValue;
      });

      _showMessage(
        'Could not save backup frequency: $error',
        isError: true,
      );
    }
  }

  bool _isAutomaticBackupDue() {
    if (_lastAutomaticBackup == null) {
      return true;
    }

    final now = DateTime.now();
    final last = _lastAutomaticBackup!;

    switch (_backupFrequency) {
      case 'daily':
        return now.difference(last).inDays >= 1;

      case 'weekly':
        return now.difference(last).inDays >= 7;

      case 'monthly':
        return now.year > last.year ||
            (now.year == last.year &&
                now.month > last.month);

      default:
        return false;
    }
  }

  Future<void> _runAutomaticBackupIfDue({
    bool force = false,
  }) async {
    if (!_automaticBackupEnabled ||
        _isProcessing ||
        (!force && !_isAutomaticBackupDue())) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final database = FinanceDB.instance.db;

      final Uint8List backupBytes =
          await BackupService.createBackup(
        database: database,
      );

      final documentsDirectory =
          await getApplicationDocumentsDirectory();

      final backupDirectory = Directory(
        p.join(
          documentsDirectory.path,
          _automaticBackupFolder,
        ),
      );

      await backupDirectory.create(
        recursive: true,
      );

      final now = DateTime.now();

      final timestamp =
          '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}-'
          '${now.minute.toString().padLeft(2, '0')}-'
          '${now.second.toString().padLeft(2, '0')}';

      final backupFile = File(
        p.join(
          backupDirectory.path,
          'My_Finance_Auto_Backup_$timestamp.zip',
        ),
      );

      await backupFile.writeAsBytes(
        backupBytes,
        flush: true,
      );

      _lastAutomaticBackup = now;

      await _savePreferences();

      if (mounted) {
        _showMessage(
          'Automatic backup created successfully.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Automatic backup failed: $error',
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

  // --------------------------------------------------
  // MANUAL BACKUP
  // --------------------------------------------------

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
        _lastManualBackup = DateTime.now();

        try {
          await _savePreferences();
        } catch (error) {
          debugPrint(
            'Manual backup date save error: $error',
          );
        }

        _showMessage(
          'Backup created successfully.',
        );
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

  // --------------------------------------------------
  // RESTORE BACKUP
  // --------------------------------------------------

  Future<void> _selectAndRestoreBackup() async {
    if (_isProcessing) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select My Finance Backup',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );

      if (!mounted ||
          result == null ||
          result.files.isEmpty) {
        return;
      }

      final selectedFile = result.files.single;

      Uint8List? backupBytes = selectedFile.bytes;

      if (backupBytes == null &&
          selectedFile.path != null) {
        backupBytes = await File(
          selectedFile.path!,
        ).readAsBytes();
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

      try {
        // Close independent database connections.
        await TransactionsService.closeDatabase();
        await BudgetsService.closeDatabase();
        await GoalsService.closeDatabase();
        await RecurringTransactionsService.closeDatabase();
        await CategoryService.closeDatabase();
        await LoansService.closeDatabase();
        await AttachmentService.closeDatabase();

        // Close the main database connection.
        await FinanceDB.instance.close();

        // Restore database and attachment files.
        await BackupService.restoreBackup(
          backupBytes: backupBytes,
        );
      } finally {
        // Reopen the main database.
        await FinanceDB.instance.reopen();
      }

      if (!mounted) return;

      _showMessage(
        'Backup restored successfully. '
        'Your finance data has been updated.',
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

  // --------------------------------------------------
  // HELPERS
  // --------------------------------------------------

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Not available yet';
    }

    return DateFormat(
      'dd MMM yyyy, hh:mm a',
    ).format(date);
  }

  String _frequencyLabel(String frequency) {
    switch (frequency) {
      case 'daily':
        return 'Daily';

      case 'weekly':
        return 'Weekly';

      case 'monthly':
        return 'Monthly';

      default:
        return 'Weekly';
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red : Colors.green,
      ),
    );
  }

  // --------------------------------------------------
  // UI
  // --------------------------------------------------

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
              _buildHeader(),

              const SizedBox(height: 22),

              _buildBackupPreferencesCard(),

              const SizedBox(height: 22),

              _buildFeatureCard(
                icon: Icons.cloud_upload,
                title: 'Create Manual Backup',
                description:
                    'Save your finance database and attachments '
                    'as a ZIP file in your selected location.',
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
                    'ZIP backup to restore your finance data.',
                buttonText: 'Select Backup File',
                color: Colors.teal,
                onPressed: _selectAndRestoreBackup,
              ),

              const SizedBox(height: 22),

              _buildBackupHistoryCard(),

              const SizedBox(height: 20),

              _buildInformationCard(),
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

          if (_isLoadingPreferences)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
            'Manage automatic backups, create manual '
            'backups and restore your finance data safely.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupPreferencesCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.settings,
                  color: Colors.indigo,
                  size: 25,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Backup Preferences',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Automatic Backup',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Automatically create local backups '
                'when a backup is due.',
              ),
              value: _automaticBackupEnabled,
              onChanged: _isLoadingPreferences ||
                      _isProcessing
                  ? null
                  : _updateAutomaticBackup,
              activeThumbColor: Colors.indigo,
            ),

            const Divider(height: 20),

            const Text(
              'Backup Frequency',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _backupFrequency,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(
                  Icons.calendar_month,
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'daily',
                  child: Text('Daily'),
                ),
                DropdownMenuItem(
                  value: 'weekly',
                  child: Text('Weekly'),
                ),
                DropdownMenuItem(
                  value: 'monthly',
                  child: Text('Monthly'),
                ),
              ],
              onChanged: _isLoadingPreferences ||
                      _isProcessing
                  ? null
                  : _updateBackupFrequency,
            ),

            const SizedBox(height: 12),

            Text(
              'Automatic backups are saved inside the app. '
              'The schedule is checked when you open this screen.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupHistoryCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.history,
                  color: Colors.indigo,
                  size: 24,
                ),
                SizedBox(width: 10),
                Text(
                  'Backup History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            _buildHistoryRow(
              icon: Icons.cloud_done,
              title: 'Last Automatic Backup',
              value: _formatDate(_lastAutomaticBackup),
            ),

            const Divider(height: 24),

            _buildHistoryRow(
              icon: Icons.save,
              title: 'Last Manual Backup',
              value: _formatDate(_lastManualBackup),
            ),

            const SizedBox(height: 12),

            Text(
              'Frequency: ${_frequencyLabel(_backupFrequency)}',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: Colors.indigo,
          size: 21,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInformationCard() {
    return Container(
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
              'Keep your manual backup ZIP file in a safe '
              'location. Restoring a backup replaces your '
              'current finance database and attachments.\n\n'
              'Automatic backups are stored locally inside '
              'the app. They are not a substitute for keeping '
              'an external backup copy.',
              style: TextStyle(height: 1.5),
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
                  backgroundColor:
                      color.withValues(alpha: 0.12),
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
                onPressed:
                    _isProcessing ? null : onPressed,
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
