import 'package:flutter/material.dart';
import 'package:my_finance/features/finance/screens/entry_form_base.dart';

class IncomeEntryForm extends EntryFormBase {
  const IncomeEntryForm({super.key});

  @override
  String get entryType => 'Income';

  @override
  State<IncomeEntryForm> createState() => EntryFormBaseState<IncomeEntryForm>();
}
