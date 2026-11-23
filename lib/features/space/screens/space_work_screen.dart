import 'package:flutter/material.dart';
import 'package:my_finance/features/space/screens/space_records_screen.dart';

/// Combines the existing Deals and Projects workflows under one My Space tab.
/// Each section keeps its own local records table and form behavior.
class SpaceWorkScreen extends StatefulWidget {
  const SpaceWorkScreen({super.key});

  @override
  State<SpaceWorkScreen> createState() => SpaceWorkScreenState();
}

class SpaceWorkScreenState extends State<SpaceWorkScreen> {
  final _projectsKey = GlobalKey<SpaceRecordsScreenState>();
  final _dealsKey = GlobalKey<SpaceRecordsScreenState>();
  String _section = 'projects';

  void showSection(String section) {
    if (section != 'deals' && section != 'projects') return;
    if (mounted) setState(() => _section = section);
  }

  void refresh([String? section]) {
    if (section == null || section == 'projects') {
      _projectsKey.currentState?.refresh();
    }
    if (section == null || section == 'deals') {
      _dealsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
                value: 'deals',
                icon: Icon(Icons.handshake_outlined),
                label: Text('Deals'),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) showSection(selection.first);
            },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? colors.onPrimary : colors.onSurface),
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? colors.primary : colors.surface),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _section == 'deals' ? 1 : 0,
            children: [
              SpaceRecordsScreen(key: _projectsKey, section: 'projects'),
              SpaceRecordsScreen(key: _dealsKey, section: 'deals'),
            ],
          ),
        ),
      ],
    );
  }
}
