import 'package:flutter/material.dart';
import 'package:my_finance/modules/space/screens/agreements_screen.dart';

/// My Space ke Work tab mein agreements workspace dikhata hai.
class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key});

  @override
  State<WorkScreen> createState() => WorkScreenState();
}

class WorkScreenState extends State<WorkScreen> {
  final _agreementsKey = GlobalKey<AgreementsScreenState>();

  void refreshAgreements() => _agreementsKey.currentState?.refreshAgreements();

  @override
  Widget build(BuildContext context) =>
      AgreementsScreen(key: _agreementsKey);
}
