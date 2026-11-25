import 'package:my_finance/features/space/services/my_space_service.dart';

/// Local editable templates for Agreements. The built-in Music Rights Agreement
/// follows the user's supplied LOR samples; clauses remain editable by the user.
class AgreementTemplateService {
  AgreementTemplateService._();
  static final instance = AgreementTemplateService._();

  static const defaultTitle = 'Music Rights Agreement';

  Future<List<Map<String, Object?>>> getTemplates() async {
    final db = await MySpaceService.instance.database;
    return db.query('space_agreement_templates', orderBy: 'is_default DESC, title COLLATE NOCASE');
  }

  Future<int> saveTemplate({
    int? id,
    required String title,
    required String agreementType,
    required String body,
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty) throw const FormatException('Template title is required.');
    if (cleanBody.isEmpty) throw const FormatException('Template clauses are required.');
    final db = await MySpaceService.instance.database;
    final now = DateTime.now().toIso8601String();
    if (id == null) {
      return db.insert('space_agreement_templates', {
        'title': cleanTitle,
        'agreement_type': agreementType.trim(),
        'body': cleanBody,
        'is_default': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.update('space_agreement_templates', {
      'title': cleanTitle,
      'agreement_type': agreementType.trim(),
      'body': cleanBody,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<int> duplicateTemplate(int id) async {
    final db = await MySpaceService.instance.database;
    final rows = await db.query('space_agreement_templates', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('Template not found.');
    final source = rows.first;
    final title = '${source['title']} (Copy)';
    return db.insert('space_agreement_templates', {
      'title': title,
      'agreement_type': source['agreement_type'] ?? 'General',
      'body': source['body'],
      'is_default': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteTemplate(int id) async {
    final db = await MySpaceService.instance.database;
    final rows = await db.query('space_agreement_templates', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    if ((rows.first['is_default'] as int? ?? 0) == 1) {
      throw StateError('The built-in template cannot be deleted.');
    }
    await db.delete('space_agreement_templates', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, Object?>?> getTemplate(int id) async {
    final rows = await (await MySpaceService.instance.database).query(
      'space_agreement_templates', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static const builtInClauses = '''1. This is to certify that I, {{first_party}}, residing at {{address}}, and duly authorized signatory for the content listed in this agreement, authorize {{label_name}} as a Digital Content Partner to distribute and administer the content on national and international platforms for the territories stated below.

2. I am the Artist, producer and copyright owner of the content and the track(s) listed in this agreement. The listed material is my own copyrighted material.

3. No other service provider or party is authorized to sell or offer this content to any platform or claim any rights for the content.

4. I authorize the rights for the track(s) listed below to be distributed and released worldwide.

5. All rights of this content, including Audio/Visual, FM Radio, Cable Network, Television Channel Broadcasting, Publishing, Physical/Digital Formats, Mobile Ring Back Tones (CRBTs) and future formats worldwide, are granted to the Label. No other service provider or party is authorized to sell or offer the content to any platform or claim any rights.

6. I accept that if any rights violations or online disputes are found, I will be responsible for the legal and financial consequences arising from the same.

7. This agreement is valid for {{term_years}} years from the Signing Date ({{signing_date}}).''';

  static const placeholders = [
    '{{first_party}}', '{{second_party}}', '{{address}}', '{{label_name}}',
    '{{territory}}', '{{term_years}}', '{{agreement_date}}', '{{signing_date}}',
  ];
}
