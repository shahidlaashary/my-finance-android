import 'package:flutter/material.dart';
import 'package:my_finance/features/finance/screens/entry_form_base.dart';

class ExpenseEntryForm extends EntryFormBase {
  const ExpenseEntryForm({super.key});

  @override
  String get entryType => 'Expense';

  @override
  State<ExpenseEntryForm> createState() => EntryFormBaseState<ExpenseEntryForm>();
}
