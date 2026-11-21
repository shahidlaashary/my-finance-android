import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';

class AssetValuationEntryForm extends StatefulWidget {
  final AssetsModel asset;
  const AssetValuationEntryForm({super.key, required this.asset});
  @override
  State<AssetValuationEntryForm> createState() => _AssetValuationEntryFormState();
}

class _AssetValuationEntryFormState extends State<AssetValuationEntryForm> {
  late final TextEditingController _value;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(text: widget.asset.currentValue.toString());
  }

  @override
  void dispose() { _value.dispose(); super.dispose(); }

  Future<void> _save() async {
    final value = double.tryParse(_value.text.trim());
    if (value == null || !value.isFinite || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid current value.')));
      return;
    }
    if (widget.asset.id == null) return;
    setState(() => _saving = true);
    try {
      await AssetsService().updateCurrentValue(widget.asset.id!, value);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(appText(context, 'Update Current Value', 'موجودہ قیمت اپ ڈیٹ کریں')),
    content: TextField(
      controller: _value,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: appText(context, 'New Current Value', 'New Current Value')),
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(appText(context, 'Cancel', 'منسوخ کریں'))),
      FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(appText(context, 'Update', 'اپ ڈیٹ کریں'))),
    ],
  );
}
