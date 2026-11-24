import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Creates a printable Legal-size agreement PDF from the saved template
/// snapshot. The user's saved document is never re-rendered from a later edit
/// to the template library.
class AgreementPdfService {
  AgreementPdfService._();
  static final instance = AgreementPdfService._();

  String _value(Map<String, Object?> data, String key, [String fallback = '']) {
    final value = data[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  String renderClauses(Map<String, Object?> data) {
    var body = _value(data, 'template_body_snapshot',
        'Agreement terms have not been added.');
    final replacements = <String, String>{
      '{{first_party}}': _value(data, 'party_one', '[First Party]'),
      '{{second_party}}': _value(data, 'party_two', '[Second Party]'),
      '{{address}}': _value(data, 'address', '[Address]'),
      '{{label_name}}': _value(data, 'label_name', '[Label]'),
      '{{territory}}': _value(data, 'territory', 'Worldwide'),
      '{{term_years}}': _value(data, 'term_years', '10'),
      '{{agreement_date}}': _value(data, 'agreement_date', '[Date]'),
    };
    replacements.forEach((key, value) => body = body.replaceAll(key, value));
    return body;
  }

  Future<Uint8List> build(Map<String, Object?> data) async {
    final document = pw.Document();
    final title = _value(data, 'template_title_snapshot', 'Music Rights Agreement');
    final clauses = renderClauses(data);
    final tracks = _value(data, 'track_details');
    final trackRows = tracks.split('\n').map((line) => line.trim())
        .where((line) => line.isNotEmpty).toList();
    final clauseParts = clauses.split('{{track_details_table}}');
    final trackTable = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Track Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey700, width: .6),
        columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(4)},
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: ['Sr.', 'Track Details'].map((v) =>
              pw.Padding(padding: const pw.EdgeInsets.all(6),
                child: pw.Text(v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))).toList()),
          ...trackRows.asMap().entries.map((entry) => pw.TableRow(children: [
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${entry.key + 1}')),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(entry.value)),
          ])),
        ],
      ),
      pw.SizedBox(height: 16),
    ]);

    pw.Widget field(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TextSpan(text: value.isEmpty ? '—' : value),
      ])),
    );

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.legal,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
      build: (context) => [
        pw.Center(child: pw.Text(title,
          style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold,
            decoration: pw.TextDecoration.underline))),
        pw.SizedBox(height: 20),
        field('Agreement Date', _value(data, 'agreement_date')),
        field('First Party / Artist', _value(data, 'party_one')),
        field('Second Party / Label', _value(data, 'party_two')),
        field('Label Name', _value(data, 'label_name')),
        field('Address', _value(data, 'address')),
        field('Territory', _value(data, 'territory', 'Worldwide')),
        field('Term', '${_value(data, 'term_years', '10')} years'),
        pw.SizedBox(height: 12),
        pw.Text('Terms and Conditions', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        pw.SizedBox(height: 8),
        ...clauseParts.asMap().entries.expand((part) => <pw.Widget>[
          ...part.value.split(RegExp(r'(?=\\d+\\.\\s)')).where((s) => s.trim().isNotEmpty).map((clause) =>
            pw.Padding(padding: const pw.EdgeInsets.only(bottom: 9),
              child: pw.Text(clause.trim(), textAlign: pw.TextAlign.justify,
                style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3)))),
          if (part.key < clauseParts.length - 1 && trackRows.isNotEmpty) trackTable,
        ]),
        pw.SizedBox(height: 28),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Name: ${_value(data, 'party_one')}'),
            pw.SizedBox(height: 8),
            if (_value(data, 'signature_data').isNotEmpty)
              pw.Image(pw.MemoryImage(base64Decode(_value(data, 'signature_data'))), width: 145, height: 48, fit: pw.BoxFit.contain),
            pw.SizedBox(height: 8),
            pw.Text('Designation: ${_value(data, 'designation', 'Artist / Producer / Owner')}'),
            pw.SizedBox(height: 28),
            pw.Container(width: 180, height: 1, color: PdfColors.black),
            pw.Text('Signature of First Party', style: const pw.TextStyle(fontSize: 9)),
          ])),
          pw.SizedBox(width: 24),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Name: ${_value(data, 'party_two')}'),
            pw.SizedBox(height: 25),
            pw.Text('Date: ${_value(data, 'agreement_date')}'),
            pw.SizedBox(height: 28),
            pw.Container(width: 180, height: 1, color: PdfColors.black),
            pw.Text('Signature of Second Party', style: const pw.TextStyle(fontSize: 9)),
          ])),
        ]),
        pw.SizedBox(height: 28),
        pw.Text('Witness: ${_value(data, 'witness_name', '____________________________')}'),
        pw.SizedBox(height: 25),
        pw.Text('Stamp / E-Stamp: Attach the applicable stamp document separately.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    ));
    return document.save();
  }

  Future<void> printAgreement(Map<String, Object?> data) async {
    final bytes = await build(data);
    await Printing.layoutPdf(onLayout: (_) async => bytes,
      name: '${_value(data, 'title', 'Music Rights Agreement')}.pdf');
  }

  Future<void> shareAgreement(Map<String, Object?> data) async {
    final bytes = await build(data);
    final safeName = _value(data, 'title', 'Music Rights Agreement')
      .replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim().replaceAll(' ', '_');
    await Printing.sharePdf(bytes: bytes,
      filename: '${safeName.isEmpty ? 'Music_Rights_Agreement' : safeName}.pdf');
  }
}
