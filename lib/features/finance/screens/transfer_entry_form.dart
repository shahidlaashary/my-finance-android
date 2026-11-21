import 'package:flutter/material.dart';
import 'package:my_finance/features/finance/screens/entry_form_base.dart';

class TransferEntryForm extends EntryFormBase {
  const TransferEntryForm({super.key});

  @override
  String get entryType => 'Transfer';

  @override
  State<TransferEntryForm> createState() => EntryFormBaseState<TransferEntryForm>();
}
