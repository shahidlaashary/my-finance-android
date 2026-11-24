import 'package:flutter/material.dart';
import 'package:my_finance/features/space/services/agreement_template_service.dart';

class AgreementTemplatesScreen extends StatefulWidget {
  const AgreementTemplatesScreen({super.key});
  @override
  State<AgreementTemplatesScreen> createState() => _AgreementTemplatesScreenState();
}

class _AgreementTemplatesScreenState extends State<AgreementTemplatesScreen> {
  Future<List<Map<String, Object?>>>? _templates;
  @override
  void initState() { super.initState(); _refresh(); }
  void _refresh() => setState(() => _templates = AgreementTemplateService.instance.getTemplates());

  Future<void> _edit([Map<String, Object?>? template]) async {
    final title = TextEditingController(text: template?['title']?.toString() ?? '');
    final agreementType = TextEditingController(text: template?['agreement_type']?.toString() ?? 'General');
    final body = TextEditingController(text: template?['body']?.toString() ?? AgreementTemplateService.builtInClauses);
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(template == null ? 'Create Template' : 'Edit Template'),
      content: SizedBox(width: 520, child: Form(key: key, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: agreementType, decoration: const InputDecoration(labelText: 'Agreement Type', border: OutlineInputBorder()),
            validator: (v) => v == null || v.trim().isEmpty ? 'Agreement type is required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Template Title', border: OutlineInputBorder()),
            validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: body, minLines: 8, maxLines: 14,
            decoration: const InputDecoration(labelText: 'Agreement Clauses', alignLabelWithHint: true, border: OutlineInputBorder()),
            validator: (v) => v == null || v.trim().isEmpty ? 'Clauses are required' : null),
          const SizedBox(height: 8),
          const Text('Placeholders: {{first_party}}, {{second_party}}, {{address}}, {{label_name}}, {{territory}}, {{term_years}}, {{agreement_date}}, {{signing_date}}',
            style: TextStyle(fontSize: 11)),
        ],
      )))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (key.currentState!.validate()) Navigator.pop(ctx, true);
        }, child: const Text('Save')),
      ],
    ));
    if (saved == true) {
      await AgreementTemplateService.instance.saveTemplate(
        id: template?['id'] as int?, title: title.text, agreementType: agreementType.text, body: body.text);
      _refresh();
    }
    title.dispose(); agreementType.dispose(); body.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agreement Templates')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New Template')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _templates,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Unable to load templates: ${snapshot.error}'));
        final rows = snapshot.data ?? [];
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            final isDefault = (row['is_default'] as int? ?? 0) == 1;
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
              title: Text(row['title']?.toString() ?? ''),
              subtitle: Text('${row['agreement_type'] ?? 'General'} • ${isDefault ? 'Built-in template' : 'Custom template'}'),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  try {
                    if (action == 'edit') await _edit(row);
                    if (action == 'duplicate') {
                      await AgreementTemplateService.instance.duplicateTemplate(row['id'] as int);
                      _refresh();
                    }
                    if (action == 'delete') {
                      await AgreementTemplateService.instance.deleteTemplate(row['id'] as int);
                      _refresh();
                    }
                  } catch (error) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                  if (!isDefault) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
              onTap: () => _edit(row),
            ));
          },
        );
      },
    ),
  );
}
