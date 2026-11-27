import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../application/services/studio_ai_music_service.dart';
import '../../domain/entities/studio_ai_music_project.dart';
import '../../domain/entities/studio_ai_voice_profile.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';

class StudioAiMusicScreen extends StatefulWidget {
  const StudioAiMusicScreen({super.key});

  @override
  State<StudioAiMusicScreen> createState() => _StudioAiMusicScreenState();
}

class _StudioAiMusicScreenState extends State<StudioAiMusicScreen> {
  final _service = StudioAiMusicService();
  final _storage = StudioStorageManager();
  final _title = TextEditingController();
  final _prompt = TextEditingController();
  final _lyrics = TextEditingController();

  static const _genres = ['Pop', 'Rock', 'Classical', 'Qawwali', 'Folk', 'Hip-hop', 'Electronic', 'Acoustic', 'Other'];
  static const _languages = ['Urdu', 'English', 'Punjabi', 'Arabic', 'Hindi', 'Other'];
  static const _moods = ['Romantic', 'Sad', 'Happy', 'Energetic', 'Peaceful', 'Cinematic', 'Other'];

  String _genre = 'Pop';
  String _language = 'Urdu';
  String _mood = 'Romantic';
  String? _voiceId;
  List<StudioAiMusicProject> _projects = const [];
  List<StudioAiVoiceProfile> _voices = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _service.listProjects(),
        _service.listVoiceProfiles(),
      ]);
      if (!mounted) return;
      setState(() {
        _projects = values[0] as List<StudioAiMusicProject>;
        _voices = values[1] as List<StudioAiVoiceProfile>;
        if (_voiceId != null && !_voices.any((v) => v.id == _voiceId)) {
          _voiceId = null;
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _saveDraft() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _service.createProject(
        title: _title.text,
        prompt: _prompt.text,
        lyrics: _lyrics.text,
        genre: _genre,
        language: _language,
        mood: _mood,
        voiceProfileId: _voiceId,
      );
      _title.clear();
      _prompt.clear();
      _lyrics.clear();
      if (!mounted) return;
      _message('Song project saved as a draft.');
      await _load();
    } catch (error) {
      if (mounted) _message('Could not save project: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addVoiceProfile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      withData: false,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;
    final sourcePath = picked.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      _message('The selected audio sample could not be accessed.');
      return;
    }

    final nameController = TextEditingController();
    final ownerController = TextEditingController();
    var consent = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create authorized voice profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Voice profile name',
                    hintText: 'e.g. My singing voice',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ownerController,
                  decoration: const InputDecoration(
                    labelText: 'Voice owner name',
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: consent,
                  onChanged: (value) => setDialogState(() => consent = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I confirm this is my voice, or I have explicit permission from its owner to create and use this AI voice profile.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  'The permission record is stored with this profile. Do not upload another person’s voice without their permission.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: consent && nameController.text.trim().isNotEmpty && ownerController.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Save profile'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || accepted != true) {
      nameController.dispose();
      ownerController.dispose();
      return;
    }

    try {
      final id = 'voice-${DateTime.now().microsecondsSinceEpoch}';
      final extension = p.extension(sourcePath).isEmpty ? '.audio' : p.extension(sourcePath);
      final destination = await _storage.allocateMediaFile(
        id: id,
        extension: extension,
        isVideo: false,
      );
      await File(sourcePath).copy(destination.path);
      await _service.addVoiceProfile(
        displayName: nameController.text,
        ownerName: ownerController.text,
        samplePath: destination.path,
        consentScope: 'AI singing generation in Studio; owner-confirmed permission',
      );
      if (!mounted) return;
      _message('Authorized voice sample added.');
      await _load();
    } catch (error) {
      if (mounted) _message('Voice profile could not be saved: $error');
    } finally {
      nameController.dispose();
      ownerController.dispose();
    }
  }

  Future<void> _revokeVoice(StudioAiVoiceProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke voice permission?'),
        content: Text('This will disable "${profile.displayName}" and detach it from saved drafts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Revoke')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.revokeVoiceConsent(profile.id);
    if (!mounted) return;
    setState(() {
      _voices = _voices.where((item) => item.id != profile.id).toList();
      if (_voiceId == profile.id) _voiceId = null;
    });
    _message('Voice permission revoked.');
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _choice(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: options.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Music Studio'),
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline_rounded, size: 42),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          colors: [colors.primaryContainer, colors.surfaceContainerHighest],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.auto_awesome_rounded, size: 30),
                        const SizedBox(height: 10),
                        Text('Create music from your ideas', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          'Prepare song projects, lyrics, musical direction and authorized voice samples.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Text('New song project', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Song title', border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _prompt,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Describe the song',
                        hintText: 'Romantic Urdu ballad with soft acoustic guitar...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _lyrics,
                      minLines: 3,
                      maxLines: 7,
                      decoration: const InputDecoration(
                        labelText: 'Lyrics (optional if description is provided)',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _choice('Genre', _genre, _genres, (v) => setState(() => _genre = v ?? _genre))),
                      const SizedBox(width: 10),
                      Expanded(child: _choice('Language', _language, _languages, (v) => setState(() => _language = v ?? _language))),
                    ]),
                    const SizedBox(height: 10),
                    _choice('Mood', _mood, _moods, (v) => setState(() => _mood = v ?? _mood)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: _voiceId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Authorized voice profile', border: OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Default / no custom voice')),
                        ..._voices.map((voice) => DropdownMenuItem<String?>(
                          value: voice.id,
                          child: Text('${voice.displayName} • ${voice.ownerName}', overflow: TextOverflow.ellipsis),
                        )),
                      ],
                      onChanged: (value) => setState(() => _voiceId = value),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveDraft,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('Save song draft'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate song — AI engine not connected yet'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Song generation, singing synthesis and mastering will become active after a licensed AI generation provider or self-hosted model is connected. Saving a draft does not create audio.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 22),
                    Row(children: [
                      Expanded(child: Text('Voice Lab', style: Theme.of(context).textTheme.titleMedium)),
                      TextButton.icon(
                        onPressed: _addVoiceProfile,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add sample'),
                      ),
                    ]),
                    Text(
                      'Voice samples are stored in Studio private storage. A profile requires an explicit permission confirmation and can be revoked.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    if (_voices.isEmpty)
                      const Card(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No authorized voice profiles yet. Add your own voice sample or a sample you have permission to use.'),
                      ))
                    else
                      ..._voices.map((voice) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.record_voice_over_outlined)),
                          title: Text(voice.displayName),
                          subtitle: Text('Owner: ${voice.ownerName}\nConsent recorded', maxLines: 2),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'revoke') _revokeVoice(voice);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'revoke', child: Text('Revoke permission')),
                            ],
                          ),
                        ),
                      )),
                    const SizedBox(height: 22),
                    Text('Song projects', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_projects.isEmpty)
                      const Card(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Your saved song drafts will appear here.'),
                      ))
                    else
                      ..._projects.map((project) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
                          title: Text(project.title),
                          subtitle: Text('${project.genre} • ${project.language} • ${project.mood}'),
                          trailing: Chip(label: Text(project.status.toUpperCase())),
                        ),
                      )),
                  ],
                ),
    );
  }
}
