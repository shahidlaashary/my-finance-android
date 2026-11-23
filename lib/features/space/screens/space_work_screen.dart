import 'package:flutter/material.dart';
import 'package:my_finance/features/space/screens/work_records_screen.dart';

/// Combines the existing Agreements and Projects workflows under one My Space tab.
/// Each section keeps its own local records table and form behavior.
class SpaceWorkScreen extends StatefulWidget {
  const SpaceWorkScreen({super.key});

  @override
  State<SpaceWorkScreen> createState() => SpaceWorkScreenState();
}

class SpaceWorkScreenState extends State<SpaceWorkScreen> {
  final _projectsKey = GlobalKey<WorkRecordsScreenState>();
  final _agreementsKey = GlobalKey<WorkRecordsScreenState>();
  String _selectedWorkSection = 'projects';

  void showWorkSection(String section) {
    if (section != 'agreements' && section != 'projects') return;
    if (mounted) setState(() => _selectedWorkSection = section);
  }

  void refreshWorkRecords([String? section]) {
    if (section == null || section == 'projects') {
      _projectsKey.currentState?.refreshWorkRecords();
    }
    if (section == null || section == 'agreements') {
      _agreementsKey.currentState?.refreshWorkRecords();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'projects',
                icon: Icon(Icons.work_outline_rounded),
                label: Text('Projects'),
              ),
              ButtonSegment<String>(
                value: 'agreements',
                icon: Icon(Icons.handshake_outlined),
                label: Text('Agreements'),
              ),
            ],
            selected: {_selectedWorkSection},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) showWorkSection(selection.first);
            },
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedWorkSection == 'agreements' ? 1 : 0,
            children: [
              WorkRecordsScreen(key: _projectsKey, section: 'projects'),
              WorkRecordsScreen(key: _agreementsKey, section: 'agreements'),
            ],
          ),
        ),
      ],
    );
  }
}
