import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VehicleExportService {
  VehicleExportService._();

  static Future<File> _save(String name, List<int> bytes) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'VehicleReports'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _cell(dynamic value) => (value ?? '').toString();
  static String _xml(String value) => value
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;').replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Future<File> exportExcel({
    required List<Map<String, dynamic>> vehicles,
    required List<Map<String, dynamic>> fuel,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> reminders,
  }) async {
    final sheets = <String, List<List<String>>>{
      'Vehicles': [
        ['Vehicle', 'Type', 'Make / Model', 'Registration', 'Fuel Type', 'Purchase Date', 'Purchase Price'],
        ...vehicles.map((v) => [_cell(v['name']), _cell(v['type']), _cell(v['model']), _cell(v['registration']), _cell(v['fuel_type']), _cell(v['purchase_date']), _cell(v['purchase_price'])]),
      ],
      'Fuel Log': [
        ['Vehicle ID', 'Date', 'Odometer KM', 'Quantity', 'Unit', 'Unit Price', 'Total', 'Full Tank', 'Station'],
        ...fuel.map((v) => [_cell(v['vehicle_id']), _cell(v['date']), _cell(v['odometer']), _cell(v['quantity']), _cell(v['unit']), _cell(v['unit_price']), _cell(v['total']), _cell(v['full_tank']), _cell(v['station'])]),
      ],
      'Expenses': [
        ['Vehicle ID', 'Date', 'Category', 'Amount', 'Odometer KM', 'Vendor', 'Notes'],
        ...expenses.map((v) => [_cell(v['vehicle_id']), _cell(v['date']), _cell(v['category']), _cell(v['amount']), _cell(v['odometer']), _cell(v['vendor']), _cell(v['notes'])]),
      ],
      'Reminders': [
        ['Vehicle ID', 'Title', 'Due Date', 'Due Odometer KM', 'Notes'],
        ...reminders.map((v) => [_cell(v['vehicle_id']), _cell(v['title']), _cell(v['due_date']), _cell(v['due_odometer']), _cell(v['notes'])]),
      ],
    };

    String column(int n) {
      var value = n + 1;
      var out = '';
      while (value > 0) {
        final rem = (value - 1) % 26;
        out = String.fromCharCode(65 + rem) + out;
        value = (value - 1) ~/ 26;
      }
      return out;
    }

    final archive = Archive();
    final sheetNames = sheets.keys.toList();
    final contentTypes = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>');
    for (var i = 0; i < sheetNames.length; i++) {
      contentTypes.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    contentTypes.write('</Types>');
    archive.addFile(ArchiveFile('[Content_Types].xml', utf8.encode(contentTypes.toString()).length, utf8.encode(contentTypes.toString())));
    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';
    archive.addFile(ArchiveFile('_rels/.rels', utf8.encode(rootRels).length, utf8.encode(rootRels)));
    final workbook = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>');
    final rels = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 0; i < sheetNames.length; i++) {
      workbook.write('<sheet name="${_xml(sheetNames[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
      rels.write('<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>');
    }
    workbook.write('</sheets></workbook>');
    rels.write('</Relationships>');
    final wbBytes = utf8.encode(workbook.toString());
    final relBytes = utf8.encode(rels.toString());
    archive.addFile(ArchiveFile('xl/workbook.xml', wbBytes.length, wbBytes));
    archive.addFile(ArchiveFile('xl/_rels/workbook.xml.rels', relBytes.length, relBytes));
    const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="1"><xf xfId="0"/></cellXfs></styleSheet>';
    final styleBytes = utf8.encode(styles);
    archive.addFile(ArchiveFile('xl/styles.xml', styleBytes.length, styleBytes));
    for (var s = 0; s < sheetNames.length; s++) {
      final rows = sheets[sheetNames[s]]!;
      final xml = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
      for (var r = 0; r < rows.length; r++) {
        xml.write('<row r="${r + 1}">');
        for (var c = 0; c < rows[r].length; c++) {
          final ref = '${column(c)}${r + 1}';
          xml.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_xml(rows[r][c])}</t></is></c>');
        }
        xml.write('</row>');
      }
      xml.write('</sheetData></worksheet>');
      final bytes = utf8.encode(xml.toString());
      archive.addFile(ArchiveFile('xl/worksheets/sheet${s + 1}.xml', bytes.length, bytes));
    }
    final zipped = ZipEncoder().encode(archive);
    return _save('vehicle_report_${DateTime.now().millisecondsSinceEpoch}.xlsx', zipped);
  }

  static Future<File> exportPdf({
    required List<Map<String, dynamic>> vehicles,
    required List<Map<String, dynamic>> fuel,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> reminders,
  }) async {
    final lines = <String>[
      'MY FINANCE - VEHICLE REPORT',
      'Generated: ${DateTime.now().toLocal()}',
      '',
      'VEHICLES',
      ...vehicles.map((v) => '${v['name']} | ${v['type']} | ${v['model']} | ${v['registration']}'),
      '',
      'FUEL LOG',
      ...fuel.map((v) => '${v['date']} | Vehicle #${v['vehicle_id']} | ${v['quantity']} ${v['unit']} x ${v['unit_price']} = ${v['total']} | Odo ${v['odometer']} km'),
      '',
      'VEHICLE EXPENSES',
      ...expenses.map((v) => '${v['date']} | Vehicle #${v['vehicle_id']} | ${v['category']} | ${v['amount']} | Odo ${v['odometer']} km'),
      '',
      'REMINDERS',
      ...reminders.map((v) => '${v['title']} | Due ${v['due_date']} | Odo ${v['due_odometer']}'),
    ];
    final safeLines = lines.map((line) {
      final out = StringBuffer();
      for (final rune in line.runes) {
        if (rune < 32 || rune > 126) {
          out.write('?');
          continue;
        }
        if (rune == 92 || rune == 40 || rune == 41) out.writeCharCode(92);
        out.writeCharCode(rune);
      }
      return out.toString();
    }).toList();
    const linesPerPage = 52;
    final pageCount = (safeLines.length / linesPerPage).ceil().clamp(1, 1000);
    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ];
    final pageRefs = <String>[];
    for (var page = 0; page < pageCount; page++) {
      final pageObject = 4 + page * 2;
      final contentObject = pageObject + 1;
      pageRefs.add('$pageObject 0 R');
      final pageLines = safeLines.skip(page * linesPerPage).take(linesPerPage).toList();
      final stream = StringBuffer('BT /F1 9 Tf 42 800 Td 12 TL ');
      for (var i = 0; i < pageLines.length; i++) {
        if (i > 0) stream.write('T* ');
        stream.write('(${pageLines[i]}) Tj ');
      }
      stream.write('ET');
      objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents $contentObject 0 R >>');
      objects.add('<< /Length ${latin1.encode(stream.toString()).length} >>\\nstream\\n${stream.toString()}\\nendstream');
    }
    objects[1] = '<< /Type /Pages /Kids [${pageRefs.join(' ')}] /Count $pageCount >>';
    final pdf = StringBuffer('%PDF-1.4\\n');
    final offsets = <int>[0];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(latin1.encode(pdf.toString()).length);
      pdf.write('${i + 1} 0 obj\\n${objects[i]}\\nendobj\\n');
    }
    final xref = latin1.encode(pdf.toString()).length;
    pdf.write('xref\\n0 ${objects.length + 1}\\n0000000000 65535 f \\n');
    for (var i = 1; i < offsets.length; i++) {
      pdf.write('${offsets[i].toString().padLeft(10, '0')} 00000 n \\n');
    }
    pdf.write('trailer\\n<< /Size ${objects.length + 1} /Root 1 0 R >>\\nstartxref\\n$xref\\n%%EOF');
    return _save('vehicle_report_${DateTime.now().millisecondsSinceEpoch}.pdf', latin1.encode(pdf.toString()));
  }
}
