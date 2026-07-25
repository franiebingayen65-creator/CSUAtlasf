import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class GPOAPdfGenerator {
  // 11 Columns: Program, SDGs, Objectives, Outcome, Participants, Time, Delivery, Resources(3), Type
  static final Map<int, pw.TableColumnWidth> _folioWidths = {
    0: const pw.FixedColumnWidth(110), // Program
    1: const pw.FixedColumnWidth(75),  // SDGs
    2: const pw.FixedColumnWidth(100), // Objectives
    3: const pw.FixedColumnWidth(95),  // Outcome
    4: const pw.FixedColumnWidth(95),  // Participants
    5: const pw.FixedColumnWidth(45),  // Timeframe
    6: const pw.FixedColumnWidth(80),  // Delivery
    7: const pw.FixedColumnWidth(65),  // RESOURCE: Persons
    8: const pw.FixedColumnWidth(65),  // RESOURCE: Facilities
    9: const pw.FixedColumnWidth(65),  // RESOURCE: Budget
    10: const pw.FixedColumnWidth(75), // Type of Activity
  };

  static Future<pw.Document> generateGPOADocument({
    required Map<String, dynamic> organization,
    required List<Map<String, dynamic>> activities,
    required Map<String, dynamic>? president,
    required Map<String, dynamic>? adviser,
    PdfPageFormat format = PdfPageFormat.a4, 
  }) async {
    final pdf = pw.Document();

    // Load fonts for cross-platform compatibility
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();
    
    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
      italic: fontItalic,
    );
    
    // Attempt to load images safely
    pw.ImageProvider? logo, iso, pilipinas, stars, aun, bldg;
    
    try { logo = await imageFromAssetBundle('assets/images/csulogo.png'); } catch (_) {}
    try { iso = await imageFromAssetBundle('assets/images/iso_pab.png'); } catch (_) {}
    try { pilipinas = await imageFromAssetBundle('assets/images/bagong_pilipinas.png'); } catch (_) {}
    try { stars = await imageFromAssetBundle('assets/images/qs_stars.png'); } catch (_) {}
    try { aun = await imageFromAssetBundle('assets/images/aun_qa.png'); } catch (_) {}
    try { bldg = await imageFromAssetBundle('assets/images/vision_mission_building.png'); } catch (_) {}

    final csuMaroon = PdfColor.fromHex('#800000');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: theme,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              // University Branding
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('CAGAYAN STATE UNIVERSITY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: csuMaroon)),
                        pw.Text('REPUBLIC OF THE PHILIPPINES', style: pw.TextStyle(fontSize: 9, color: csuMaroon)),
                        pw.Text('LAL-LO CAMPUS', style: pw.TextStyle(fontSize: 9, color: csuMaroon)),
                        pw.Text('Address', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: csuMaroon)),
                      ],
                    ),
                  ),
                  if (logo != null) pw.Container(height: 55, width: 55, child: pw.Image(logo)) else pw.SizedBox(width: 55, height: 55),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Email Address:', style: pw.TextStyle(fontSize: 8, color: csuMaroon)),
                        pw.Text('Website: www.csu.edu.ph', style: pw.TextStyle(fontSize: 8, color: csuMaroon)),
                        pw.Text('Facebook Page:', style: pw.TextStyle(fontSize: 8, color: csuMaroon)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              
              // Organization Name Centered Below Logo
              pw.Center(
                child: pw.Text(organization['name']?.toString().toUpperCase() ?? 'NAME OF ORGANIZATION', 
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5, color: PdfColors.black),
              pw.SizedBox(height: 12),
              
              // Top border for the table when it continues on Page 2+
              if (context.pageNumber > 1) 
                pw.Container(height: 0.5, color: PdfColors.black, width: double.infinity),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Container(margin: const pw.EdgeInsets.only(top: 10, bottom: 5), height: 0.5, color: PdfColors.black),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Spacer(),
                  if (iso != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 5), child: pw.Image(iso, height: 32)),
                  if (pilipinas != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 5), child: pw.Image(pilipinas, height: 32)),
                  if (stars != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 5), child: pw.Image(stars, height: 32)),
                  if (aun != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 5), child: pw.Image(aun, height: 32)),
                  if (bldg != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 10), child: pw.Image(bldg, height: 40)),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // Unified Table to ensure alignment across headers and data
            pw.Table(
              border: const pw.TableBorder(
                left: pw.BorderSide(width: 0.5),
                right: pw.BorderSide(width: 0.5),
                top: pw.BorderSide(width: 0.5),
                bottom: pw.BorderSide(width: 0.5),
                verticalInside: pw.BorderSide(width: 0.5),
                horizontalInside: pw.BorderSide(width: 0.5),
              ),
              columnWidths: _folioWidths,
              children: [
                // Header Row (only on first page content, but Table repeat header would be better if we could split it)
                // For now, consistent with standard MultiPage table behavior
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _headerCell('PROGRAM/\nACTIVITIES/\nPROJECT'),
                    _headerCell('SDGs\naddressed'),
                    _headerCell('OBJECTIVES'),
                    _headerCell('EXPECTED\nOUTCOME'),
                    _headerCell('TARGET\nPARTICIPANTS'),
                    _headerCell('TIME\nFRAME'),
                    _headerCell('DELIVERY\nSTRATEGY'),
                    _resourceHeader('PERSONS\nINVOLVED', showLabel: true),
                    _resourceHeader('FACILITIES/\nMATERIALS'),
                    _resourceHeader('BUDGET\nALLOCATION'),
                    _headerCell('Type of\nActivity'),
                  ],
                ),
                // Data Rows
                ... activities.map((act) => pw.TableRow(
                  children: [
                    _dataCell(act['title']),
                    _dataCell(act['sdgs']),
                    _dataCell(act['objectives']),
                    _dataCell(act['outcome']),
                    _dataCell(act['participants']),
                    _dataCell(act['time_frame']),
                    _dataCell(act['delivery_strategy']),
                    _dataCell(act['persons_involved']),
                    _dataCell(act['facilities_materials']),
                    _dataCell(act['budget_allocation']),
                    _dataCell(act['subtitle']),
                  ],
                )),
              ],
            ),
            
            pw.SizedBox(height: 35),
            
            // Signatures block
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _signatureUnit('Prepared by:', president?['full_name'] ?? '(Name of Student)', 'President'),
                _signatureUnit('Attested by:', adviser?['full_name'] ?? '(Adviser)', 'Adviser'),
                _signatureUnit('Noted by:', 'Donna Macadangdang', 'OSDW Coordinator'),
                _signatureUnit('Approved by:', 'Engr. James B. Cabildo', 'CEO, Lal-lo Campus'),
              ],
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  static Future<void> generateAndPrintGPOA({
    required Map<String, dynamic> organization,
    required List<Map<String, dynamic>> activities,
    required Map<String, dynamic>? president,
    required Map<String, dynamic>? adviser,
  }) async {
    // Lock to Folio Landscape
    final folioFormat = PdfPageFormat(8.5 * PdfPageFormat.inch, 13.0 * PdfPageFormat.inch).landscape;
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async {
      final pdf = await generateGPOADocument(
        organization: organization, 
        activities: activities, 
        president: president, 
        adviser: adviser,
        format: folioFormat,
      );
      return pdf.save();
    });
  }

  static pw.Widget _headerCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _resourceHeader(String text, {bool showLabel = false}) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          height: 18,
          width: double.infinity,
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
          child: showLabel ? pw.Text('RESOURCES', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)) : pw.SizedBox(),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.center,
          child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
        ),
      ],
    );
  }

  static pw.Widget _dataCell(dynamic text) {
    return pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(text?.toString() ?? '', style: const pw.TextStyle(fontSize: 10)));
  }

  static pw.Widget _signatureUnit(String label, String name, String position) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 35),
        pw.Text(name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
        pw.Text(position, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}
