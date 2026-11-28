import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../application/services/studio_media_import_service.dart';
import '../application/services/studio_media_library_service.dart';
import '../domain/entities/studio_media_file.dart';
import '../infrastructure/storage/studio_storage_manager.dart';

class StudioRecordingScreen extends StatefulWidget {
  const StudioRecordingScreen({super.key});

  @override
  State<StudioRecordingScreen> createState() => _StudioRecordingScreenState();
}

class _StudioRecordingScreenState extends State<StudioRecordingScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final StudioStorageManager _storage = StudioStorageManager();
  final StudioMediaLibraryService _library = StudioMediaLibraryService();
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  bool _recording = false;
  bool _saving = false;
  Duration _elapsed = Duration.zero;
  String? _activePath;
  String? _error;
  StudioMediaFile? _lastRecording;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _format(Duration value) {
    final hours = value.inHours.toString().padLeft(2, '0');
    final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Future<void> _startRecording() async {
    if (_recording || _saving) return;
    try {
      final allowed = await _recorder.hasPermission();
      if (!mounted) return;
      if (!allowed) {
        setState(() => _error = 'Microphone permission is required to record audio.');
        return;
      }
      final id = 'studio_recording_${DateTime.now().microsecondsSinceEpoch}';
      final file = await _storage.allocateMediaFile(
        id: id,
        extension: '.wav',
        isVideo: false,
      );
      if (!mounted) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Best-effort cleanup when the user leaves during file allocation.
        }
        return;
      }
      // Keep the allocated path so a failed start can clean up its partial file.
      _activePath = file.path;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: file.path,
      );
      if (!mounted) {
        try {
          await _recorder.stop();
        } catch (_) {
          // The recorder may already have been disposed during navigation.
        }
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Best-effort cleanup; diagnostics can report an orphaned file.
        }
        _activePath = null;
        return;
      }
      _stopwatch
        ..reset()
        ..start();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed = _stopwatch.elapsed);
      });
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
        _error = null;
        _lastRecording = null;
      });
    } catch (error) {
      // A native start can fail after partially opening the recorder. Stop it
      // before deleting the output path so the file is not still being written.
      try {
        await _recorder.stop();
      } catch (_) {
        // The recorder may not have started; preserve the original error.
      }
      final path = _activePath;
      if (path != null) {
        try {
          final partial = File(path);
          if (await partial.exists()) await partial.delete();
        } catch (_) {
          // Keep the original start error visible; storage diagnostics can
          // report any file that could not be cleaned up.
        }
      }
      _activePath = null;
      if (mounted) setState(() {
        _recording = false;
        _error = 'Could not start recording: $error';
      });
    }
  }

  Future<void> _stopAndSave() async {
    if (_saving || (!_recording && _activePath == null)) return;
    setState(() => _saving = true);
    _ticker?.cancel();
    _stopwatch.stop();
    try {
      final path = _recording ? await _recorder.stop() : null;
      final sourcePath = path ?? _activePath;
      if (sourcePath == null || !await File(sourcePath).exists()) {
        throw StateError('The recording file was not created.');
      }
      final imported = await StudioMediaImportService(
        storageManager: _storage,
        mediaLibrary: _library,
      ).importFile(
        sourcePath: sourcePath,
        mediaType: StudioMediaType.audio,
      );
      String? cleanupWarning;
      try {
        await File(sourcePath).delete();
      } catch (error) {
        // The imported Media Library copy is already registered. Do not treat
        // temporary-file cleanup failure as an import failure or retry import.
        cleanupWarning = 'Recording saved, but its temporary file could not be removed: $error';
      }
      if (!mounted) return;
      setState(() {
        _lastRecording = imported;
        _recording = false;
        _saving = false;
        _activePath = null;
        _elapsed = _stopwatch.elapsed;
        _error = cleanupWarning;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cleanupWarning == null
            ? 'Recording saved to Media Library.'
            : 'Recording saved. Temporary cleanup needs attention.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _saving = false;
        // Keep the managed recording path so the user can retry saving or
        // explicitly discard it instead of losing access to the recording.
        _error = 'Recording could not be saved: $error';
      });
    }
  }

  Future<void> _discardRecording() async {
    if (_saving) return;
    try {
      if (_recording) {
        await _recorder.stop();
        // Stop succeeded: even if file deletion fails below, expose Retry Save
        // rather than leaving controls in a recording state.
        _recording = false;
        _ticker?.cancel();
        _stopwatch.stop();
      }
      final path = _activePath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      _ticker?.cancel();
      _stopwatch
        ..stop()
        ..reset();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _activePath = null;
        _elapsed = Duration.zero;
        _error = null;
      });
    } catch (error) {
      // Keep the path and recording controls available so a failed discard
      // never silently loses the user's only remaining copy.
      if (!mounted) return;
      setState(() {
        _error = 'Could not discard recording: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Recording Workspace')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: (_recording ? colors.error : colors.primary)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _recording ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                    size: 36,
                    color: _recording ? colors.error : colors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _format(_elapsed),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [],
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 7),
                Text(
                  _recording ? 'RECORDING IN PROGRESS' : 'READY TO RECORD',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: _recording ? colors.error : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                ),
                const SizedBox(height: 24),
                if (!_recording && _activePath == null)
                  FilledButton.icon(
                    onPressed: _saving ? null : _startRecording,
                    icon: const Icon(Icons.fiber_manual_record_rounded),
                    label: const Text('Start Recording'),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _saving ? null : _stopAndSave,
                        icon: Icon(_recording ? Icons.stop_rounded : Icons.save_rounded),
                        label: Text(_recording ? 'Stop & Save' : 'Retry Save'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _discardRecording,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Discard'),
                      ),
                    ],
                  ),
                if (_saving) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  const Text('Saving recording to Studio Media Library…'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recording format',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  const _InfoRow(label: 'Format', value: 'WAV / PCM'),
                  const _InfoRow(label: 'Sample rate', value: '44.1 kHz'),
                  const _InfoRow(label: 'Channels', value: 'Mono'),
                  const _InfoRow(label: 'Storage', value: 'Private Studio storage'),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(color: colors.error)),
          ],
          if (_lastRecording != null) ...[
            const SizedBox(height: 18),
            Text('Latest recording',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.audio_file_rounded),
                title: Text(_lastRecording!.originalName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${(_lastRecording!.fileSizeBytes / 1024).toStringAsFixed(1)} KB • WAV',
                ),
                trailing: const Icon(Icons.check_circle_rounded),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Recordings are saved as managed audio files and appear in Media Library for identification, comparison and catalogue linking.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
